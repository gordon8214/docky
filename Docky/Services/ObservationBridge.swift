//
//  ObservationBridge.swift
//  Docky
//
//  Bridge between the `Observation` framework's
//  `withObservationTracking` and Combine's `AnyCancellable` /
//  `Set<AnyCancellable>` lifecycle pattern. Lets the existing
//  `cancellables.store(in:)` ergonomics continue to work after
//  services migrate from `ObservableObject + @Published` to
//  `@Observable`.
//
//  Behavior: `observe(_:)` runs `action` once (registering reads of
//  any `@Observable` properties accessed inside it), then re-runs it
//  whenever any of those tracked properties changes — coalesced and
//  hopped to the main actor. The returned `AnyCancellable` stops
//  re-running on cancel/deallocate.
//
//  `observeChanges(of:perform:)` tracks only `read`, and calls
//  `perform` outside the tracking scope when the value changes. Use
//  it when `perform` builds views or reads other observable state:
//  nested `withObservationTracking` scopes merge their reads into
//  the outer scope, so anything `perform` reads would otherwise
//  re-run the whole observer.
//
//  Caveats vs. the Combine `.sink` pattern this replaces:
//    • `onChange` from `withObservationTracking` only fires once per
//      observation-window. We re-install on each change, so we don't
//      miss subsequent updates, but each fire is "any of the tracked
//      reads changed" without telling us which one.
//    • Equality dedupe is NOT free (Combine's `removeDuplicates()`
//      had to be opted in). Property setters that short-circuit on
//      equal values inside `didSet` still avoid emitting; the
//      Observation framework fires unconditionally otherwise.
//

import Combine
import Foundation
import Observation
import Synchronization

@discardableResult
@MainActor
func observeChanges(
    _ action: @escaping @MainActor () -> Void
) -> sending AnyCancellable {
    let state = ObserveBridgeState(action: action)
    state.install()
    return AnyCancellable { @Sendable in state.isCancelled = true }
}

private final class ObserveBridgeState: Sendable {
    private let cancelled = Mutex(false)
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    var isCancelled: Bool {
        get { cancelled.withLock { $0 } }
        set { cancelled.withLock { $0 = newValue } }
    }

    @MainActor func install() {
        guard !isCancelled else { return }
        withObservationTracking {
            self.action()
        } onChange: { [self] in
            // `onChange` is called from the mutating thread, before
            // the new value is installed. Re-install on the next
            // main-actor tick so reads inside `action()` see the
            // mutation result.
            Task { @MainActor in
                self.install()
            }
        }
    }
}

/// Calls `perform` with `read()` now, then again on the main actor whenever the
/// value `read` returns changes. Only `read` is tracked, and equal values are
/// skipped.
@discardableResult
@MainActor
func observeChanges<Value: Equatable>(
    of read: @escaping @MainActor () -> Value,
    perform: @escaping @MainActor (Value) -> Void
) -> sending AnyCancellable {
    let cancellation = ObserveCancellation()
    let state = ObserveValueState(read: read, perform: perform, cancellation: cancellation)
    state.install()
    // Capture only the flag: capturing the generic state would capture `Value`'s metatype.
    return AnyCancellable { @Sendable in cancellation.isCancelled = true }
}

private final class ObserveCancellation: Sendable {
    private let cancelled = Mutex(false)

    var isCancelled: Bool {
        get { cancelled.withLock { $0 } }
        set { cancelled.withLock { $0 = newValue } }
    }
}

@MainActor
private final class ObserveValueState<Value: Equatable> {
    private let read: @MainActor () -> Value
    private let perform: @MainActor (Value) -> Void
    private let cancellation: ObserveCancellation
    private var last: Value?

    init(
        read: @escaping @MainActor () -> Value, perform: @escaping @MainActor (Value) -> Void,
        cancellation: ObserveCancellation
    ) {
        self.read = read
        self.perform = perform
        self.cancellation = cancellation
    }

    func install() {
        guard !cancellation.isCancelled else { return }
        let value = withObservationTracking {
            read()
        } onChange: { [self] in
            Task { @MainActor in
                self.install()
            }
        }
        if let last, last == value { return }
        last = value
        perform(value)
    }
}

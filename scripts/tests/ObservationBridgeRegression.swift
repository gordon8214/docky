import Combine
import Foundation
import Observation
import Synchronization

@MainActor
@Observable
private final class Model {
    var value = 0
    var other = 0
}

@MainActor
private final class Readings {
    var values: [Int] = []
    var reads = 0
}

private final class TokenHolder: Sendable {
    let token: Mutex<AnyCancellable?>

    init(_ token: sending AnyCancellable) {
        self.token = Mutex(token)
    }
}

@main
private enum ObservationBridgeRegression {
    @MainActor
    static func main() async {
        let model = Model()
        let readings = Readings()
        let token = observeChanges {
            MainActor.preconditionIsolated()
            readings.values.append(model.value)
        }
        precondition(readings.values == [0], "Observation must run immediately")

        model.value = 1
        await waitUntil { readings.values == [0, 1] }
        model.value = 2
        await waitUntil { readings.values == [0, 1, 2] }

        model.value = 3
        token.cancel()
        await drainMainActor()
        precondition(readings.values == [0, 1, 2], "Cancellation must suppress a queued update")

        let backgroundReadings = Readings()
        let backgroundToken = TokenHolder(observeChanges {
            backgroundReadings.values.append(model.value)
        })
        model.value = 4
        cancelOnBackground(backgroundToken)
        await drainMainActor()
        model.value = 5
        await drainMainActor()
        precondition(backgroundReadings.values == [3], "Background cancellation must stop observation")

        let releasedReadings = Readings()
        var releasedToken: AnyCancellable? = observeChanges {
            releasedReadings.values.append(model.value)
        }
        precondition(releasedToken != nil)
        releasedToken = nil
        model.value = 6
        await drainMainActor()
        precondition(releasedReadings.values == [5], "Releasing the token must cancel observation")
        await checkValueObservation()
        print("Observation bridge regression checks passed")
    }

    /// `observeChanges(of:perform:)` tracks only `read`, skips equal values, and
    /// doesn't track what `perform` reads.
    @MainActor
    private static func checkValueObservation() async {
        let model = Model()
        let readings = Readings()
        let token = observeChanges(of: {
            readings.reads += 1
            return model.value / 2
        }) { half in
            _ = model.other
            readings.values.append(half)
        }
        precondition(readings.values == [0], "Value observation must run immediately")
        model.value = 1
        await drainMainActor()
        precondition(readings.values == [0], "An equal value must not call perform")
        model.value = 2
        await waitUntil { readings.values == [0, 1] }
        let reads = readings.reads
        model.other = 1
        await drainMainActor()
        // A tracked read would re-run `read`, even though the value stays equal.
        precondition(readings.reads == reads, "Reads inside perform must not be tracked")
        model.value = 4
        await waitUntil { readings.values == [0, 1, 2] }
        token.cancel()
        model.value = 6
        await drainMainActor()
        precondition(readings.values == [0, 1, 2], "Cancellation must stop value observation")
    }

    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Observation update exceeded its one-second budget")
            await Task.yield()
        }
    }

    @MainActor
    private static func drainMainActor() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    // Keep the main actor occupied until cancellation completes so the
    // observation's queued update cannot win the scheduling race.
    private static func cancelOnBackground(_ holder: TokenHolder) {
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            holder.token.withLock {
                $0?.cancel()
                $0 = nil
            }
            completed.signal()
        }
        precondition(completed.wait(timeout: .now() + 1) == .success, "Background cancellation stalled")
    }
}

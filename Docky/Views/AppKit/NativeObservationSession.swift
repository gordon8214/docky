import Combine

/// Reusable controllers stop UI observation while hidden and reconnect when reopened.
@MainActor
final class NativeObservationSession {
    private var factories: [@MainActor () -> AnyCancellable] = []
    private var subscriptions: [AnyCancellable] = []
    private var active = true
    func add(_ factory: @escaping @MainActor () -> AnyCancellable) {
        factories.append(factory)
        if active { subscriptions.append(factory()) }
    }
    func stop() {
        active = false
        subscriptions.removeAll()
    }
    func start() {
        guard !active else { return }
        active = true
        subscriptions = factories.map { $0() }
    }
}

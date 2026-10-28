import Foundation

/// One readiness result, with an injectable deadline for isolated tests.
final class WorkspaceStartup {
    enum State: Equatable { case waiting, ready, failed, stopped }
    private let lock = NSLock()
    private var current: State = .waiting
    private var timer: DispatchWorkItem?
    var state: State { lock.lock(); defer { lock.unlock() }; return current }

    init(timeout: TimeInterval = 30, queue: DispatchQueue = .main, onTimeout: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.finish(.failed, onlyWaiting: true) else { return }
            onTimeout()
        }
        timer = work
        queue.asyncAfter(deadline: .now() + timeout, execute: work)
    }
    @discardableResult func ready() -> Bool { finish(.ready, onlyWaiting: true) }
    @discardableResult func fail() -> Bool { finish(.failed, onlyWaiting: false) }
    func stop() { _ = finish(.stopped, onlyWaiting: false) }
    private func finish(_ result: State, onlyWaiting: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current == .waiting || (!onlyWaiting && current == .ready) else { return false }
        current = result; timer?.cancel(); timer = nil
        return true
    }
    deinit { timer?.cancel() }
}

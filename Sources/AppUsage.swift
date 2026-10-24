import Cocoa

/// Most-recently-used app order, so the switcher's default order matches the user's mental model.
final class AppUsage {
    static let shared = AppUsage()

    private let lock = NSLock()
    private var order: [pid_t] = []
    private var observer: NSObjectProtocol?

    func start() {
        if let front = NSWorkspace.shared.frontmostApplication {
            order = [front.processIdentifier]
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.record(app.processIdentifier)
        }
    }

    func record(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
        if order.count > 64 { order.removeLast() }
    }

    func index(of pid: pid_t) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return order.firstIndex(of: pid)
    }
}

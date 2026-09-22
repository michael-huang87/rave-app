import Foundation
import Network

/// Posts once when the path goes from unsatisfied → satisfied so screens refetch.
enum NetworkRestored {
    static let notification = Notification.Name("rave.networkRestored")

    private static let monitor = NWPathMonitor()
    private static let queue = DispatchQueue(label: "rave.network")
    private static let lock = NSLock()
    private static var wasOnline = true
    private static var started = false

    /// The last path the monitor reported. Starts optimistic so a launch with a signal does not
    /// wait for the first callback before it may sync.
    static var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wasOnline
    }

    static func start() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            lock.lock()
            let becameOnline = online && !wasOnline
            wasOnline = online
            lock.unlock()
            if becameOnline {
                NotificationCenter.default.post(name: notification, object: nil)
            }
        }
        monitor.start(queue: queue)
    }
}

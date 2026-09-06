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

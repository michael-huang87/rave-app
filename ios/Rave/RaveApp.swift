import SwiftUI

@main
struct RaveApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NetworkRestored.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .task { await APIClient.shared.drainPendingWrites() }
                .onReceive(NotificationCenter.default.publisher(for: NetworkRestored.notification)) { _ in
                    Task { await APIClient.shared.drainPendingWrites() }
                }
                .onChange(of: scenePhase) { _, now in
                    // Signal at a festival comes back without the path ever going unsatisfied, so
                    // waking the app is its own chance to drain.
                    if now == .active { Task { await APIClient.shared.drainPendingWrites() } }
                }
        }
    }
}

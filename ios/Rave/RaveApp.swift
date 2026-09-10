import SwiftUI

@main
struct RaveApp: App {
    init() {
        NetworkRestored.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

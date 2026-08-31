import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            EventListView()
                .tabItem { Label("Shows", systemImage: "sparkles") }
            SetsListView()
                .tabItem { Label("Sets", systemImage: "music.note.list") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "trophy") }
            RecapView()
                .tabItem { Label("Recap", systemImage: "chart.bar.fill") }
        }
        .tint(RaveTheme.accent)
    }
}

#Preview {
    ContentView()
}

import SwiftUI

private enum RaveTab: Hashable {
    case festival, shows, sets, stats, recap
}

struct ContentView: View {
    @AppStorage(FestivalMode.storageKey) private var festivalEventId = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var festival: Event?
    @State private var selection = RaveTab.shows

    var body: some View {
        TabView(selection: $selection) {
            if let festival {
                ScheduleView(event: festival, presentation: .tab) {}
                    .tabItem { Label("Festival", systemImage: "tent.fill") }
                    .tag(RaveTab.festival)
            }
            EventListView()
                .tabItem { Label("Shows", systemImage: "sparkles") }
                .tag(RaveTab.shows)
            SetsListView()
                .tabItem { Label("Sets", systemImage: "music.note.list") }
                .tag(RaveTab.sets)
            StatsView()
                .tabItem { Label("Stats", systemImage: "trophy") }
                .tag(RaveTab.stats)
            RecapView()
                .tabItem { Label("Recap", systemImage: "chart.bar.fill") }
                .tag(RaveTab.recap)
        }
        .tint(RaveTheme.accent)
        .task {
            await resolve()
            if festival != nil { selection = .festival }
        }
        .onChange(of: festivalEventId) { Task { await resolve() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await resolve() } }
        }
    }

    /// A failed load is no evidence the festival is over, so it leaves the mode armed and the tab
    /// standing. The cached events list is enough to decide, which matters on festival signal.
    @MainActor
    private func resolve() async {
        guard !festivalEventId.isEmpty else { return disarm() }
        guard let read = try? await APIClient.shared.events() else { return }
        guard let event = read.value.first(where: { $0.id == festivalEventId }),
              FestivalMode.isActive(event) else {
            festivalEventId = ""
            return disarm()
        }
        festival = event
    }

    private func disarm() {
        festival = nil
        if selection == .festival { selection = .shows }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

private enum RaveTab: Hashable {
    case festival, shows, sets, stats, recap
}

struct ContentView: View {
    @AppStorage(FestivalMode.storageKey) private var overrideRaw = ""
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
        .task { await resolve(select: true) }
        .onChange(of: overrideRaw) { Task { await resolve(select: false) } }
        // Reopening the app during a festival lands on the schedule again. Switching tabs by hand
        // does not, so nothing moves under you mid-session.
        .onChange(of: scenePhase) { was, now in
            if now == .active, was == .background { Task { await resolve(select: true) } }
        }
    }

    /// A failed load is no evidence the festival is over, so it leaves the tab standing. The
    /// last-read events list is enough to decide, which matters on festival signal.
    @MainActor
    private func resolve(select: Bool) async {
        guard let read = try? await APIClient.shared.events() else { return }
        let events = read.value

        var override = FestivalMode.Override(raw: overrideRaw)
        if let id = override.eventId, let named = events.first(where: { $0.id == id }),
           FestivalMode.hasEnded(named) {
            overrideRaw = ""
            override = .auto
        }

        for candidate in FestivalMode.candidates(in: events, override: override) {
            guard await hasSchedule(candidate.id) else { continue }
            festival = candidate
            if select { selection = .festival }
            return
        }
        clear()
    }

    /// A festival with no schedule has no tab to offer. A cached one still counts, or the tab would
    /// vanish exactly when the signal does.
    private func hasSchedule(_ eventId: String) async -> Bool {
        if let cached = await ScheduleStore.shared.record(for: eventId), !cached.schedule.slots.isEmpty {
            return true
        }
        return (try? await APIClient.shared.schedule(eventId: eventId))?.slots.isEmpty == false
    }

    private func clear() {
        festival = nil
        if selection == .festival { selection = .shows }
    }
}

#Preview {
    ContentView()
}

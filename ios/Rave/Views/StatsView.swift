import SwiftUI

/// The sheet's ArtistsVenues tab, in the app. Artists count sets seen; venues and cities
/// count distinct days, which is how the sheet's own formulas do it.
struct StatsView: View {
    @State private var stats: Stats?
    @State private var error: String?
    @State private var fromCache = false
    @State private var cachedAt: Date?
    @State private var refreshing: Bool

    init() {
        let hit = LastReadStore.shared.load(Stats.self, key: .stats)
        _stats = State(initialValue: hit?.payload)
        _cachedAt = State(initialValue: hit?.savedAt)
        _refreshing = State(initialValue: hit != nil)
    }

    private static let preview = 10

    var body: some View {
        NavigationStack {
            Group {
                if let stats {
                    List {
                        section("Artists", "sets seen", stats.artists)
                        section("Venues", "days", stats.venues)
                        section("Cities", "days", stats.cities)
                    }
                    .scrollContentBackground(.hidden)
                } else if let error {
                    ContentUnavailableView {
                        Label("No stats yet", systemImage: "trophy")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .background(RaveTheme.bg)
            .navigationTitle("Stats")
            .safeAreaInset(edge: .top, spacing: 0) {
                CacheStatusBar(fromCache: fromCache, cachedAt: cachedAt, refreshing: refreshing)
            }
            .task { await load() }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: NetworkRestored.notification)) { _ in
                Task { await load() }
            }
            .navigationDestination(for: StatList.self) { list in
                RankedList(title: list.title, unit: list.unit, counts: list.counts)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ unit: String, _ counts: [StatCount]) -> some View {
        Section(title) {
            ForEach(counts.prefix(Self.preview)) { row(unit, $0) }
                .listRowBackground(RaveTheme.card)
            if counts.count > Self.preview {
                NavigationLink(value: StatList(title: title, unit: unit, counts: counts)) {
                    Text("All \(counts.count)").foregroundStyle(RaveTheme.accent)
                }
                .listRowBackground(RaveTheme.card)
            }
        }
    }

    @MainActor
    private func load() async {
        if stats == nil, let hit = LastReadStore.shared.load(Stats.self, key: .stats) {
            stats = hit.payload
            cachedAt = hit.savedAt
            fromCache = false
            refreshing = true
            error = nil
        } else {
            refreshing = stats != nil
        }
        do {
            let read = try await APIClient.shared.stats()
            stats = read.value
            fromCache = read.fromCache
            cachedAt = read.cachedAt
            error = nil
            refreshing = false
        } catch {
            self.error = stats == nil ? error.localizedDescription : nil
            if stats != nil { fromCache = true }
            refreshing = false
        }
    }
}

private struct StatList: Hashable {
    let title: String
    let unit: String
    let counts: [StatCount]
}

@ViewBuilder
private func row(_ unit: String, _ count: StatCount) -> some View {
    HStack {
        Text(count.name)
            .foregroundStyle(.white)
            .lineLimit(1)
        Spacer(minLength: 8)
        Text("\(count.count)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(RaveTheme.accent2)
        Text(unit)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct RankedList: View {
    let title: String
    let unit: String
    let counts: [StatCount]

    var body: some View {
        List {
            ForEach(counts) { row(unit, $0) }
                .listRowBackground(RaveTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(RaveTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

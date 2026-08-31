import SwiftUI

/// The sheet's ArtistsVenues tab, in the app. Artists count sets seen; venues and cities
/// count distinct days, which is how the sheet's own formulas do it.
struct StatsView: View {
    @State private var stats: Stats?
    @State private var error: String?

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
            .task { await load() }
            .refreshable { await load() }
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
        do { stats = try await APIClient.shared.stats() }
        catch { self.error = error.localizedDescription }
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

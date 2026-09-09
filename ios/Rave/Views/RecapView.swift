import SwiftUI

struct RecapView: View {
    @State private var recap: Recap?
    @State private var error: String?
    @State private var fromCache = false
    @State private var cachedAt: Date?

    var body: some View {
        NavigationStack {
            Group {
                if let recap {
                    List {
                        Section("All-time") {
                            recapBlock(recap.allTime)
                        }
                        ForEach(recap.byYear.keys.sorted(by: >), id: \.self) { year in
                            if let bucket = recap.byYear[year] {
                                Section(year) { recapBlock(bucket) }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else if let error {
                    ContentUnavailableView {
                        Label("No recap yet", systemImage: "chart.bar")
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
            .navigationTitle("Recap")
            .safeAreaInset(edge: .top, spacing: 0) {
                if fromCache { OfflineBanner(cachedAt: cachedAt) }
            }
            .task { await load() }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: NetworkRestored.notification)) { _ in
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func recapBlock(_ b: RecapBucket) -> some View {
        LabeledContent("Sets", value: "\(b.sets)")
        LabeledContent("Artists", value: "\(b.artists)")
        LabeledContent("Shows", value: "\(b.shows)")
        LabeledContent("Events", value: "\(b.events)")
        LabeledContent("Spend", value: b.spend.usd)
        LabeledContent("Ticket", value: b.spendByType.ticket.usd)
        LabeledContent("Travel", value: b.spendByType.travel.usd)
        LabeledContent("Drinks / Food / Merch", value: b.spendByType.drinksFoodMerch.usd)
        if let top = b.topArtist {
            LabeledContent("Top artist", value: "\(top.name) (\(top.count))")
        }
        if let city = b.topCity {
            LabeledContent("Top city", value: "\(city.name) (\(city.count))")
        }
        if let most = b.mostSets {
            LabeledContent("Most sets", value: "\(most.name) (\(most.count))")
        }
        if let best = b.bestDollarsPerSet {
            LabeledContent("Best $/set", value: "\(best.name) (\(best.dollarsPerSet.usd))")
        }
    }

    @MainActor
    private func load() async {
        do {
            let read = try await APIClient.shared.recap()
            recap = read.value
            fromCache = read.fromCache
            cachedAt = read.cachedAt
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import SwiftUI

struct RecapView: View {
    @State private var recap: Recap?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if recap != nil {
                    List {
                        ForEach(periods, id: \.title) { period in
                            Section(period.title) {
                                summary(period.bucket)
                                NavigationLink(value: period) {
                                    Text("Highlights & spend")
                                        .foregroundStyle(RaveTheme.accent)
                                }
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
            .task { await load() }
            .refreshable { await load() }
            .navigationDestination(for: RecapPeriod.self) { RecapDetailView(period: $0) }
        }
    }

    /// All-time first, then years newest first. Both navigate to the same detail page.
    private var periods: [RecapPeriod] {
        guard let recap else { return [] }
        return [RecapPeriod(title: "All-time", bucket: recap.allTime)]
            + recap.byYear.keys.sorted(by: >).compactMap { year in
                recap.byYear[year].map { RecapPeriod(title: year, bucket: $0) }
            }
    }

    @ViewBuilder
    private func summary(_ b: RecapBucket) -> some View {
        LabeledContent("Sets", value: "\(b.sets)")
        LabeledContent("Artists", value: "\(b.artists)")
        LabeledContent("Shows", value: "\(b.shows)")
        LabeledContent("Events", value: "\(b.events)")
        LabeledContent("Spend", value: b.spend.usd)
    }

    @MainActor
    private func load() async {
        do { recap = try await APIClient.shared.recap() }
        catch { self.error = error.localizedDescription }
    }
}

private struct RecapPeriod: Hashable {
    let title: String
    let bucket: RecapBucket
}

private struct RecapDetailView: View {
    let period: RecapPeriod

    var body: some View {
        List {
            Section("Spend") {
                LabeledContent("Ticket", value: period.bucket.spendByType.ticket.usd)
                LabeledContent("Travel", value: period.bucket.spendByType.travel.usd)
                LabeledContent("Drinks / Food / Merch", value: period.bucket.spendByType.drinksFoodMerch.usd)
                LabeledContent("Total", value: period.bucket.spend.usd)
            }
            if !highlights.isEmpty {
                Section("Highlights") {
                    ForEach(highlights, id: \.label) {
                        LabeledContent($0.label, value: $0.value)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RaveTheme.bg)
        .navigationTitle(period.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A year with events but no logged sets has none of these, so the section drops out.
    private var highlights: [(label: String, value: String)] {
        let b = period.bucket
        return [
            b.topArtist.map { (label: "Top artist", value: "\($0.name) (\($0.count))") },
            b.topCity.map { (label: "Top city", value: "\($0.name) (\($0.count))") },
            b.mostSets.map { (label: "Most sets", value: "\($0.name) (\($0.count))") },
            b.bestDollarsPerSet.map { (label: "Best $/set", value: "\($0.name) (\($0.dollarsPerSet.usd))") },
        ].compactMap { $0 }
    }
}

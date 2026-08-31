import SwiftUI

struct RecapView: View {
    @State private var recap: Recap?
    @State private var error: String?

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
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func recapBlock(_ b: RecapBucket) -> some View {
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

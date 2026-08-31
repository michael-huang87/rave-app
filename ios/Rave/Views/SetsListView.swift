import SwiftUI

struct SetsListView: View {
    @State private var sets: [SetEntry] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading && sets.isEmpty {
                    ProgressView("Loading sets…")
                } else if let error, sets.isEmpty {
                    ContentUnavailableView {
                        Label("Backend not reachable", systemImage: "wifi.slash")
                    } description: {
                        Text("URL: \(APIClient.configuredBaseURL)\n\n\(error)")
                    } actions: {
                        Button("Retry") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .background(RaveTheme.bg)
            .navigationTitle("Sets")
            .searchable(text: $query, prompt: "Artist, set, show, or venue")
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private var list: some View {
        List {
            ForEach(days, id: \.key) { day in
                Section {
                    ForEach(day.values) { entry in
                        NavigationLink(value: entry.eventId) {
                            SetRow(entry: entry)
                        }
                        .listRowBackground(RaveTheme.card)
                        .listRowInsets(RaveTheme.rowInsets)
                    }
                } header: {
                    Text(Self.dayTitle(day.key, day.values.first))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .listRowInsets(RaveTheme.headerInsets)
                }
            }
        }
        .listStyle(.plain)
        // A List row is 44pt tall before its content has any say, which is most of a one-line row.
        .environment(\.defaultMinListRowHeight, 30)
        .scrollContentBackground(.hidden)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationDestination(for: String.self) { id in
            EventDetailView(eventId: id)
        }
    }

    private var filtered: [SetEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sets }
        return sets.filter { entry in
            ([entry.title, entry.show, entry.venue].compactMap { $0 } + entry.artists)
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// The date, show, and venue repeat for every set of a night, so they live in the header
    /// instead of on 1248 rows. Sheet order inside a day is preserved by `grouped`.
    private var days: [(key: String, values: [SetEntry])] {
        filtered.grouped { $0.date ?? "" }
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, yyyy"
        return f
    }()

    private static func dayTitle(_ iso: String, _ entry: SetEntry?) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        let date = parse.date(from: iso).map { headerFormatter.string(from: $0) } ?? "Undated"
        return ([date, entry?.show, entry?.venue]
            .compactMap { $0 }
            .filter { !$0.isEmpty })
            .joined(separator: " · ")
    }

    @MainActor
    private func reload() async {
        loading = sets.isEmpty
        error = nil
        do {
            sets = try await APIClient.shared.sets()
            loading = false
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

private struct SetRow: View {
    let entry: SetEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.title)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            // Most sets name a single artist matching the title; only b2b rows add anything.
            if entry.artists != [entry.title] {
                Spacer(minLength: 8)
                Text(entry.artists.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(RaveTheme.accent2)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }
}

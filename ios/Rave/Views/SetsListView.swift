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
            ForEach(filtered) { entry in
                NavigationLink(value: entry.eventId) {
                    SetRow(entry: entry)
                }
                .listRowBackground(RaveTheme.card)
            }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .foregroundStyle(.white)
            // Most sets name a single artist matching the title; only b2b rows add anything.
            if entry.artists != [entry.title] {
                Text(entry.artists.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(RaveTheme.accent2)
            }
            Text([entry.date, entry.show, entry.venue]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

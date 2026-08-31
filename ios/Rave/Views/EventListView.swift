import SwiftUI

struct EventListView: View {
    @State private var events: [Event] = []
    @State private var filter: EventStatus? = nil
    @State private var error: String?
    @State private var loading = true
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && events.isEmpty {
                    ProgressView("Loading shows…")
                } else if let error, events.isEmpty {
                    ContentUnavailableView {
                        Label("Backend not reachable", systemImage: "wifi.slash")
                    } description: {
                        Text("URL: \(APIClient.configuredBaseURL)\n\n\(error)\n\nIf Safari works but this app does not, open Settings → Rave and turn on Cellular Data and Local Network. Confirm Tailscale is connected, then tap Retry.")
                    } actions: {
                        Button("Retry") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .background(RaveTheme.bg)
            .navigationTitle("Rave")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                EventFormView { await reload() }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private var list: some View {
        List {
            Picker("Status", selection: $filter) {
                Text("All").tag(Optional<EventStatus>.none)
                ForEach(EventStatus.allCases) { s in
                    Text(s.label).tag(Optional(s))
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(filtered) { event in
                NavigationLink(value: event.id) {
                    EventRow(event: event)
                }
                .listRowBackground(RaveTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(for: String.self) { id in
            EventDetailView(eventId: id)
        }
    }

    private var filtered: [Event] {
        guard let filter else { return events }
        return events.filter { $0.status == filter }
    }

    @MainActor
    private func reload() async {
        loading = events.isEmpty
        error = nil
        do {
            events = try await APIClient.shared.events()
            loading = false
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

private struct EventRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.show)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(event.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(event.status.tint.opacity(0.2))
                    .foregroundStyle(event.status.tint)
                    .clipShape(Capsule())
            }
            Text([event.dateDisplay ?? event.startDate, event.venue, event.city]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(event.setsLogged) sets")
                Spacer()
                Text(event.total.usd)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(RaveTheme.accent2)
        }
        .padding(.vertical, 4)
    }
}

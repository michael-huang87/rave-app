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
        VStack(spacing: 0) {
            // Pinned above the list: scrolling it away costs a swipe back for every filter change.
            Picker("Status", selection: $filter) {
                Text("All").tag(Optional<EventStatus>.none)
                ForEach(EventStatus.allCases) { s in
                    Text(s.label).tag(Optional(s))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            rows
        }
    }

    private var rows: some View {
        List {
            ForEach(months, id: \.key) { month in
                Section {
                    ForEach(month.values) { event in
                        NavigationLink(value: event.id) {
                            EventRow(event: event)
                        }
                        .listRowBackground(RaveTheme.card)
                        .listRowInsets(RaveTheme.rowInsets)
                    }
                } header: {
                    HStack {
                        Text(Self.monthTitle(month.key))
                        Spacer()
                        Text("\(month.values.count)")
                    }
                    .font(.caption.weight(.semibold))
                    .listRowInsets(RaveTheme.headerInsets)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 30)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: String.self) { id in
            EventDetailView(eventId: id)
        }
    }

    private var filtered: [Event] {
        guard let filter else { return events }
        return events.filter { $0.status == filter }
    }

    /// The server sends newest-first. Under Planned that buries the next show at the bottom,
    /// so only that filter flips to soonest-first.
    private var months: [(key: String, values: [Event])] {
        let ordered = filter == .planned ? filtered.reversed().map { $0 } : filtered
        return ordered.grouped { String(($0.startDate ?? "").prefix(7)) }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static func monthTitle(_ key: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM"
        guard let date = parse.date(from: key) else { return "Undated" }
        return monthFormatter.string(from: date)
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

    /// One line so the month reads at a glance. Sets, spend, and city stay on the detail screen;
    /// status is the date's colour rather than a capsule that would cost the line its width.
    var body: some View {
        HStack(spacing: 8) {
            Text(day)
                .font(.caption.monospacedDigit())
                .foregroundStyle(event.status.tint)
                .frame(width: 34, alignment: .leading)
            Text(event.show)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let location = event.venue ?? event.city, !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }

    /// Day of month; the section header already carries the month and year.
    private var day: String {
        guard let iso = event.startDate, iso.count >= 10 else { return "" }
        return String(iso.suffix(2))
    }
}

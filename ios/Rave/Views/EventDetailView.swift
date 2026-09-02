import SwiftUI

struct EventDetailView: View {
    let eventId: String
    @State private var event: Event?
    @State private var error: String?
    @State private var showSpend = false
    @State private var showSet = false
    @State private var showEdit = false

    var body: some View {
        Group {
            if let event {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(event)
                        spendCard(event)
                        setsCard(event)
                    }
                    .padding()
                }
            } else if let error {
                ContentUnavailableView("Could not load show", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .background(RaveTheme.bg)
        .navigationTitle(event?.show ?? "Show")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
                    .disabled(event == nil)
            }
        }
        .sheet(isPresented: $showSpend) {
            if let event { LogSpendView(event: event) { await reload() } }
        }
        .sheet(isPresented: $showSet) {
            if let event { LogSetView(event: event) { await reload() } }
        }
        .sheet(isPresented: $showEdit) {
            if let event { EventFormView(existing: event) { await reload() } }
        }
        .task { await reload() }
    }

    private func header(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(event.status.tint)
            Text(event.dateDisplay ?? event.startDate ?? "")
                .font(.title3.weight(.semibold))
            if event.isFestival, let days = event.days {
                Label("Festival · \(days) days", systemImage: "tent.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RaveTheme.accent)
            }
            if let venue = event.venue { Text(venue) }
            if let city = event.city { Text(city).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spendCard(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spend").font(.headline)
                Spacer()
                Button("Log spend") { showSpend = true }
            }
            spendRow("Ticket", event.ticket)
            spendRow("Travel", event.travel)
            spendRow("Drinks / Food / Merch", event.drinksFoodMerch)
            Divider()
            spendRow("Total", event.total, emphasize: true)
            if let per = event.dollarsPerSet {
                spendRow("$ per set", per)
            } else {
                Text("$ per set is blank when no sets are logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RaveTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func spendRow(_ label: String, _ value: Double, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.usd).monospacedDigit()
        }
        .font(emphasize ? .body.weight(.semibold) : .body)
    }

    private func setsTitle(_ event: Event) -> String {
        // The sheet's own count; the qualifier disappears once the gap is reconciled.
        guard let sheet = event.setsSheet, sheet > event.setsLogged else {
            return "Sets (\(event.setsLogged))"
        }
        return "Sets (\(event.setsLogged) of \(sheet) on sheet)"
    }

    private func setsCard(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(setsTitle(event)).font(.headline)
                Spacer()
                Button("Log a set") { showSet = true }
            }
            if let sets = event.sets, !sets.isEmpty {
                let nights = sets.grouped { $0.date ?? "" }
                ForEach(Array(nights.enumerated()), id: \.element.key) { index, night in
                    if nights.count > 1 {
                        Text(Self.nightTitle(night.key, index: index, start: event.startDate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RaveTheme.accent)
                            .padding(.top, index == 0 ? 0 : 8)
                    }
                    ForEach(night.values) { set in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title).font(.body.weight(.medium))
                            Text(set.artists.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("No sets logged yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RaveTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static let nightFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Day numbers come off the event's start date, so a night with nothing logged still counts.
    private static func nightTitle(_ iso: String, index: Int, start: String?) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        parse.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let date = parse.date(from: iso)
        var number = index + 1
        if let date, let start, let from = parse.date(from: start),
           let offset = calendar.dateComponents([.day], from: from, to: date).day, offset >= 0 {
            number = offset + 1
        }
        return ["Day \(number)", date.map { nightFormatter.string(from: $0) }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @MainActor
    private func reload() async {
        do { event = try await APIClient.shared.event(id: eventId) }
        catch { self.error = error.localizedDescription }
    }
}

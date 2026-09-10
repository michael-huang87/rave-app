import SwiftUI

struct EventDetailView: View {
    let eventId: String
    @State private var event: Event?
    @State private var error: String?
    @State private var showSpend = false
    @State private var showAdd = false
    @State private var showEdit = false
    @State private var showSchedule = false
    @State private var scheduleSlots = 0
    @State private var editing: SetEntry?

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
        .sheet(isPresented: $showAdd) {
            if let event { QuickAddSetsView(event: event) { await reload() } }
        }
        .sheet(item: $editing) { set in
            EditSetView(set: set) { await reload() }
        }
        .sheet(isPresented: $showEdit) {
            if let event { EventFormView(existing: event) { await reload() } }
        }
        .sheet(isPresented: $showSchedule) {
            if let event { ScheduleView(event: event) { await reload() } }
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
                // The long title form plus both buttons overruns the card by 21pt, so a schedule collapses them.
                if scheduleSlots > 0 {
                    Menu {
                        Button("Add artists") { showAdd = true }
                        Button("Set times") { showSchedule = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    Button("Add artists") { showAdd = true }
                }
            }
            if let sets = event.sets, !sets.isEmpty {
                let nights = sets.grouped { $0.date ?? "" }
                ForEach(Array(nights.enumerated()), id: \.element.key) { index, night in
                    if nights.count > 1 {
                        Text(nightLabel(night.key, index: index, start: event.startDate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RaveTheme.accent)
                            .padding(.top, index == 0 ? 0 : 8)
                    }
                    ForEach(night.values) { set in
                        Button { editing = set } label: { setRow(set) }
                            .buttonStyle(.plain)
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

    private func setRow(_ set: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.title)
                .font(.body.weight(.medium))
            // Most sets name a single artist matching the title; only b2b rows add anything.
            if set.artists != [set.title] {
                Text(set.artists.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(RaveTheme.accent2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @MainActor
    private func reload() async {
        async let loaded = APIClient.shared.event(id: eventId)
        async let slots = APIClient.shared.schedule(eventId: eventId).slots.count
        do { event = try await loaded }
        catch { self.error = error.localizedDescription }
        // Most events never get a schedule, so a failed lookup just leaves the button hidden.
        scheduleSlots = (try? await slots) ?? 0
    }
}

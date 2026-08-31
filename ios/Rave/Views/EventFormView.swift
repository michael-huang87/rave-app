import SwiftUI

struct EventFormView: View {
    var existing: Event? = nil
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var show = ""
    @State private var venue = ""
    @State private var city = ""
    @State private var start = ""
    @State private var end = ""
    @State private var ticket = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    TextField("Show / festival", text: $show)
                    TextField("Venue", text: $venue)
                    TextField("City", text: $city)
                    TextField("Start date (YYYY-MM-DD)", text: $start)
                    TextField("End date (optional)", text: $end)
                }
                if existing == nil {
                    Section("Ticket (optional)") {
                        TextField("0.00", text: $ticket)
                            .keyboardType(.decimalPad)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(existing == nil ? "Add show" : "Edit show")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(show.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                if let existing {
                    show = existing.show
                    venue = existing.venue ?? ""
                    city = existing.city ?? ""
                    start = existing.startDate ?? ""
                    end = existing.endDate ?? ""
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        do {
            if let existing {
                _ = try await APIClient.shared.updateEvent(
                    id: existing.id,
                    show: show,
                    venue: venue.nilIfEmpty,
                    city: city.nilIfEmpty,
                    startDate: start.nilIfEmpty,
                    endDate: end.nilIfEmpty
                )
            } else {
                _ = try await APIClient.shared.createEvent(
                    EventDraft(
                        show: show,
                        venue: venue.nilIfEmpty,
                        city: city.nilIfEmpty,
                        startDate: start.nilIfEmpty,
                        endDate: end.nilIfEmpty,
                        ticket: Double(ticket) ?? 0,
                        travel: 0,
                        drinksFoodMerch: 0
                    )
                )
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

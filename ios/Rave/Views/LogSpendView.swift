import SwiftUI

struct LogSpendView: View {
    let event: Event
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ticket = ""
    @State private var travel = ""
    @State private var merch = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Buckets") {
                    TextField("Ticket", text: $ticket).keyboardType(.decimalPad)
                    TextField("Travel", text: $travel).keyboardType(.decimalPad)
                    TextField("Drinks / Food / Merch", text: $merch).keyboardType(.decimalPad)
                }
                Section {
                    Text("Total and $ per set are computed. Blank buckets count as $0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Log spend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .onAppear {
                ticket = String(event.ticket)
                travel = String(event.travel)
                merch = String(event.drinksFoodMerch)
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        do {
            _ = try await APIClient.shared.logSpend(
                eventId: event.id,
                spend: SpendDraft(
                    ticket: Double(ticket) ?? 0,
                    travel: Double(travel) ?? 0,
                    drinksFoodMerch: Double(merch) ?? 0
                )
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}

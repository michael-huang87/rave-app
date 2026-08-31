import SwiftUI

struct LogSetView: View {
    let event: Event
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artists = ""
    @State private var date = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Set title (e.g. Kill the Noise b2b Trivecta)", text: $title)
                    TextField("Artists, comma-separated", text: $artists)
                    TextField("Date (YYYY-MM-DD)", text: $date)
                }
                Section {
                    Text("Venue and city come from \(event.show) — you don't retype them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Log a set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear { date = event.startDate ?? "" }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        let names = artists.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            _ = try await APIClient.shared.logSet(
                eventId: event.id,
                draft: SetDraft(
                    title: title,
                    artists: names.isEmpty ? [title] : names,
                    date: date.isEmpty ? event.startDate : date
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

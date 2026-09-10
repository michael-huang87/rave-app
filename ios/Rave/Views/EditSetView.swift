import SwiftUI

struct EditSetView: View {
    let set: SetEntry
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artists: String
    @State private var date: String
    @State private var artistsEdited = false
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var saving = false

    init(set: SetEntry, onSaved: @escaping () async -> Void) {
        self.set = set
        self.onSaved = onSaved
        _title = State(initialValue: set.title)
        _artists = State(initialValue: set.artists.joined(separator: ", "))
        _date = State(initialValue: set.date ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Set title (e.g. Kill the Noise b2b Trivecta)", text: $title)
                    TextField("Artists, comma-separated", text: Binding(
                        get: { artists },
                        set: { artists = $0; artistsEdited = true }
                    ))
                    TextField("Date (YYYY-MM-DD)", text: $date)
                }
                Section {
                    Button("Delete set", role: .destructive) { confirmingDelete = true }
                        .disabled(saving)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit set")
            // Renaming a row to "A b2b B" is how two artists get merged, so the artists follow the title
            // until the user takes the field over.
            .onChange(of: title) { _, renamed in
                guard !artistsEdited else { return }
                artists = names(from: renamed, separator: " b2b ").joined(separator: ", ")
            }
            .confirmationDialog("Delete this set?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await remove() } }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func names(from text: String, separator: String) -> [String] {
        text.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        let artistNames = names(from: artists, separator: ",")
        do {
            _ = try await APIClient.shared.updateSet(
                id: set.id,
                patch: SetPatch(
                    title: title,
                    artists: artistNames.isEmpty ? [title] : artistNames,
                    date: date.isEmpty ? nil : date
                )
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }

    @MainActor
    private func remove() async {
        saving = true
        error = nil
        do {
            try await APIClient.shared.deleteSet(id: set.id)
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}

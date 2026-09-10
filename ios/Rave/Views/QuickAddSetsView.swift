import SwiftUI

struct QuickAddSetsView: View {
    let event: Event
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var pending: [String] = []
    @State private var night = ""
    @State private var known: [String] = []
    @State private var error: String?
    @State private var saving = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Form {
                if event.nights.count > 1 {
                    Section("Night") {
                        Picker("Night", selection: $night) {
                            ForEach(Array(event.nights.enumerated()), id: \.element) { index, iso in
                                Text(nightLabel(iso, index: index, start: event.startDate)).tag(iso)
                            }
                        }
                    }
                }
                Section {
                    TextField("Artist", text: $entry)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { commit(entry) }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                if !suggestions.isEmpty {
                    Section("Already in your data") {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { commit(name) }
                        }
                    }
                }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending, id: \.self) { Text($0) }
                            .onDelete { pending.remove(atOffsets: $0) }
                            .onMove { pending.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        HStack {
                            Text("Adding (\(pending.count))")
                            Spacer()
                            // The order is the order the sets were seen, and .onMove only drags in edit mode.
                            EditButton()
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add artists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(pending.isEmpty || saving)
                }
            }
            .onAppear {
                let today = Self.isoDay.string(from: Date())
                night = event.nights.contains(today) ? today : (event.nights.first ?? "")
                typing = true
            }
            // The last-read cache is welcome here: suggesting names from the last good load beats
            // suggesting nothing when the field is the whole point of the screen.
            .task { known = (try? await APIClient.shared.stats())?.value.artists.map(\.name) ?? [] }
        }
    }

    private var suggestions: [String] {
        let query = entry.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let taken = Set(pending.map { $0.lowercased() })
        let hits = known.filter { !taken.contains($0.lowercased()) && $0.localizedCaseInsensitiveContains(query) }
        let starts = hits.filter { $0.lowercased().hasPrefix(query) }
        return Array((starts + hits.filter { !$0.lowercased().hasPrefix(query) }).prefix(6))
    }

    /// Commas and newlines both split, so a list pasted off a lineup poster lands as separate artists.
    private func commit(_ text: String) {
        let names = text
            .split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for name in names where !pending.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            pending.append(name)
        }
        entry = ""
        typing = true
    }

    /// Local, not GMT like the model's: at a show on the US west coast at 11pm, GMT is already
    /// tomorrow and would default the picker to the wrong night.
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    private func save() async {
        saving = true
        error = nil
        do {
            _ = try await APIClient.shared.bulkAddSets(
                eventId: event.id,
                draft: BulkSetsDraft(
                    artists: pending,
                    date: event.nights.count > 1 ? night : event.startDate
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

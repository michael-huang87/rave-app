import SwiftUI

struct ScheduleView: View {
    let event: Event
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var schedule: Schedule?
    @State private var day = ""
    @State private var selected: Set<String> = []
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Group {
                if let schedule {
                    list(schedule)
                } else if let error {
                    ContentUnavailableView {
                        Label("Backend not reachable", systemImage: "wifi.slash")
                    } description: {
                        Text("URL: \(APIClient.configuredBaseURL)\n\n\(error)")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .background(RaveTheme.bg)
            .navigationTitle("Set times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(changeCount > 0 ? "Save (\(changeCount))" : "Save") { Task { await save() } }
                        .disabled(changeCount == 0 || saving)
                }
            }
            .task { await load() }
        }
    }

    private func list(_ schedule: Schedule) -> some View {
        List {
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .listRowBackground(RaveTheme.card)
            }
            if schedule.days.count > 1 {
                // "Day 1 · Fri Sep 18" needs 123pt a segment and a three-day segmented control gets 121.
                Picker("Day", selection: $day) {
                    ForEach(Array(schedule.days.enumerated()), id: \.element) { index, iso in
                        Text(nightLabel(iso, index: index, start: event.startDate)).tag(iso)
                    }
                }
                .pickerStyle(.menu)
                .listRowBackground(RaveTheme.card)
            }
            ForEach(schedule.slots.filter { $0.day == day }) { slot in
                Button { toggle(slot) } label: { row(slot) }
                    .buttonStyle(.plain)
                    .listRowBackground(RaveTheme.card)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ slot: ScheduleSlot) -> some View {
        let isSelected = selected.contains(slot.id)
        return HStack(spacing: 10) {
            Text(slot.startTime ?? "")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                if let stage = slot.stage {
                    Text(stage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? RaveTheme.accent : Color.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The server's `seen` flags are the baseline the diff is measured against.
    private var seen: Set<String> {
        Set((schedule?.slots ?? []).filter(\.seen).map(\.id))
    }

    private var added: Set<String> { selected.subtracting(seen) }
    private var removed: Set<String> { seen.subtracting(selected) }
    private var changeCount: Int { added.count + removed.count }

    private func toggle(_ slot: ScheduleSlot) {
        if selected.contains(slot.id) { selected.remove(slot.id) } else { selected.insert(slot.id) }
    }

    @MainActor
    private func load() async {
        error = nil
        do {
            let loaded = try await APIClient.shared.schedule(eventId: event.id)
            schedule = loaded
            selected = Set(loaded.slots.filter(\.seen).map(\.id))
            day = loaded.days.first ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        do {
            if !added.isEmpty {
                _ = try await APIClient.shared.markSlotsSeen(eventId: event.id, slotIds: Array(added))
            }
            // Unmarking is deleting the set the slot created, so a slot the server never logged has nothing to undo.
            for slotId in removed {
                guard let setId = schedule?.slots.first(where: { $0.id == slotId })?.setId else { continue }
                try await APIClient.shared.deleteSet(id: setId)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }
}

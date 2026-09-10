import SwiftUI

/// Plan is the private wishlist and never leaves the phone; Seen is the log the API keeps.
enum ScheduleMode: String, CaseIterable {
    case plan, seen

    var label: String { self == .plan ? "Plan" : "Seen" }
}

enum ScheduleFilter: Hashable {
    case all
    case planned
    case stage(String)
}

struct ScheduleView: View {
    let event: Event
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var record: ScheduleRecord?
    @State private var day = ""
    @State private var mode = ScheduleMode.seen
    @State private var showGrid = false
    @State private var filter = ScheduleFilter.all
    /// Colours come off the whole schedule, so narrowing the day or the stage never repaints anything.
    @State private var stageOrder: [String] = []
    @State private var loadError: String?
    @State private var syncError: String?
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            Group {
                if let record {
                    VStack(spacing: 0) {
                        chrome(record)
                        content(record)
                    }
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Backend not reachable", systemImage: "wifi.slash")
                    } description: {
                        Text("URL: \(APIClient.configuredBaseURL)\n\n\(loadError)")
                    } actions: {
                        Button("Retry") { Task { await refresh() } }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { Task { await save() } }
                        .disabled(record == nil)
                }
            }
            .task { await open() }
        }
    }

    private var saveLabel: String {
        let pending = record?.pendingCount ?? 0
        return pending > 0 ? "Save (\(pending))" : "Done"
    }

    // The mode picker decides what a tap does, so it gets the full-width row; day, filter and
    // layout share the line under it and the schedule keeps the rest of the screen.
    private func chrome(_ record: ScheduleRecord) -> some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                if record.schedule.days.count > 1 {
                    Picker("Day", selection: $day) {
                        ForEach(Array(record.schedule.days.enumerated()), id: \.element) { index, iso in
                            Text(nightLabel(iso, index: index, start: event.startDate)).tag(iso)
                        }
                    }
                    .pickerStyle(.menu)
                    // "Day 1 · Fri Sep 18" wraps to three lines if the row is allowed to squeeze it.
                    .fixedSize()
                }
                Spacer(minLength: 0)
                filterMenu
                Picker("Layout", selection: $showGrid) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "rectangle.split.3x1").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }

            if record.pendingCount > 0 || syncError != nil {
                HStack(spacing: 8) {
                    Text(pendingLine(record))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Retry") { Task { await refresh() } }
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pendingLine(_ record: ScheduleRecord) -> String {
        let count = record.pendingCount
        guard count > 0 else { return "Showing the last synced copy." }
        return "\(count) change\(count == 1 ? "" : "s") saved on this phone, not yet synced"
    }

    private var filterMenu: some View {
        Menu {
            Button("All stages") { filter = .all }
            Button("Planned only") { filter = .planned }
            Divider()
            ForEach(stageOrder, id: \.self) { stage in
                Button {
                    filter = .stage(stage)
                } label: {
                    Label {
                        Text(stage)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(StagePalette.color(stage, in: stageOrder))
                    }
                }
            }
        } label: {
            // Unfiltered needs no words: the whole day is on screen saying so, and the row has no
            // room to spare beside the day menu. A filled icon marks the state without relying on it.
            if filter == .all {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.subheadline)
            } else {
                Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }

    private var filterLabel: String {
        switch filter {
        case .all: return "All stages"
        case .planned: return "Planned only"
        case .stage(let stage): return stage
        }
    }

    @ViewBuilder
    private func content(_ record: ScheduleRecord) -> some View {
        let slots = visibleSlots(record)
        if slots.isEmpty {
            ContentUnavailableView("Nothing here", systemImage: "moon.zzz", description: Text(emptyReason(record)))
        } else if showGrid {
            if let layout = ScheduleDayLayout(schedule: record.schedule, day: day, stageOrder: stageOrder) {
                ScheduleGridView(
                    layout: layout,
                    stageOrder: stageOrder,
                    visible: Set(slots.map(\.id)),
                    planned: record.planned,
                    selected: record.selected,
                    onTap: toggle
                )
            } else {
                ContentUnavailableView(
                    "No times on this day",
                    systemImage: "clock.badge.questionmark",
                    description: Text("The schedule came back without a time axis, so the stage grid has nothing to place. The list still works.")
                )
            }
        } else {
            list(slots, record: record)
        }
    }

    private func emptyReason(_ record: ScheduleRecord) -> String {
        switch filter {
        case .planned: return "Nothing starred for this day yet. Switch to Plan and tap the sets you want."
        default: return "This day has no slots."
        }
    }

    private func list(_ slots: [ScheduleSlot], record: ScheduleRecord) -> some View {
        List(slots) { slot in
            Button { toggle(slot) } label: { row(slot, record: record) }
                .buttonStyle(.plain)
                .listRowBackground(RaveTheme.card)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ slot: ScheduleSlot, record: ScheduleRecord) -> some View {
        let isSeen = record.selected.contains(slot.id)
        let isPlanned = record.planned.contains(slot.id)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(StagePalette.color(slot.stageKey, in: stageOrder))
                .frame(width: 4)
            Text(slot.startTime ?? "")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                Text(slot.stageKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isPlanned {
                Image(systemName: "star.fill").foregroundStyle(.white)
            }
            Image(systemName: isSeen ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSeen ? .white : Color.secondary)
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.title), \(slot.stageKey)\(isPlanned ? ", planned" : "")\(isSeen ? ", seen" : "")")
    }

    private func visibleSlots(_ record: ScheduleRecord) -> [ScheduleSlot] {
        record.schedule.slots.filter { slot in
            guard slot.day == day else { return false }
            switch filter {
            case .all: return true
            case .planned: return record.planned.contains(slot.id)
            case .stage(let stage): return slot.stageKey == stage
            }
        }
    }

    private func toggle(_ slot: ScheduleSlot) {
        guard var updated = record else { return }
        switch mode {
        case .plan: updated.planned.formSymmetricDifference([slot.id])
        case .seen: updated.selected.formSymmetricDifference([slot.id])
        }
        updated.updatedAt = Date()
        record = updated
        Task { try? await ScheduleStore.shared.save(updated, for: event.id) }
    }

    @MainActor
    private func open() async {
        if let cached = await ScheduleStore.shared.record(for: event.id) {
            adopt(cached)
        }
        await refresh()
    }

    @MainActor
    private func refresh() async {
        syncing = true
        syncError = nil
        do {
            adopt(try await ScheduleStore.shared.sync(eventId: event.id))
            loadError = nil
        } catch {
            // With something cached this is a pending sync, not a failure to show the schedule.
            if record == nil { loadError = error.localizedDescription } else { syncError = error.localizedDescription }
        }
        syncing = false
    }

    @MainActor
    private func adopt(_ fresh: ScheduleRecord) {
        record = fresh
        stageOrder = StagePalette.order(fresh.schedule)
        if !fresh.schedule.days.contains(day) { day = fresh.schedule.days.first ?? "" }
    }

    @MainActor
    private func save() async {
        dismiss()
        // Every tap already persisted, so the sync is best-effort: failing leaves the changes pending.
        Task {
            _ = try? await ScheduleStore.shared.sync(eventId: event.id)
            await onSaved()
        }
    }
}

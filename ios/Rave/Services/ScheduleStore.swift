import Foundation

struct ScheduleRecord: Codable {
    var schedule: Schedule
    var planned: Set<String>
    var selected: Set<String>
    var syncedSeen: [String: String]
    var updatedAt: Date

    init(
        schedule: Schedule,
        planned: Set<String> = [],
        selected: Set<String> = [],
        syncedSeen: [String: String] = [:],
        updatedAt: Date = Date()
    ) {
        self.schedule = schedule
        self.planned = planned
        self.selected = selected
        self.syncedSeen = syncedSeen
        self.updatedAt = updatedAt
    }

    /// Pending work is always derived from the two stored sets rather than queued, so a crash between
    /// a tick and a sync loses nothing and a replayed sync is a no-op.
    var pendingAdditions: Set<String> { selected.subtracting(syncedSeen.keys) }
    var pendingRemovals: Set<String> { Set(syncedSeen.keys).subtracting(selected) }
    var pendingCount: Int { pendingAdditions.count + pendingRemovals.count }
}

/// The slice of the API the store pushes through, so the offline paths can be exercised without one.
protocol ScheduleSyncing: Sendable {
    func schedule(eventId: String) async throws -> Schedule
    func markSlotsSeen(eventId: String, slotIds: [String]) async throws -> BulkSetsResponse
    func deleteSet(id: String) async throws
}

extension APIClient: ScheduleSyncing {}

actor ScheduleStore {
    static let shared = ScheduleStore()

    private let api: ScheduleSyncing
    private let directory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(api: ScheduleSyncing = APIClient.shared, directory: URL? = nil) {
        self.api = api
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Schedules", isDirectory: true)
    }

    func record(for eventId: String) -> ScheduleRecord? {
        guard let data = try? Data(contentsOf: url(for: eventId)) else { return nil }
        return try? decoder.decode(ScheduleRecord.self, from: data)
    }

    func save(_ record: ScheduleRecord, for eventId: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(record).write(to: url(for: eventId), options: .atomic)
    }

    func sync(eventId: String) async throws -> ScheduleRecord {
        let local = record(for: eventId)

        if let additions = local?.pendingAdditions, !additions.isEmpty {
            _ = try await api.markSlotsSeen(eventId: eventId, slotIds: additions.sorted())
        }
        for slotId in local?.pendingRemovals.sorted() ?? [] {
            guard let setId = local?.syncedSeen[slotId] else { continue }
            do {
                try await api.deleteSet(id: setId)
            } catch APIError.http(404) {
                continue
            }
        }

        let fresh = try await api.schedule(eventId: eventId)
        let serverSeen = fresh.slots.reduce(into: [String: String]()) { seen, slot in
            if let setId = slot.setId, slot.seen { seen[slot.id] = setId }
        }
        let updated = ScheduleRecord(
            schedule: fresh,
            planned: local?.planned ?? [],
            selected: local?.selected ?? Set(serverSeen.keys),
            syncedSeen: serverSeen
        )
        try save(updated, for: eventId)
        return updated
    }

    private func url(for eventId: String) -> URL {
        let name = eventId.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return directory.appendingPathComponent("\(String(name)).json")
    }
}

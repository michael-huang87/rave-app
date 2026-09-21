import Foundation

/// A write the user made that the server has not taken yet.
///
/// Every case is safe to replay, which is what lets the flush retry after an ambiguous
/// timeout without tracking whether the request reached the server: the two PATCH handlers
/// and the spend handler assign rather than accumulate, bulk-add skips titles already on the
/// night, create derives the event id from its own content, and a delete that already landed
/// answers 404. `POST /events/{id}/sets` is the one write that would duplicate on replay, and
/// the app never calls it.
enum PendingWrite: Codable, Equatable {
    case createEvent(localId: String, draft: EventDraft)
    case updateEvent(id: String, patch: EventPatch)
    case logSpend(eventId: String, spend: SpendDraft)
    case bulkAddSets(eventId: String, localIdPrefix: String, draft: BulkSetsDraft)
    case updateSet(id: String, patch: SetPatch)
    case deleteSet(id: String)
}

struct QueuedWrite: Codable, Equatable, Identifiable {
    var id: String
    var write: PendingWrite
    var queuedAt: Date

    init(write: PendingWrite, id: String = UUID().uuidString, queuedAt: Date = Date()) {
        self.id = id
        self.write = write
        self.queuedAt = queuedAt
    }
}

/// The slice of the API the outbox pushes through, so the offline paths can be exercised without one.
protocol OutboxSyncing: Sendable {
    /// Answers the id the server gave a newly created event, so writes queued against that
    /// event's local id can be readdressed before they go up. Nil for every other write.
    @discardableResult
    func perform(_ write: PendingWrite) async throws -> String?
}

// MARK: - Overlay

/// Reads come from `LastReadStore`, which only ever holds what the server last said. Laying the
/// queue over that payload is what makes an offline edit visible on the screen that made it,
/// instead of appearing to vanish on the refetch that follows a save.
struct OutboxSnapshot: Equatable {
    var writes: [PendingWrite]

    init(_ writes: [PendingWrite] = []) {
        self.writes = writes
    }

    var isEmpty: Bool { writes.isEmpty }

    func apply(to events: [Event]) -> [Event] {
        writes.reduce(into: events) { events, write in
            switch write {
            case .createEvent(let localId, let draft):
                guard !events.contains(where: { $0.id == localId }) else { return }
                events.append(Event(localId: localId, draft: draft))
            case .updateEvent(let id, let patch):
                mutate(&events, id: id) { $0.apply(patch) }
            case .logSpend(let eventId, let spend):
                mutate(&events, id: eventId) { $0.apply(spend) }
            case .bulkAddSets(let eventId, let prefix, let draft):
                mutate(&events, id: eventId) { $0.applyBulkAdd(prefix: prefix, draft: draft) }
            case .updateSet, .deleteSet:
                for i in events.indices where events[i].sets != nil {
                    events[i].sets = OutboxSnapshot([write]).apply(to: events[i].sets ?? [])
                    events[i].refreshSetCount()
                }
            }
        }
    }

    func apply(to event: Event) -> Event {
        apply(to: [event]).first { $0.id == event.id } ?? event
    }

    func apply(to sets: [SetEntry]) -> [SetEntry] {
        writes.reduce(into: sets) { sets, write in
            switch write {
            case .bulkAddSets(let eventId, let prefix, let draft):
                sets.append(contentsOf: newSets(eventId: eventId, prefix: prefix, draft: draft, existing: sets))
            case .updateSet(let id, let patch):
                guard let i = sets.firstIndex(where: { $0.id == id }) else { return }
                sets[i].apply(patch)
            case .deleteSet(let id):
                sets.removeAll { $0.id == id }
            case .createEvent, .updateEvent, .logSpend:
                return
            }
        }
    }

    private func mutate(_ events: inout [Event], id: String, _ change: (inout Event) -> Void) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        change(&events[i])
    }
}

/// Mirrors the backend's bulk-add, which treats one typed line as one set and skips a title
/// already on that night rather than duplicating it.
private func newSets(eventId: String, prefix: String, draft: BulkSetsDraft, existing: [SetEntry]) -> [SetEntry] {
    var seen = Set(existing.filter { $0.eventId == eventId && $0.date == draft.date }.map { normalizedTitle($0.title) })
    var made: [SetEntry] = []
    for (offset, line) in draft.artists.enumerated() {
        let title = line.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, seen.insert(normalizedTitle(title)).inserted else { continue }
        made.append(
            SetEntry(
                id: "\(prefix)-\(offset)",
                eventId: eventId,
                title: title,
                show: nil,
                venue: nil,
                city: nil,
                year: draft.date.flatMap { Int($0.prefix(4)) },
                date: draft.date,
                artists: splitArtists(title)
            )
        )
    }
    return made
}

func normalizedTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespaces).lowercased()
}

func splitArtists(_ title: String) -> [String] {
    var parts = [title]
    for separator in [" b2b ", " B2B ", " x ", " & ", " vs ", " VS "] {
        parts = parts.flatMap { $0.components(separatedBy: separator) }
    }
    let names = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return names.isEmpty ? [title] : names
}

private func money(_ value: Double) -> Double { (value * 100).rounded() / 100 }

private func today() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

extension Event {
    /// A show created with no signal. The id is local until the flush replaces this row with the
    /// server's, whose id is derived from show, start date, and venue.
    init(localId: String, draft: EventDraft) {
        let total = money(draft.ticket + draft.travel + draft.drinksFoodMerch)
        let ends = draft.endDate ?? draft.startDate
        self.init(
            id: localId,
            show: draft.show,
            venue: draft.venue,
            city: draft.city,
            year: draft.startDate.flatMap { Int($0.prefix(4)) },
            startDate: draft.startDate,
            endDate: ends,
            dateDisplay: draft.startDate,
            ticket: money(draft.ticket),
            travel: money(draft.travel),
            drinksFoodMerch: money(draft.drinksFoodMerch),
            total: total,
            setsLogged: 0,
            setsSheet: nil,
            dollarsPerSet: nil,
            status: (ends.map { $0 < today() } ?? false) ? .attended : .planned,
            days: nil,
            source: "user",
            sourceTab: nil,
            sets: []
        )
    }

    mutating func apply(_ patch: EventPatch) {
        show = patch.show
        venue = patch.venue
        city = patch.city
        startDate = patch.startDate
        endDate = patch.endDate
    }

    mutating func apply(_ spend: SpendDraft) {
        ticket = money(spend.ticket)
        travel = money(spend.travel)
        drinksFoodMerch = money(spend.drinksFoodMerch)
        refreshTotals()
    }

    mutating func applyBulkAdd(prefix: String, draft: BulkSetsDraft) {
        let added = newSets(eventId: id, prefix: prefix, draft: draft, existing: sets ?? [])
        if sets != nil { sets?.append(contentsOf: added) }
        setsLogged += added.count
        refreshTotals()
    }

    mutating func refreshSetCount() {
        guard let sets else { return }
        setsLogged = sets.count
        refreshTotals()
    }

    mutating func refreshTotals() {
        total = money(ticket + travel + drinksFoodMerch)
        dollarsPerSet = setsLogged > 0 ? money(total / Double(setsLogged)) : nil
    }
}

extension SetEntry {
    mutating func apply(_ patch: SetPatch) {
        if let title = patch.title { self.title = title }
        if let artists = patch.artists { self.artists = artists }
        if let date = patch.date { self.date = date }
    }
}

// MARK: - Store

/// On-disk queue of writes the server has not taken. Survives a force quit, because the whole
/// point is a weekend in a field with no signal.
actor Outbox {
    static let shared = Outbox()

    static let changed = Notification.Name("rave.outboxChanged")

    private let fileURL: URL
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var queue: [QueuedWrite]
    private var flushing = false

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("Outbox.json")
        let onDisk = JSONDecoder()
        onDisk.dateDecodingStrategy = .iso8601
        queue = (try? Data(contentsOf: fileURL)).flatMap { try? onDisk.decode([QueuedWrite].self, from: $0) } ?? []
    }

    var pending: [QueuedWrite] { queue }
    var count: Int { queue.count }
    var snapshot: OutboxSnapshot { OutboxSnapshot(queue.map(\.write)) }

    func enqueue(_ write: PendingWrite) async {
        queue.append(QueuedWrite(write: write))
        await persist()
    }

    /// Sends in the order the user made the writes and stops at the first one that cannot go,
    /// so a later write never lands before the earlier one it was typed on top of. A write the
    /// server rejects outright is dropped: retrying it forever would wedge everything behind it.
    @discardableResult
    func flush(using api: OutboxSyncing) async -> Int {
        guard !flushing else { return 0 }
        flushing = true
        defer { flushing = false }

        var sent = 0
        var realIds: [String: String] = [:]
        while let next = queue.first {
            let write = readdressed(next.write, realIds)
            do {
                if case .createEvent(let localId, _) = write, let serverId = try await api.perform(write) {
                    realIds[localId] = serverId
                } else {
                    try await api.perform(write)
                }
            } catch {
                guard (error as? APIError)?.isPermanent == true else { break }
            }
            queue.removeFirst()
            sent += 1
            await persist()
        }
        return sent
    }

    /// A show created with no signal is queued under a local id, and anything logged against it
    /// before that create goes up carries the same id. Swapping in the server's id as soon as the
    /// create lands is what stops those sets 404ing and being thrown away.
    private func readdressed(_ write: PendingWrite, _ realIds: [String: String]) -> PendingWrite {
        switch write {
        case .updateEvent(let id, let patch):
            guard let real = realIds[id] else { return write }
            return .updateEvent(id: real, patch: patch)
        case .logSpend(let eventId, let spend):
            guard let real = realIds[eventId] else { return write }
            return .logSpend(eventId: real, spend: spend)
        case .bulkAddSets(let eventId, let prefix, let draft):
            guard let real = realIds[eventId] else { return write }
            return .bulkAddSets(eventId: real, localIdPrefix: prefix, draft: draft)
        case .createEvent, .updateSet, .deleteSet:
            return write
        }
    }

    private func persist() async {
        if let data = try? encoder.encode(queue) {
            try? data.write(to: fileURL, options: .atomic)
        }
        let waiting = queue.count
        await ReadRevision.shared.bump()
        Task { @MainActor in
            NotificationCenter.default.post(name: Outbox.changed, object: nil, userInfo: ["count": waiting])
            NotificationCenter.default.post(name: LocalLog.changed, object: nil)
        }
    }
}

extension APIError {
    /// A rejection the same request will keep earning. Anything else is worth another go.
    var isPermanent: Bool {
        if case .http(let code) = self { return (400..<500).contains(code) && code != 408 && code != 429 }
        if case .decode = self { return true }
        return false
    }
}

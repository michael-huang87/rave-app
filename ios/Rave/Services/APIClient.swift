import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case decode
    case transport(String)
    case needsSignal

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad API URL"
        case .http(let code): return "Server returned \(code)"
        case .decode: return "Could not read the server response"
        case .transport(let message): return message
        case .needsSignal:
            return "No signal. The change is saved on this phone and goes up when the API is reachable."
        }
    }
}

actor APIClient: OutboxSyncing {
    static let shared = APIClient()

    static var configuredBaseURL: String {
        resolveBaseURL().absoluteString
    }

    /// Simulator uses localhost; a physical device uses `APIBaseURL` from Info.plist.
    var baseURL: URL

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Fail fast so we can show last-read cache instead of hanging offline.
        // Linux exposes this as read-only, and its default is already false.
        #if !os(Linux)
        config.waitsForConnectivity = false
        #endif
        config.timeoutIntervalForRequest = 15
        config.allowsCellularAccess = true
        #if !os(Linux)
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        #endif
        return URLSession(configuration: config)
    }()

    private let store: LastReadStore

    private init(store: LastReadStore = .shared) {
        baseURL = Self.resolveBaseURL()
        self.store = store
    }

    private static func resolveBaseURL() -> URL {
        // Set by the launch environment so the offline paths can be driven against a dead port
        // without stopping the real backend.
        if let raw = ProcessInfo.processInfo.environment["RAVE_API_BASE_URL"], let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              let url = URL(string: raw) else {
            return URL(string: "http://127.0.0.1:8000")!
        }
        return url
        #endif
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func events(status: EventStatus? = nil, year: Int? = nil) async throws -> ReadResult<[Event]> {
        var items: [URLQueryItem] = []
        if let status { items.append(.init(name: "status", value: status.rawValue)) }
        if let year { items.append(.init(name: "year", value: String(year))) }
        return try await cachedGet("/events", query: items, key: .events)
    }

    func event(id: String) async throws -> ReadResult<Event> {
        try await cachedGet("/events/\(id)", key: .event(id))
    }

    func sets() async throws -> ReadResult<[SetEntry]> {
        try await cachedGet("/sets", key: .sets)
    }

    func recap() async throws -> ReadResult<Recap> {
        try await cachedGet("/recap", key: .recap)
    }

    func stats() async throws -> ReadResult<Stats> {
        try await cachedGet("/stats", key: .stats)
    }

    /// The one door every write goes through. With a signal it sends; without one it puts the
    /// write in the outbox, where the next reachable moment picks it up. Writes already waiting
    /// hold the door: a new write queues behind them so the server never sees a later edit
    /// before the earlier one it was typed on top of.
    func submit(_ write: PendingWrite) async throws {
        if await Outbox.shared.count > 0 {
            await Outbox.shared.enqueue(write)
            await flushOutbox()
            return
        }
        do {
            try await perform(write)
        } catch APIError.needsSignal {
            await Outbox.shared.enqueue(write)
        }
    }

    @discardableResult
    func perform(_ write: PendingWrite) async throws -> String? {
        switch write {
        case .createEvent(_, let draft):
            let event: Event = try await send("/events", method: "POST", body: draft)
            absorb(event: event)
            return event.id
        case .updateEvent(let id, let patch):
            let event: Event = try await send("/events/\(id)", method: "PATCH", body: patch)
            absorb(event: event)
        case .logSpend(let eventId, let spend):
            let event: Event = try await send("/events/\(eventId)/spend", method: "PATCH", body: spend)
            absorb(event: event)
        case .bulkAddSets(let eventId, _, let draft):
            let response: BulkSetsResponse = try await send("/events/\(eventId)/sets/bulk", method: "POST", body: draft)
            absorb(sets: response.created)
        case .updateSet(let id, let patch):
            let updated: SetEntry = try await send("/sets/\(id)", method: "PATCH", body: patch)
            absorb(sets: [updated])
        case .deleteSet(let id):
            try await deleteSet(id: id)
            forgetSet(id)
        }
        return nil
    }

    /// ScheduleStore drives its own sync off derived state rather than the outbox, so it needs
    /// the raw call.
    func deleteSet(id: String) async throws {
        try await sendNoContent("/sets/\(id)", method: "DELETE")
    }

    @discardableResult
    func flushOutbox() async -> Int {
        await Outbox.shared.flush(using: self)
    }

    /// Pushes the outbox, then every festival seen-set that is still ahead of the server, then
    /// pulls the snapshots those screens derive from. A failed push leaves its queue in place.
    func drainPendingWrites() async {
        let sent = await flushOutbox()
        var synced = 0
        for id in await ScheduleStore.shared.eventIdsWithPending() {
            if (try? await ScheduleStore.shared.sync(eventId: id)) != nil { synced += 1 }
        }
        guard sent > 0 || synced > 0 else { return }
        await refreshServerSnapshots()
        Task { @MainActor in
            NotificationCenter.default.post(name: LocalLog.changed, object: nil)
        }
    }

    /// The sets list with unsent writes and unticked-or-ticked slots laid on, or nil if this
    /// phone has never loaded sets.
    func localSets() async -> ReadResult<[SetEntry]>? {
        guard let hit = store.load([SetEntry].self, key: .sets) else { return nil }
        let events = store.load([Event].self, key: .events)?.payload ?? []
        let log = await assembled(events: events, sets: hit.payload, setsAreComplete: true)
        return ReadResult(value: log.sets, fromCache: true, cachedAt: hit.savedAt)
    }

    func localEvents() async -> ReadResult<[Event]>? {
        guard let hit = store.load([Event].self, key: .events) else { return nil }
        let setsHit = store.load([SetEntry].self, key: .sets)
        let log = await assembled(events: hit.payload, sets: setsHit?.payload ?? [], setsAreComplete: setsHit != nil)
        return ReadResult(value: log.events, fromCache: true, cachedAt: hit.savedAt)
    }

    func localEvent(id: String) async -> ReadResult<Event>? {
        guard let hit = store.load(Event.self, key: .event(id)) else { return nil }
        let pending = await Outbox.shared.snapshot
        let schedules = await ScheduleStore.shared.allRecords()
        let sibling = store.load([SetEntry].self, key: .sets)?.payload
        let event = LocalLog.detail(hit.payload, siblingSets: sibling, pending: pending, schedules: schedules)
        return ReadResult(value: event, fromCache: true, cachedAt: hit.savedAt)
    }

    func localStats() async -> ReadResult<Stats>? {
        let saved = store.load(Stats.self, key: .stats)
        if let setsHit = store.load([SetEntry].self, key: .sets) {
            let events = store.load([Event].self, key: .events)?.payload ?? []
            let pending = await Outbox.shared.snapshot
            let log = await assembled(events: events, sets: setsHit.payload, setsAreComplete: true)
            if saved == nil || !pending.isEmpty || log.sets != setsHit.payload {
                return ReadResult(value: log.stats(), fromCache: true, cachedAt: saved?.savedAt)
            }
        }
        if let saved { return ReadResult(value: saved.payload, fromCache: true, cachedAt: saved.savedAt) }
        return nil
    }

    func localRecap() async -> ReadResult<Recap>? {
        let saved = store.load(Recap.self, key: .recap)
        if let setsHit = store.load([SetEntry].self, key: .sets),
           let eventsHit = store.load([Event].self, key: .events) {
            let pending = await Outbox.shared.snapshot
            let log = await assembled(events: eventsHit.payload, sets: setsHit.payload, setsAreComplete: true)
            if saved == nil || !pending.isEmpty || log.sets != setsHit.payload {
                return ReadResult(value: log.recap(asOf: saved?.payload.asOf), fromCache: true, cachedAt: saved?.savedAt)
            }
        }
        if let saved { return ReadResult(value: saved.payload, fromCache: true, cachedAt: saved.savedAt) }
        return nil
    }

    func schedule(eventId: String) async throws -> Schedule {
        try await get("/events/\(eventId)/schedule")
    }

    func markSlotsSeen(eventId: String, slotIds: [String]) async throws -> BulkSetsResponse {
        try await send("/events/\(eventId)/schedule/seen", method: "POST", body: MarkSeenDraft(slotIds: slotIds))
    }

    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.badURL }
        comps.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        return url
    }

    /// Network refresh for a last-read key. Screens paint the local projection first so this
    /// wait never gates the UI when a cache already exists. On failure, serve that projection.
    /// A GET that started before a local write is not saved: it would put the pre-write snapshot
    /// back under a queue that has already moved on.
    private func cachedGet<T: Codable>(_ path: String, query: [URLQueryItem] = [], key: LastReadKey) async throws -> ReadResult<T> {
        let token = await ReadRevision.shared.current
        do {
            let live: T = try await get(path, query: query)
            let current = await ReadRevision.shared.current
            if current == token { store.save(live, key: key) }
            if let projected = await projected(key) as? T {
                let stamped = store.load(T.self, key: key)?.savedAt
                return ReadResult(value: projected, fromCache: current != token, cachedAt: current != token ? stamped : nil)
            }
            return ReadResult(value: live, fromCache: false, cachedAt: nil)
        } catch {
            if let projected = await projected(key) as? T {
                return ReadResult(value: projected, fromCache: true, cachedAt: store.load(T.self, key: key)?.savedAt)
            }
            throw error
        }
    }

    private func projected(_ key: LastReadKey) async -> Any? {
        switch key {
        case .sets: return await localSets()?.value
        case .events: return await localEvents()?.value
        case .event(let id): return await localEvent(id: id)?.value
        case .stats: return await localStats()?.value
        case .recap: return await localRecap()?.value
        }
    }

    private func assembled(events: [Event], sets: [SetEntry], setsAreComplete: Bool) async -> LocalLog {
        let pending = await Outbox.shared.snapshot
        let schedules = await ScheduleStore.shared.allRecords()
        return LocalLog.make(
            events: events,
            sets: sets,
            pending: pending,
            schedules: schedules,
            setsAreComplete: setsAreComplete
        )
    }

    /// Pulls the four snapshots after a push. Bumps first so a GET already in flight cannot
    /// write the older body over this one.
    func refreshServerSnapshots() async {
        await ReadRevision.shared.bump()
        let token = await ReadRevision.shared.current
        await storeGet([Event].self, "/events", .events, token)
        await storeGet([SetEntry].self, "/sets", .sets, token)
        await storeGet(Recap.self, "/recap", .recap, token)
        await storeGet(Stats.self, "/stats", .stats, token)
    }

    private func storeGet<T: Codable>(_ type: T.Type, _ path: String, _ key: LastReadKey, _ token: Int) async {
        guard let live: T = try? await get(path) else { return }
        guard await ReadRevision.shared.current == token else { return }
        store.save(live, key: key)
    }

    /// The write response is what the server just said. Folding it into last-read is what keeps
    /// the row on screen after its queue entry is removed, before the next full GET.
    private func absorb(event: Event) {
        var stored = event
        if stored.sets == nil, let previous = store.load(Event.self, key: .event(event.id))?.payload {
            stored.sets = previous.sets
        }
        store.save(stored, key: .event(event.id))
        guard var events = store.load([Event].self, key: .events)?.payload else { return }
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            let nested = events[i].sets
            events[i] = stored
            if events[i].sets == nil { events[i].sets = nested }
        } else {
            events.insert(stored, at: 0)
        }
        store.save(events, key: .events)
    }

    private func absorb(sets incoming: [SetEntry]) {
        guard !incoming.isEmpty else { return }
        if let existing = store.load([SetEntry].self, key: .sets)?.payload {
            store.save(LocalLog.absorb(incoming, into: existing), key: .sets)
        }
        for (eventId, rows) in Dictionary(grouping: incoming, by: \.eventId) {
            guard var event = store.load(Event.self, key: .event(eventId))?.payload, event.sets != nil else { continue }
            event.sets = LocalLog.absorb(rows, into: event.sets ?? [])
            event.setsLogged = event.sets?.count ?? event.setsLogged
            event.refreshTotals()
            store.save(event, key: .event(eventId))
        }
    }

    private func forgetSet(_ id: String) {
        let eventId = store.load([SetEntry].self, key: .sets)?.payload.first { $0.id == id }?.eventId
        if var sets = store.load([SetEntry].self, key: .sets)?.payload {
            sets.removeAll { $0.id == id }
            store.save(sets, key: .sets)
        }
        guard let eventId, var event = store.load(Event.self, key: .event(eventId))?.payload else { return }
        event.sets?.removeAll { $0.id == id }
        if event.sets != nil {
            event.setsLogged = event.sets?.count ?? event.setsLogged
            event.refreshTotals()
            store.save(event, key: .event(eventId))
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let url = try makeURL(path, query: query)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(Self.describe(error))
        }
        try Self.check(response)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }

    private func send<Body: Encodable, T: Decodable>(_ path: String, method: String, body: Body) async throws -> T {
        let url = try makeURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if Self.isOffline(error) { throw APIError.needsSignal }
            throw APIError.transport(Self.describe(error))
        }
        try Self.check(response)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }

    private func sendNoContent(_ path: String, method: String) async throws {
        let url = try makeURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: req)
        } catch {
            if Self.isOffline(error) { throw APIError.needsSignal }
            throw APIError.transport(Self.describe(error))
        }
        try Self.check(response)
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection. If using Tailscale, confirm it is connected."
            case .timedOut:
                return "Timed out reaching the API. Confirm your Mac is awake and the backend is running."
            case .cannotConnectToHost, .networkConnectionLost:
                return "Could not connect to the API host. Check Tailscale on both devices and Settings → Rave → enable Cellular Data and Local Network."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
    }
}

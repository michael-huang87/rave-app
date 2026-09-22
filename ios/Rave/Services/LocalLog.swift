import Foundation

extension Notification.Name {
    /// Posted after a local write or a successful sync so every screen re-reads the projection.
    static let raveLocalLogChanged = Notification.Name("rave.localLogChanged")
}

/// Bumped on every local mutation and every accepted sync. A GET that started before the bump
/// must not overwrite the snapshot the mutation is projected onto.
actor ReadRevision {
    static let shared = ReadRevision()
    private var value = 0
    func bump() { value += 1 }
    var current: Int { value }
}

/// What Sets, Stats, Recap, and the show list show while a write has not reached the server.
///
/// Last-read stays a snapshot of what the server last said. This lays two queues on top of it:
/// the outbox (creates, edits, spend, typed sets) and the festival schedule's seen set
/// (`selected` minus `syncedSeen`). Screens read the result immediately. Nothing here is a
/// second copy that can drift on its own; it is recomputed whenever either queue changes.
///
/// Sync, single-user: the outbox flushes in typed order and stops on a dropped connection.
/// A 4xx other than 408/429 is dropped so one rejected write cannot wedge the rest. Schedule
/// ticks are an intent set, not a log: push additions, then removals, then pull. The server
/// skips a slot it already logged and a delete of a missing set is a no-op, so retrying is safe.
/// After a pull, server-acked slot ids replace `syncedSeen`. Slots this phone changed keep the
/// local selection; slots it did not change follow the server. That is last-write-wins for one
/// person, not a multi-device merge.
struct LocalLog {
    static let changed = Notification.Name.raveLocalLogChanged

    var events: [Event]
    var sets: [SetEntry]

    static func make(
        events: [Event],
        sets: [SetEntry],
        pending: OutboxSnapshot,
        schedules: [ScheduleRecord],
        setsAreComplete: Bool
    ) -> LocalLog {
        var events = pending.apply(to: events)
        let projected = applySchedules(
            pending.apply(to: sets),
            events: events,
            schedules: schedules,
            pending: pending
        )
        // Leave the server's set counts alone when nothing local changed the set list. A stale
        // sets snapshot must not overwrite a newer event total that the server already computed.
        if setsAreComplete && projected != sets {
            var before: [String: Int] = [:]
            var after: [String: Int] = [:]
            for set in sets { before[set.eventId, default: 0] += 1 }
            for set in projected { after[set.eventId, default: 0] += 1 }
            for id in Set(before.keys).union(after.keys) where before[id, default: 0] != after[id, default: 0] {
                guard let i = events.firstIndex(where: { $0.id == id }) else { continue }
                events[i].setsLogged = after[id, default: 0]
                events[i].refreshTotals()
            }
        } else if !setsAreComplete {
            for record in schedules {
                guard let i = events.firstIndex(where: { $0.id == record.schedule.eventId }) else { continue }
                let delta = record.pendingAdditions.count - record.pendingRemovals.count
                events[i].setsLogged = max(0, events[i].setsLogged + delta)
                events[i].refreshTotals()
            }
        }
        return LocalLog(events: events, sets: projected)
    }

    /// A show's own set list. When the sets snapshot exists it wins, so the detail screen and
    /// the Sets tab cannot disagree about what an offline tick did.
    static func detail(
        _ event: Event,
        siblingSets: [SetEntry]?,
        pending: OutboxSnapshot,
        schedules: [ScheduleRecord]
    ) -> Event {
        var event = pending.apply(to: event)
        let mine = schedules.filter { $0.schedule.eventId == event.id }
        // The sets snapshot and this show's own payload can be a GET apart. Keep any row either
        // one has, then lay ticks on top, so a fresh detail cannot hide a set the list already
        // shows and a fresh list cannot hide a set this payload just returned.
        var base: [SetEntry] = []
        if let siblingSets {
            base = pending.apply(to: siblingSets.filter { $0.eventId == event.id })
        }
        if let nested = event.sets {
            let have = Set(base.map(\.id))
            for set in nested where !have.contains(set.id) { base.append(set) }
        }
        if siblingSets == nil && event.sets == nil {
            let delta = mine.reduce(0) { $0 + $1.pendingAdditions.count - $1.pendingRemovals.count }
            event.setsLogged = max(0, event.setsLogged + delta)
            event.refreshTotals()
            return event
        }
        let rows = applySchedules(base, events: [event], schedules: mine, pending: pending)
        event.sets = rows
        event.setsLogged = rows.count
        event.refreshTotals()
        return event
    }

    /// Inserts server rows that just landed so the projection still shows them once the queue
    /// entry that created them is gone.
    static func absorb(_ incoming: [SetEntry], into sets: [SetEntry]) -> [SetEntry] {
        var sets = sets
        for set in incoming {
            if let i = sets.firstIndex(where: { $0.id == set.id }) {
                sets[i] = set
            } else {
                insertByDate(set, into: &sets)
            }
        }
        return sets
    }

    func stats() -> Stats {
        var artists: [(String, String)] = []
        var venues: [(String, String)] = []
        var cities: [(String, String)] = []
        for set in sets {
            for artist in set.artists where !collapsed(artist).isEmpty {
                artists.append((artist, set.id))
            }
            if let venue = set.venue, !collapsed(venue).isEmpty {
                venues.append((venue, set.date ?? ""))
            }
            if let city = set.city, !collapsed(city).isEmpty {
                cities.append((city, set.date ?? ""))
            }
        }
        return Stats(artists: rank(artists), venues: rank(venues), cities: rank(cities))
    }

    func recap(asOf: String?) -> Recap {
        let years = Set(events.compactMap(\.year))
        var byYear: [String: RecapBucket] = [:]
        for year in years {
            byYear[String(year)] = bucket(
                events: events.filter { $0.year == year },
                sets: sets.filter { $0.year == year }
            )
        }
        return Recap(asOf: asOf, allTime: bucket(events: events, sets: sets), byYear: byYear)
    }

    private func bucket(events: [Event], sets: [SetEntry]) -> RecapBucket {
        let artistNames = sets.flatMap(\.artists).map(collapsed).filter { !$0.isEmpty }
        let artistPairs = sets.flatMap { set in
            set.artists.filter { !collapsed($0).isEmpty }.map { ($0, set.id) }
        }
        let cityPairs = sets.compactMap { set -> (String, String)? in
            guard let city = set.city, !collapsed(city).isEmpty else { return nil }
            return (city, set.date ?? "")
        }
        let rankedArtists = rank(artistPairs)
        let rankedCities = rank(cityPairs)
        let ticket = money(events.reduce(0) { $0 + $1.ticket })
        let travel = money(events.reduce(0) { $0 + $1.travel })
        let drinks = money(events.reduce(0) { $0 + $1.drinksFoodMerch })
        return RecapBucket(
            sets: sets.count,
            artists: Set(artistNames).count,
            setTitles: Set(sets.map(\.title).filter { !$0.isEmpty }).count,
            shows: Set(sets.compactMap(\.show).filter { !$0.isEmpty }).count,
            events: events.count,
            venues: Set(events.compactMap(\.venue).filter { !$0.isEmpty }).count,
            cities: Set(events.compactMap(\.city).filter { !$0.isEmpty }).count,
            spend: money(events.reduce(0) { $0 + $1.total }),
            spendByType: .init(ticket: ticket, travel: travel, drinksFoodMerch: drinks),
            topArtist: rankedArtists.first.map { .init(name: $0.name, count: $0.count) },
            topCity: rankedCities.first.map { .init(name: $0.name, count: $0.count) },
            mostSets: mostSets(events),
            bestDollarsPerSet: bestPaid(events)
        )
    }
}

// MARK: - Schedule ticks

/// A ticked slot becomes a set row until the sets snapshot contains the id the server assigned.
/// An untick drops that id. A set the outbox is already deleting is not put back.
private func applySchedules(
    _ sets: [SetEntry],
    events: [Event],
    schedules: [ScheduleRecord],
    pending: OutboxSnapshot
) -> [SetEntry] {
    var sets = sets
    let deleted = Set(pending.writes.compactMap { write -> String? in
        if case .deleteSet(let id) = write { return id }
        return nil
    })
    let eventsById = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    for record in schedules {
        let eventId = record.schedule.eventId
        let removeIds = Set(record.pendingRemovals.compactMap { record.syncedSeen[$0] })
        if !removeIds.isEmpty {
            sets.removeAll { removeIds.contains($0.id) }
        }

        var claimed = Set<String>()
        var missing: [ScheduleSlot] = []
        let selected = record.schedule.slots
            .filter { record.selected.contains($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }
        for slot in selected {
            if let sid = record.syncedSeen[slot.id] {
                if deleted.contains(sid) { continue }
                if sets.contains(where: { $0.id == sid }) {
                    claimed.insert(sid)
                    continue
                }
            }
            let title = collapsed(slot.title)
            if let match = sets.first(where: {
                $0.eventId == eventId
                    && $0.date == slot.day
                    && collapsed($0.title) == title
                    && !claimed.contains($0.id)
                    && !removeIds.contains($0.id)
            }) {
                claimed.insert(match.id)
                continue
            }
            missing.append(slot)
        }

        let event = eventsById[eventId]
        for slot in missing {
            let localId = "pending-seen:\(eventId):\(slot.id)"
            guard !sets.contains(where: { $0.id == localId }) else { continue }
            insertByDate(setFrom(slot, eventId: eventId, event: event, id: localId), into: &sets)
        }
    }
    return sets
}

private func setFrom(_ slot: ScheduleSlot, eventId: String, event: Event?, id: String) -> SetEntry {
    SetEntry(
        id: id,
        eventId: eventId,
        title: slot.title,
        show: event?.show,
        venue: event?.venue,
        city: event?.city,
        year: event?.year ?? Int(slot.day.prefix(4)),
        date: slot.day,
        artists: slot.artists.isEmpty ? splitArtists(slot.title) : slot.artists
    )
}

/// The sets list is date-descending, and within a day the order the sets were logged. A tick
/// joins the end of its day so the day stays one section.
private func insertByDate(_ entry: SetEntry, into sets: inout [SetEntry]) {
    let key = entry.date ?? ""
    guard !key.isEmpty else {
        sets.append(entry)
        return
    }
    if let last = sets.lastIndex(where: { $0.date == key }) {
        sets.insert(entry, at: last + 1)
        return
    }
    if let older = sets.firstIndex(where: { ($0.date ?? "").isEmpty == false && ($0.date ?? "") < key }) {
        sets.insert(entry, at: older)
        return
    }
    sets.append(entry)
}

// MARK: - Rankings (same rules as GET /stats and GET /recap)

private func collapsed(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}

private func rank(_ pairs: [(String, String)]) -> [StatCount] {
    var seen: [String: Set<String>] = [:]
    var display: [String: String] = [:]
    for (name, item) in pairs {
        let key = collapsed(name)
        guard !key.isEmpty else { continue }
        seen[key, default: []].insert(item)
        if display[key] == nil {
            display[key] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return seen.map { StatCount(name: display[$0.key] ?? $0.key, count: $0.value.count) }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.lowercased() < $1.name.lowercased()
        }
}

private func mostSets(_ events: [Event]) -> RecapBucket.NamedCount? {
    guard let winner = events.min(by: { lhs, rhs in
        if lhs.setsLogged != rhs.setsLogged { return lhs.setsLogged > rhs.setsLogged }
        return lhs.show.lowercased() < rhs.show.lowercased()
    }), winner.setsLogged > 0 else { return nil }
    return .init(name: winner.show, count: winner.setsLogged)
}

private func bestPaid(_ events: [Event]) -> RecapBucket.DollarsPerSet? {
    struct Score: Comparable {
        var dps: Double
        var negSets: Int
        var show: String
        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.dps != rhs.dps { return lhs.dps < rhs.dps }
            if lhs.negSets != rhs.negSets { return lhs.negSets < rhs.negSets }
            return lhs.show < rhs.show
        }
    }
    var best: (Score, String)?
    for event in events where event.setsLogged > 0 && event.total > 0 {
        let dps = event.dollarsPerSet ?? money(event.total / Double(event.setsLogged))
        let score = Score(dps: dps, negSets: -event.setsLogged, show: event.show.lowercased())
        if best == nil || score < best!.0 { best = (score, event.show) }
    }
    return best.map { .init(name: $0.1, dollarsPerSet: $0.0.dps) }
}

private func money(_ value: Double) -> Double { (value * 100).rounded() / 100 }

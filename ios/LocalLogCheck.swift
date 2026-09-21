import Foundation

// Local write → sets / stats / recap, and the seen-set queue draining when the API answers:
//   swiftc -swift-version 5 -parse-as-library \
//     ios/Rave/Models/RaveModels.swift ios/Rave/Services/LastReadStore.swift \
//     ios/Rave/Services/Outbox.swift ios/Rave/Services/LocalLog.swift \
//     ios/Rave/Services/APIClient.swift ios/Rave/Services/ScheduleStore.swift \
//     ios/LocalLogCheck.swift -o /tmp/local-log-check && /tmp/local-log-check

private var checks = 0

private func check(_ condition: Bool, _ what: String) {
    checks += 1
    guard condition else {
        FileHandle.standardError.write(Data("FAILED: \(what)\n".utf8))
        exit(1)
    }
}

private func set(_ id: String, _ title: String, artists: [String]? = nil, date: String = "2026-09-18") -> SetEntry {
    SetEntry(
        id: id, eventId: "evt1", title: title, show: "Lost Lands", venue: "Legend Valley",
        city: "Thornville", year: 2026, date: date, artists: artists ?? [title]
    )
}

private func event(_ id: String = "evt1", setsLogged: Int = 1) -> Event {
    Event(
        id: id, show: "Lost Lands", venue: "Legend Valley", city: "Thornville", year: 2026,
        startDate: "2026-09-18", endDate: "2026-09-20", dateDisplay: nil,
        ticket: 600, travel: 0, drinksFoodMerch: 0, total: 600,
        setsLogged: setsLogged, setsSheet: nil, dollarsPerSet: setsLogged > 0 ? 600 / Double(setsLogged) : nil,
        status: .planned, days: 3, source: "user", sourceTab: nil, sets: nil
    )
}

private func slot(_ id: String, _ title: String, day: String, sort: Int, artists: [String]? = nil) -> ScheduleSlot {
    ScheduleSlot(
        id: id, day: day, stage: "Main", title: title, artists: artists ?? [title],
        startTime: "22:00", endTime: nil, startMinute: 22 * 60, endMinute: nil,
        sortIndex: sort, seen: false, setId: nil
    )
}

private func schedule(_ slots: [ScheduleSlot], selected: Set<String>, synced: [String: String] = [:]) -> ScheduleRecord {
    ScheduleRecord(
        schedule: Schedule(eventId: "evt1", days: Array(Set(slots.map(\.day))).sorted(), slots: slots),
        planned: [],
        selected: selected,
        syncedSeen: synced
    )
}

private func log(sets: [SetEntry], events: [Event]? = nil, pending: OutboxSnapshot = OutboxSnapshot(), record: ScheduleRecord? = nil) -> LocalLog {
    LocalLog.make(
        events: events ?? [event()],
        sets: sets,
        pending: pending,
        schedules: record.map { [$0] } ?? [],
        setsAreComplete: true
    )
}

private actor FakeScheduleAPI: ScheduleSyncing {
    var slots: [ScheduleSlot]
    var seen: [String: String]
    private(set) var marked: [String] = []
    private(set) var deleted: [String] = []
    var fail = false

    func setFail() { fail = true }

    init(slots: [ScheduleSlot], seen: [String: String] = [:]) {
        self.slots = slots
        self.seen = seen
    }

    func schedule(eventId: String) async throws -> Schedule {
        let painted = slots.map { slot -> ScheduleSlot in
            var slot = slot
            slot.seen = seen[slot.id] != nil
            slot.setId = seen[slot.id]
            return slot
        }
        return Schedule(eventId: eventId, days: Array(Set(slots.map(\.day))).sorted(), slots: painted)
    }

    func markSlotsSeen(eventId: String, slotIds: [String]) async throws -> BulkSetsResponse {
        if fail { throw APIError.needsSignal }
        marked.append(contentsOf: slotIds)
        for id in slotIds where seen[id] == nil { seen[id] = "server-\(id)" }
        return BulkSetsResponse(created: [], skipped: [])
    }

    func deleteSet(id: String) async throws {
        if fail { throw APIError.needsSignal }
        deleted.append(id)
        seen = seen.filter { $0.value != id }
    }
}

@main
struct LocalLogCheck {
    static func main() async {
        markSeenUpdatesSetsStatsAndRecap()
        unmarkDropsTheSet()
        unmarkOfASyncedSetRemovesThatRow()
        placeholderSurvivesUntilTheServerRowIsCached()
        cachedServerRowIsNotDuplicated()
        deletedSetIsNotResurrected()
        identicalTitlesBothLog()
        spendAndTypedSetsMoveRecapAndStats()
        unrelatedShowKeepsItsServerCount()
        await seenQueueDrainsWhenTheAPIAnswers()
        await seenQueueSurvivesAFailedSync()
        print("local log check: \(checks) assertions passed")
    }

    /// The festival tick, with no network. Sets, Stats, and Recap all move off the same projection.
    static func markSeenUpdatesSetsStatsAndRecap() {
        let stored = [set("s1", "Wooli")]
        let record = schedule(
            [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)],
            selected: ["slot-a"]
        )
        let shown = log(sets: stored, record: record)

        check(shown.sets.map(\.title) == ["Excision", "Wooli"], "the ticked set joins the list immediately, newest day first")
        let ticked = shown.sets[0]
        check(ticked.id == "pending-seen:evt1:slot-a", "the row is local until the server assigns an id")
        check(ticked.artists == ["Excision"], "the schedule's artists are the ones that count")
        check(ticked.venue == "Legend Valley" && ticked.date == "2026-09-19", "venue and day come off the show and the slot")
        check(shown.events[0].setsLogged == 2, "the show's set count includes the tick")
        check(shown.events[0].dollarsPerSet == 300, "dollars per set moves with the new count")

        let stats = shown.stats()
        check(stats.artists.map(\.name) == ["Excision", "Wooli"], "tied artists rank by name, and both are counted")
        check(stats.artists.map(\.count) == [1, 1], "each ticked set counts once")
        check(stats.venues == [StatCount(name: "Legend Valley", count: 2)], "a second day at the same venue counts as another visit")
        check(stats.cities == [StatCount(name: "Thornville", count: 2)], "and so does the city")

        let recap = shown.recap(asOf: "2026-09-19")
        check(recap.allTime.sets == 2 && recap.allTime.artists == 2, "recap set and artist totals include the tick")
        check(recap.allTime.spend == 600, "spend is unchanged by a tick")
        check(recap.allTime.topArtist?.name == "Excision", "the tie breaks the same way stats does")
        check(recap.allTime.mostSets?.count == 2, "most sets follows the new count")
        check(recap.allTime.bestDollarsPerSet?.dollarsPerSet == 300, "best dollars per set follows it too")
        check(recap.byYear["2026"]?.sets == 2, "the year bucket moves with the all-time one")
    }

    static func unmarkDropsTheSet() {
        let record = schedule(
            [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)],
            selected: []
        )
        let shown = log(sets: [set("s1", "Wooli")], record: record)
        check(shown.sets.map(\.title) == ["Wooli"], "unticking a set that never synced leaves the list as it was")
        check(shown.stats().artists.map(\.name) == ["Wooli"], "and stats")
        check(shown.recap(asOf: nil).allTime.sets == 1, "and recap")
        check(shown.events[0].setsLogged == 1 && shown.events[0].dollarsPerSet == 600, "the show count goes back")
    }

    static func unmarkOfASyncedSetRemovesThatRow() {
        let record = schedule(
            [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)],
            selected: [],
            synced: ["slot-a": "s-server"]
        )
        let shown = log(sets: [set("s1", "Wooli"), set("s-server", "Excision", date: "2026-09-19")], record: record)
        check(shown.sets.map(\.id) == ["s1"], "unticking a synced set takes that server row off the list")
        check(shown.events[0].setsLogged == 1, "and the show count")
        check(shown.recap(asOf: nil).allTime.sets == 1, "and recap")
    }

    static func placeholderSurvivesUntilTheServerRowIsCached() {
        let record = schedule(
            [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)],
            selected: ["slot-a"],
            synced: ["slot-a": "server-slot-a"]
        )
        let beforeCache = log(sets: [set("s1", "Wooli")], record: record)
        check(beforeCache.sets.contains { $0.title == "Excision" }, "after sync, before the sets snapshot catches up, the tick is still visible")

        let afterCache = log(sets: [set("s1", "Wooli"), set("server-slot-a", "Excision", date: "2026-09-19")], record: record)
        check(afterCache.sets.map(\.id) == ["s1", "server-slot-a"], "once the snapshot has the server id, the placeholder is gone")
        check(afterCache.sets.filter { $0.title == "Excision" }.count == 1, "and the set is not listed twice")
    }

    static func cachedServerRowIsNotDuplicated() {
        let record = schedule(
            [slot("slot-a", "Wooli", day: "2026-09-18", sort: 0)],
            selected: ["slot-a"]
        )
        let shown = log(sets: [set("s1", "Wooli")], record: record)
        check(shown.sets.count == 1 && shown.sets[0].id == "s1", "a tick whose title is already logged that night does not add a second row")
    }

    static func deletedSetIsNotResurrected() {
        let record = schedule(
            [slot("slot-a", "Wooli", day: "2026-09-18", sort: 0)],
            selected: ["slot-a"],
            synced: ["slot-a": "s1"]
        )
        let pending = OutboxSnapshot([.deleteSet(id: "s1")])
        let shown = log(sets: [set("s1", "Wooli")], pending: pending, record: record)
        check(shown.sets.isEmpty, "a set deleted locally stays deleted even if the schedule still says seen")
        check(shown.events[0].setsLogged == 0, "the show count follows the delete")
    }

    static func identicalTitlesBothLog() {
        let slots = [
            slot("a", "Secret Takeover", day: "2026-09-18", sort: 0),
            slot("b", "Secret Takeover", day: "2026-09-18", sort: 1),
        ]
        let shown = log(sets: [], events: [event(setsLogged: 0)], record: schedule(slots, selected: ["a", "b"]))
        check(shown.sets.count == 2, "two slots with one title are two sets")
        check(Set(shown.sets.map(\.id)).count == 2, "and they do not collapse onto one local id")
    }

    static func spendAndTypedSetsMoveRecapAndStats() {
        let pending = OutboxSnapshot([
            .logSpend(eventId: "evt1", spend: SpendDraft(ticket: 600, travel: 80, drinksFoodMerch: 20)),
            .bulkAddSets(eventId: "evt1", localIdPrefix: "local", draft: BulkSetsDraft(artists: ["Svdden Death"], date: "2026-09-18")),
        ])
        let shown = log(sets: [set("s1", "Wooli")], pending: pending)
        check(shown.sets.map(\.title) == ["Wooli", "Svdden Death"], "a typed set shows up on the list before it is sent")
        check(shown.events[0].total == 700 && shown.events[0].setsLogged == 2, "spend and the new set both land on the show")
        check(shown.events[0].dollarsPerSet == 350, "dollars per set uses the unsent spend and the unsent set")
        let recap = shown.recap(asOf: nil)
        check(recap.allTime.spend == 700 && recap.allTime.sets == 2, "recap spend and set count follow without a GET")
        check(shown.stats().artists.map(\.name).contains("Svdden Death"), "stats count the typed artist")
    }

    static func unrelatedShowKeepsItsServerCount() {
        let other = Event(
            id: "evt2", show: "Club", venue: nil, city: nil, year: 2026,
            startDate: "2026-08-01", endDate: "2026-08-01", dateDisplay: nil,
            ticket: 40, travel: 0, drinksFoodMerch: 0, total: 40,
            setsLogged: 10, setsSheet: nil, dollarsPerSet: 4,
            status: .attended, days: 1, source: "user", sourceTab: nil, sets: nil
        )
        let record = schedule(
            [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)],
            selected: ["slot-a"]
        )
        let shown = log(sets: [set("s1", "Wooli")], events: [event(), other], record: record)
        let club = shown.events.first { $0.id == "evt2" }
        check(club?.setsLogged == 10 && club?.dollarsPerSet == 4, "a tick on one show does not recompute another show off a sets snapshot that does not hold it")
    }

    static func seenQueueDrainsWhenTheAPIAnswers() async {
        let slots = [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)]
        let api = FakeScheduleAPI(slots: slots)
        let dir = tempDir()
        let store = ScheduleStore(api: api, directory: dir)
        try? await store.save(schedule(slots, selected: ["slot-a"]), for: "evt1")

        let synced = try? await store.sync(eventId: "evt1")
        let marked = await api.marked
        check(marked == ["slot-a"], "coming back online pushes the ticked slot")
        check(synced?.pendingCount == 0, "and the queue is empty once the server has it")
        check(synced?.syncedSeen["slot-a"] == "server-slot-a", "the server id replaces the local pending one")

        _ = try? await store.sync(eventId: "evt1")
        let markedAgain = await api.marked
        check(markedAgain == ["slot-a"], "a second drain does not log the same slot again")

        let reopened = ScheduleStore(api: api, directory: dir)
        let still = await reopened.record(for: "evt1")
        check(still?.pendingCount == 0 && still?.syncedSeen["slot-a"] == "server-slot-a", "the acked state is what is on disk after a force quit")
    }

    static func seenQueueSurvivesAFailedSync() async {
        let slots = [slot("slot-a", "Excision", day: "2026-09-19", sort: 1)]
        let api = FakeScheduleAPI(slots: slots)
        await api.setFail()
        let dir = tempDir()
        let store = ScheduleStore(api: api, directory: dir)
        try? await store.save(schedule(slots, selected: ["slot-a"]), for: "evt1")

        let synced = try? await store.sync(eventId: "evt1")
        check(synced == nil, "no signal does not pretend the sync landed")
        let waiting = await store.pendingSlotCount()
        check(waiting == 1, "the tick stays queued")

        let reopened = ScheduleStore(api: api, directory: dir)
        let record = await reopened.record(for: "evt1")
        check(record?.pendingAdditions == Set(["slot-a"]), "and it is still there after a force quit")
        let marked = await api.marked
        check(marked.isEmpty, "a failed push sends nothing")
    }

    static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("local-log-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

}

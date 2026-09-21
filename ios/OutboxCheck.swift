import Foundation

// Compiled against the shipping Services/Outbox.swift, so it fails if the queue or the overlay drifts:
//   swiftc -swift-version 5 -parse-as-library ios/Rave/Models/RaveModels.swift \
//     ios/Rave/Services/LastReadStore.swift ios/Rave/Services/Outbox.swift ios/Rave/Services/LocalLog.swift \
//     ios/Rave/Services/APIClient.swift ios/Rave/Services/ScheduleStore.swift ios/OutboxCheck.swift \
//     -o /tmp/outbox-check && /tmp/outbox-check

private var checks = 0

private func check(_ condition: Bool, _ what: String) {
    checks += 1
    guard condition else {
        FileHandle.standardError.write(Data("FAILED: \(what)\n".utf8))
        exit(1)
    }
}

private func set(_ id: String, _ title: String, artists: [String], date: String? = "2026-09-18") -> SetEntry {
    SetEntry(id: id, eventId: "evt1", title: title, show: nil, venue: nil, city: nil, year: 2026, date: date, artists: artists)
}

private func event(_ id: String, sets: [SetEntry]? = nil) -> Event {
    Event(
        id: id, show: "Lost Lands", venue: nil, city: nil, year: 2026,
        startDate: "2026-09-18", endDate: "2026-09-20", dateDisplay: nil,
        ticket: 420, travel: 0, drinksFoodMerch: 0, total: 420,
        setsLogged: sets?.count ?? 0, setsSheet: nil, dollarsPerSet: nil,
        status: .planned, days: 3, source: "user", sourceTab: nil, sets: sets
    )
}

/// Answers whatever the script queued for it, so a flush can be driven without a server.
private actor FakeAPI: OutboxSyncing {
    private var outcomes: [Error?]
    private(set) var seen: [PendingWrite] = []

    init(_ outcomes: [Error?]) { self.outcomes = outcomes }

    @discardableResult
    func perform(_ write: PendingWrite) async throws -> String? {
        seen.append(write)
        if !outcomes.isEmpty, let error = outcomes.removeFirst() { throw error }
        if case .createEvent = write { return "evt-from-server" }
        return nil
    }

    var sentCount: Int { seen.count }
}

@main
struct OutboxCheck {
    static func main() async {
        await overlayShowsUnsentEdits()
        await queueSurvivesRelaunch()
        await flushDrainsInOrder()
        await transientFailureHoldsTheRest()
        await permanentFailureDoesNotWedgeTheQueue()
        await replayIsAtMostOnce()
        await setsFollowTheShowTheyWereAddedTo()
        print("outbox check: \(checks) assertions passed")
    }

    /// The reported bug. Editing the artists on a b2b set with no signal has to survive the
    /// refetch that follows the save, which reads last-read and would otherwise show the old names.
    static func overlayShowsUnsentEdits() async {
        let stored = [set("s1", "Excision b2b Space Laces", artists: ["Excision", "Space Laces"])]
        let pending = OutboxSnapshot([
            .updateSet(id: "s1", patch: SetPatch(title: "Excision b2b Space Laces", artists: ["Excision", "Space Laces", "Subtronics"], date: nil))
        ])
        let shown = pending.apply(to: stored)
        check(shown.count == 1, "patching a set does not add a row")
        check(shown[0].artists == ["Excision", "Space Laces", "Subtronics"], "the unsent artist edit is what the list shows")

        let removed = OutboxSnapshot([.deleteSet(id: "s1")]).apply(to: stored)
        check(removed.isEmpty, "an unsent delete takes the row off the list")

        let added = OutboxSnapshot([
            .bulkAddSets(eventId: "evt1", localIdPrefix: "local-a", draft: BulkSetsDraft(artists: ["Sullivan King", "Excision b2b Space Laces"], date: "2026-09-18"))
        ]).apply(to: stored)
        check(added.count == 2, "bulk add skips a title already on that night, like the server does")
        check(added[1].title == "Sullivan King", "the new line is the one that was not already there")
        check(added[1].artists == ["Sullivan King"], "a plain title is its own artist")

        let split = OutboxSnapshot([
            .bulkAddSets(eventId: "evt1", localIdPrefix: "local-b", draft: BulkSetsDraft(artists: ["Kai Wachi b2b Zomboy"], date: "2026-09-19"))
        ]).apply(to: [SetEntry]())
        check(split[0].artists == ["Kai Wachi", "Zomboy"], "a b2b line becomes two artists")

        let spent = OutboxSnapshot([
            .logSpend(eventId: "evt1", spend: SpendDraft(ticket: 420, travel: 180, drinksFoodMerch: 100))
        ]).apply(to: event("evt1", sets: [set("s1", "A", artists: ["A"]), set("s2", "B", artists: ["B"])]))
        check(spent.total == 700, "unsent spend recomputes the total")
        check(spent.dollarsPerSet == 350, "and the dollars per set that hangs off it")

        let created = OutboxSnapshot([
            .createEvent(localId: "local-x", draft: EventDraft(show: "Forbidden Kingdom", venue: nil, city: nil, startDate: "2027-03-05", endDate: nil, ticket: 300, travel: 0, drinksFoodMerch: 0))
        ]).apply(to: [event("evt1")])
        check(created.count == 2, "a show created offline appears in the list")
        check(created[1].show == "Forbidden Kingdom" && created[1].status == .planned, "a future show created offline reads as planned")

        let detail = OutboxSnapshot([.deleteSet(id: "s2")]).apply(to: event("evt1", sets: [set("s1", "A", artists: ["A"]), set("s2", "B", artists: ["B"])]))
        check(detail.sets?.count == 1 && detail.setsLogged == 1, "a show's own set count follows an unsent delete")
    }

    static func queueSurvivesRelaunch() async {
        let dir = tempDir()
        let first = Outbox(directory: dir)
        await first.enqueue(.updateSet(id: "s1", patch: SetPatch(title: nil, artists: ["Wooli"], date: nil)))
        await first.enqueue(.deleteSet(id: "s2"))

        let reopened = Outbox(directory: dir)
        let count = await reopened.count
        check(count == 2, "the queue is still there after a force quit")
        let writes = await reopened.snapshot.writes
        check(writes.first == .updateSet(id: "s1", patch: SetPatch(title: nil, artists: ["Wooli"], date: nil)), "and in the order it was typed")
    }

    static func flushDrainsInOrder() async {
        let outbox = Outbox(directory: tempDir())
        await outbox.enqueue(.updateSet(id: "s1", patch: SetPatch(title: "one", artists: nil, date: nil)))
        await outbox.enqueue(.updateSet(id: "s2", patch: SetPatch(title: "two", artists: nil, date: nil)))
        await outbox.enqueue(.deleteSet(id: "s3"))

        let api = FakeAPI([])
        let sent = await outbox.flush(using: api)
        check(sent == 3, "a reachable server takes every waiting write")
        let empty = await outbox.count
        check(empty == 0, "and the queue empties")
        let seen = await api.seen
        check(seen == [
            .updateSet(id: "s1", patch: SetPatch(title: "one", artists: nil, date: nil)),
            .updateSet(id: "s2", patch: SetPatch(title: "two", artists: nil, date: nil)),
            .deleteSet(id: "s3"),
        ], "in the order the user made them")
    }

    /// Order is the invariant: a later edit must never land on the server ahead of the earlier
    /// one it was typed on top of.
    static func transientFailureHoldsTheRest() async {
        let outbox = Outbox(directory: tempDir())
        await outbox.enqueue(.updateSet(id: "s1", patch: SetPatch(title: "one", artists: nil, date: nil)))
        await outbox.enqueue(.updateSet(id: "s2", patch: SetPatch(title: "two", artists: nil, date: nil)))
        await outbox.enqueue(.updateSet(id: "s3", patch: SetPatch(title: "three", artists: nil, date: nil)))

        let api = FakeAPI([nil, APIError.needsSignal])
        let sent = await outbox.flush(using: api)
        check(sent == 1, "signal dropping mid-flush stops after the write that got through")
        let left = await outbox.count
        check(left == 2, "the rest stay queued")

        let resumed = FakeAPI([])
        _ = await outbox.flush(using: resumed)
        let order = await resumed.seen
        check(order.map { if case .updateSet(let id, _) = $0 { return id } else { return "" } } == ["s2", "s3"], "and go up in order when signal returns")
    }

    static func permanentFailureDoesNotWedgeTheQueue() async {
        let outbox = Outbox(directory: tempDir())
        await outbox.enqueue(.updateSet(id: "gone", patch: SetPatch(title: "edit to a deleted set", artists: nil, date: nil)))
        await outbox.enqueue(.updateSet(id: "s2", patch: SetPatch(title: "still good", artists: nil, date: nil)))

        let api = FakeAPI([APIError.http(404), nil])
        let sent = await outbox.flush(using: api)
        check(sent == 2, "a write the server will always refuse is dropped rather than retried forever")
        let left = await outbox.count
        check(left == 0, "so the write behind it still lands")
    }

    static func replayIsAtMostOnce() async {
        let outbox = Outbox(directory: tempDir())
        await outbox.enqueue(.deleteSet(id: "s1"))
        let api = FakeAPI([])
        _ = await outbox.flush(using: api)
        _ = await outbox.flush(using: api)
        let count = await api.sentCount
        check(count == 1, "a second flush does not resend a write the server already took")
    }

    /// A show created with no signal is queued under a local id. Anything logged against it
    /// before the create goes up would 404 and be dropped unless the flush readdresses it.
    static func setsFollowTheShowTheyWereAddedTo() async {
        let outbox = Outbox(directory: tempDir())
        await outbox.enqueue(.createEvent(localId: "local-x", draft: EventDraft(show: "Basement Show", venue: nil, city: nil, startDate: "2026-11-01", endDate: nil, ticket: 30, travel: 0, drinksFoodMerch: 0)))
        await outbox.enqueue(.bulkAddSets(eventId: "local-x", localIdPrefix: "local-y", draft: BulkSetsDraft(artists: ["Hamdi"], date: "2026-11-01")))
        await outbox.enqueue(.logSpend(eventId: "local-x", spend: SpendDraft(ticket: 30, travel: 12, drinksFoodMerch: 0)))

        let api = FakeAPI([])
        let sent = await outbox.flush(using: api)
        check(sent == 3, "the show and everything logged against it all go up")
        let seen = await api.seen
        if case .bulkAddSets(let eventId, _, _) = seen[1] {
            check(eventId == "evt-from-server", "the sets are addressed to the id the server gave the show")
        } else {
            check(false, "the second write is the bulk add")
        }
        if case .logSpend(let eventId, _) = seen[2] {
            check(eventId == "evt-from-server", "and so is the spend")
        } else {
            check(false, "the third write is the spend")
        }
    }

    static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-check-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

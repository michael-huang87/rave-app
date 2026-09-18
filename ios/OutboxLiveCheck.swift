import Foundation

// Drives the shipping APIClient over real URLSession, in three separate processes, because a
// force quit between the edit and the signal coming back is the case that matters:
//   scripts/verify_outbox.sh

private var checks = 0

private func check(_ condition: Bool, _ what: String) {
    checks += 1
    guard condition else {
        FileHandle.standardError.write(Data("FAILED: \(what)\n".utf8))
        exit(1)
    }
}

private let targetSetId = ProcessInfo.processInfo.environment["RAVE_CHECK_SET_ID"] ?? ""
private let editedArtists = ["Sullivan King", "Ray Volpe", "Excision", "Subtronics"]

@main
struct OutboxLiveCheck {
    static func main() async {
        switch CommandLine.arguments.dropFirst().first ?? "" {
        case "online-first": await onlineFirst()
        case "offline-edit": await offlineEdit()
        case "back-online": await backOnline()
        default:
            FileHandle.standardError.write(Data("usage: outbox-live-check <online-first|offline-edit|back-online>\n".utf8))
            exit(2)
        }
        print("\(CommandLine.arguments[1]): \(checks) assertions passed")
    }

    /// A normal loaded session, which is what leaves the last-read cache the offline leg reads from.
    static func onlineFirst() async {
        let waiting = await Outbox.shared.count
        check(waiting == 0, "the queue starts empty")
        guard let read = try? await APIClient.shared.sets() else {
            check(false, "the scratch backend answered /sets")
            return
        }
        check(!read.fromCache, "with a reachable server the read is live")
        check(read.value.contains { $0.id == targetSetId }, "the set under test is in the loaded data")
    }

    /// The reported bug, end to end: edit the artists on a b2b set with no signal, then read the
    /// list back the way the screen does after saving.
    static func offlineEdit() async {
        let before = await Outbox.shared.count
        check(before == 0, "nothing is waiting before the edit")

        do {
            try await APIClient.shared.submit(
                .updateSet(id: targetSetId, patch: SetPatch(title: nil, artists: editedArtists, date: nil))
            )
        } catch {
            check(false, "saving with no signal does not throw, it queues: \(error)")
        }

        let queued = await Outbox.shared.count
        check(queued == 1, "the edit is on the queue instead of lost")

        guard let read = try? await APIClient.shared.sets() else {
            check(false, "reading with no signal still answers from cache")
            return
        }
        check(read.fromCache, "that read came from the cache")
        let edited = read.value.first { $0.id == targetSetId }
        check(edited?.artists == editedArtists, "and shows the artists just typed, not the stale ones")
    }

    static func backOnline() async {
        let waiting = await Outbox.shared.count
        check(waiting == 1, "the queued edit survived the force quit")

        let sent = await APIClient.shared.flushOutbox()
        check(sent == 1, "signal coming back sends it")
        let left = await Outbox.shared.count
        check(left == 0, "and empties the queue")

        guard let read = try? await APIClient.shared.sets() else {
            check(false, "the server answered after the flush")
            return
        }
        check(!read.fromCache, "the read is live again")
        let landed = read.value.first { $0.id == targetSetId }
        check(landed?.artists == editedArtists, "the server now has the artists typed with no signal")
    }
}

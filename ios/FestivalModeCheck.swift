import Foundation

// Compiled against the shipping Models/RaveModels.swift, so it fails if FestivalMode drifts:
//   swiftc -parse-as-library ios/Rave/Models/RaveModels.swift ios/FestivalModeCheck.swift \
//     -o /tmp/festival-mode-check && /tmp/festival-mode-check

private let cal = Calendar(identifier: .gregorian)
private var checks = 0

private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute) = (parts[0], parts[1], parts[2], hour, minute)
    return cal.date(from: c)!
}

private func check(_ condition: Bool, _ what: String) {
    checks += 1
    guard condition else {
        FileHandle.standardError.write(Data("FAILED: \(what)\n".utf8))
        exit(1)
    }
}

private func show(_ id: String, _ start: String, _ end: String?) -> Event {
    Event(
        id: id, show: id, venue: nil, city: nil, year: nil,
        startDate: start, endDate: end, dateDisplay: nil,
        ticket: 0, travel: 0, drinksFoodMerch: 0, total: 0,
        setsLogged: 0, setsSheet: nil, dollarsPerSet: nil,
        status: .planned, days: 3, source: nil, sourceTab: nil, sets: nil
    )
}

@main
struct FestivalModeCheck {
    static func main() {
        let lostLands = show("lost-lands", "2026-09-18", "2026-09-20")
        let emberShores = show("ember-shores", "2026-11-20", "2026-11-22")
        let shows = [emberShores, lostLands]

        // On for the festival happening now, with nothing stored.
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-19", 21)).first?.id == "lost-lands", "on during")
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-18", 0)).first?.id == "lost-lands", "on from the first midnight")
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-21", 2)).first?.id == "lost-lands", "02:00 belongs to the last night")
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-21", 5, 59)).first?.id == "lost-lands", "still before the rollover")
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-21", 6)).isEmpty, "off at the rollover")
        check(FestivalMode.candidates(in: shows, override: .auto, now: at("2026-09-17", 23)).isEmpty, "off the night before")

        // On early by hand, and off again during.
        let early = at("2026-09-10", 12)
        check(FestivalMode.candidates(in: shows, override: .on("lost-lands"), now: early).first?.id == "lost-lands", "on early")
        check(FestivalMode.candidates(in: shows, override: .on("lost-lands"), now: at("2026-09-21", 6)).isEmpty, "an early on still expires")
        check(FestivalMode.candidates(in: shows, override: .off("lost-lands"), now: at("2026-09-19", 21)).isEmpty, "off during")
        check(FestivalMode.candidates(in: shows, override: .off("ember-shores"), now: at("2026-09-19", 21)).first?.id == "lost-lands", "off names another festival")
        check(FestivalMode.candidates(in: shows, override: .on("ember-shores"), now: at("2026-09-19", 21)).first?.id == "ember-shores", "an explicit on wins")
        check(FestivalMode.candidates(in: shows, override: .on("gone"), now: at("2026-09-19", 21)).first?.id == "lost-lands", "an override naming nothing falls through")

        // One show at a time, the shape the detail toggle asks in.
        check(!FestivalMode.candidates(in: [lostLands], override: .auto, now: at("2026-09-19", 21)).isEmpty, "toggle reads on during")
        check(FestivalMode.candidates(in: [lostLands], override: .auto, now: early).isEmpty, "toggle reads off before")
        check(!FestivalMode.candidates(in: [lostLands], override: .on("lost-lands"), now: early).isEmpty, "toggle reads on when armed early")

        // A show with no end date is a one-night show.
        let oneNight = show("club", "2026-09-18", nil)
        check(FestivalMode.isRunning(oneNight, now: at("2026-09-19", 5)), "one night runs past midnight")
        check(!FestivalMode.isRunning(oneNight, now: at("2026-09-19", 6)), "and still expires")
        check(FestivalMode.hasEnded(show("undated", "", nil)), "an undated show is over")

        // The stored override round-trips, and anything else reads as nothing stored.
        for value in [FestivalMode.Override.auto, .on("lost-lands"), .off("lost-lands")] {
            check(FestivalMode.Override(raw: value.raw) == value, "round-trips \(value.raw)")
        }
        check(FestivalMode.Override(raw: "garbage") == .auto, "garbage reads as auto")
        check(FestivalMode.Override(raw: "on:a:b") == .on("a:b"), "an id keeps its colons")

        // A show sharing the weekend must not shadow the festival that has the schedule.
        let clubNight = show("club-night", "2026-09-19", "2026-09-19")
        let weekend = [clubNight, lostLands]
        check(
            FestivalMode.candidates(in: weekend, override: .auto, now: at("2026-09-19", 21)).map(\.id)
                == ["club-night", "lost-lands"],
            "both running shows are offered, in order"
        )
        check(
            FestivalMode.candidates(in: weekend, override: .off("club-night"), now: at("2026-09-19", 21)).map(\.id)
                == ["lost-lands"],
            "off drops only the show it names"
        )

        // The day picker opens on tonight.
        let days = ["2026-09-18", "2026-09-19", "2026-09-20"]
        check(FestivalMode.currentDay(in: days, now: at("2026-09-19", 21)) == "2026-09-19", "tonight")
        check(FestivalMode.currentDay(in: days, now: at("2026-09-20", 3)) == "2026-09-19", "03:00 is still last night")
        check(FestivalMode.currentDay(in: days, now: at("2026-09-20", 7)) == "2026-09-20", "past 06:00 it rolls over")
        check(FestivalMode.currentDay(in: days, now: early) == nil, "before the schedule opens")

        print("FestivalMode: \(checks) checks passed")
    }
}

import Foundation

// Compiled against the shipping Models/RaveModels.swift, so it fails if FestivalMode drifts:
//   swiftc -parse-as-library ios/Rave/Models/RaveModels.swift ios/FestivalModeCheck.swift \
//     -o /tmp/festival-mode-check && /tmp/festival-mode-check

private let cal = Calendar(identifier: .gregorian)

private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute) = (parts[0], parts[1], parts[2], hour, minute)
    return cal.date(from: c)!
}

private func festival(start: String, end: String?) -> Event {
    Event(
        id: "e", show: "Verify Fest", venue: nil, city: nil, year: nil,
        startDate: start, endDate: end, dateDisplay: nil,
        ticket: 0, travel: 0, drinksFoodMerch: 0, total: 0,
        setsLogged: 0, setsSheet: nil, dollarsPerSet: nil,
        status: .planned, days: 3, source: nil, sourceTab: nil, sets: nil
    )
}

@main
struct FestivalModeCheck {
    static func main() {
        let fest = festival(start: "2026-09-18", end: "2026-09-20")

        assert(FestivalMode.isActive(fest, now: at("2026-09-15", 12)), "armed before it starts")
        assert(FestivalMode.isActive(fest, now: at("2026-09-20", 23)), "last night")
        assert(FestivalMode.isActive(fest, now: at("2026-09-21", 2)), "02:00 belongs to the last night")
        assert(FestivalMode.isActive(fest, now: at("2026-09-21", 5, 59)), "still before the 06:00 rollover")
        assert(!FestivalMode.isActive(fest, now: at("2026-09-21", 6)), "deactivates at the rollover")
        assert(!FestivalMode.isActive(fest, now: at("2026-09-25", 12)), "long over")

        let oneNight = festival(start: "2026-09-18", end: nil)
        assert(FestivalMode.isActive(oneNight, now: at("2026-09-19", 5)), "no end date falls back to the start")
        assert(!FestivalMode.isActive(oneNight, now: at("2026-09-19", 6)), "and still expires")

        let days = ["2026-09-18", "2026-09-19", "2026-09-20"]
        assert(FestivalMode.currentDay(in: days, now: at("2026-09-19", 21)) == "2026-09-19", "tonight")
        assert(FestivalMode.currentDay(in: days, now: at("2026-09-20", 3)) == "2026-09-19", "03:00 is still last night")
        assert(FestivalMode.currentDay(in: days, now: at("2026-09-20", 7)) == "2026-09-20", "past 06:00 it rolls over")
        assert(FestivalMode.currentDay(in: days, now: at("2026-09-15", 12)) == nil, "before the schedule opens")

        print("FestivalMode: 12 assertions passed")
    }
}

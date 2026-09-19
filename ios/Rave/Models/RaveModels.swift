import SwiftUI

enum RaveTheme {
    static let accent = Color(red: 0.92, green: 0.28, blue: 0.72)
    static let accent2 = Color(red: 0.35, green: 0.85, blue: 0.95)
    static let bg = Color.black
    static let card = Color(red: 0.10, green: 0.10, blue: 0.12)

    // Both list tabs pack one line per row; the stock insets are built for two.
    static let rowInsets = EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)
    static let headerInsets = EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16)
}

enum EventStatus: String, Codable, CaseIterable, Identifiable {
    case attended, planned, skipped
    var id: String { rawValue }

    var label: String {
        switch self {
        case .attended: return "Went"
        case .planned: return "Planned"
        case .skipped: return "Skipped"
        }
    }

    var tint: Color {
        switch self {
        case .attended: return RaveTheme.accent2
        case .planned: return RaveTheme.accent
        case .skipped: return .secondary
        }
    }
}

struct Event: Identifiable, Codable, Hashable {
    var id: String
    var show: String
    var venue: String?
    var city: String?
    var year: Int?
    var startDate: String?
    var endDate: String?
    var dateDisplay: String?
    var ticket: Double
    var travel: Double
    var drinksFoodMerch: Double
    var total: Double
    var setsLogged: Int
    var setsSheet: Int?
    var dollarsPerSet: Double?
    var status: EventStatus
    var days: Int?
    var source: String?
    var sourceTab: String?
    var sets: [SetEntry]?

    /// The sheet dates a festival as a range; a single night is a show.
    var isFestival: Bool { (days ?? 1) > 1 }

    /// Every night the event covers, logged or not, so a night with nothing on it is still offerable.
    var nights: [String] {
        guard let startDate else { return [] }
        guard let endDate,
              let from = isoDayFormatter.date(from: startDate),
              let to = isoDayFormatter.date(from: endDate),
              to >= from else { return [startDate] }
        var days: [String] = []
        var cursor = from
        while cursor <= to, let next = gmtCalendar.date(byAdding: .day, value: 1, to: cursor) {
            days.append(isoDayFormatter.string(from: cursor))
            cursor = next
        }
        return days
    }
}

private let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

private let nightFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

private let gmtCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

/// Day numbers come off the event's start date, so a night with nothing logged still counts.
func nightLabel(_ iso: String, index: Int, start: String?) -> String {
    let date = isoDayFormatter.date(from: iso)
    var number = index + 1
    if let date, let start, let from = isoDayFormatter.date(from: start),
       let offset = gmtCalendar.dateComponents([.day], from: from, to: date).day, offset >= 0 {
        number = offset + 1
    }
    return ["Day \(number)", date.map { nightFormatter.string(from: $0) }]
        .compactMap { $0 }
        .joined(separator: " · ")
}

struct SetEntry: Identifiable, Codable, Hashable {
    var id: String
    var eventId: String
    var title: String
    var show: String?
    var venue: String?
    var city: String?
    var year: Int?
    var date: String?
    var artists: [String]
}

struct RecapBucket: Codable, Hashable {
    struct SpendByType: Codable, Hashable {
        var ticket: Double
        var travel: Double
        var drinksFoodMerch: Double
    }

    struct NamedCount: Codable, Hashable {
        var name: String
        var count: Int
    }

    struct DollarsPerSet: Codable, Hashable {
        var name: String
        var dollarsPerSet: Double
    }

    var sets: Int
    var artists: Int
    var setTitles: Int?
    var shows: Int
    var events: Int
    var venues: Int
    var cities: Int
    var spend: Double
    var spendByType: SpendByType
    var topArtist: NamedCount?
    var topCity: NamedCount?
    var mostSets: NamedCount?
    var bestDollarsPerSet: DollarsPerSet?
}

struct Recap: Codable {
    var asOf: String?
    var allTime: RecapBucket
    var byYear: [String: RecapBucket]
}

struct StatCount: Codable, Hashable, Identifiable {
    var name: String
    var count: Int
    var id: String { name }
}

/// Mirrors the sheet's ArtistsVenues tab: artists by sets seen, venues and cities by distinct days.
struct Stats: Codable {
    var artists: [StatCount]
    var venues: [StatCount]
    var cities: [StatCount]
}

struct EventDraft: Codable, Equatable {
    var show: String
    var venue: String?
    var city: String?
    var startDate: String?
    var endDate: String?
    var ticket: Double
    var travel: Double
    var drinksFoodMerch: Double
}

struct SpendDraft: Codable, Equatable {
    var ticket: Double
    var travel: Double
    var drinksFoodMerch: Double
}

struct BulkSetsDraft: Codable, Equatable {
    var artists: [String]
    var date: String?
}

struct EventPatch: Codable, Equatable {
    var show: String
    var venue: String?
    var city: String?
    var startDate: String?
    var endDate: String?
}

struct BulkSetsResponse: Codable {
    var created: [SetEntry]
    var skipped: [String]
}

struct SetPatch: Codable, Equatable {
    var title: String?
    var artists: [String]?
    var date: String?
}

struct ScheduleSlot: Identifiable, Codable, Hashable {
    var id: String
    var day: String
    var stage: String?
    var title: String
    var artists: [String]
    var startTime: String?
    var endTime: String?
    var startMinute: Int?
    var endMinute: Int?
    var sortIndex: Int
    var seen: Bool
    var setId: String?

    var stageKey: String { stage ?? "Unlisted" }
}

struct Schedule: Codable, Hashable {
    var eventId: String
    var days: [String]
    var slots: [ScheduleSlot]
}

/// Dark-mode categorical slots, validated as an adjacent pairlist rather than all-pairs: at this
/// cardinality only neighbours are guaranteed to separate, so the order is the guarantee.
/// Assign in this order, never cycle, never generate.
enum StagePalette {
    static let colors: [Color] = [
        Color(hex: 0x3987E5), Color(hex: 0xD95926), Color(hex: 0x199E70), Color(hex: 0xC98500),
        Color(hex: 0xD55181), Color(hex: 0x008300), Color(hex: 0x9085E9), Color(hex: 0xE66767),
    ]
    static let overflow = Color(white: 0.55)

    /// First appearance across the whole schedule in running order, so a filter that drops stages
    /// cannot repaint the survivors.
    static func order(_ schedule: Schedule) -> [String] {
        schedule.slots.sorted { $0.sortIndex < $1.sortIndex }.grouped(by: \.stageKey).map(\.key)
    }

    static func color(_ stage: String, in order: [String]) -> Color {
        guard let index = order.firstIndex(of: stage), index < colors.count else { return overflow }
        return colors[index]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// One day's slots placed on the shared vertical axis the server already computed.
struct ScheduleDayLayout {
    struct Block: Identifiable {
        var slot: ScheduleSlot
        var start: Int
        var length: Int
        var id: String { slot.id }
    }

    static let openEndedLength = 60

    var columns: [(stage: String, blocks: [Block])]
    var start: Int
    var end: Int
    /// Wall-clock minutes minus axis minutes, read off a slot carrying both, so the festival day's
    /// 06:00 boundary stays the server's rule and is never restated here.
    var clockOffset: Int

    init?(schedule: Schedule, day: String, stageOrder: [String]) {
        let timed = schedule.slots.compactMap { slot -> (slot: ScheduleSlot, start: Int)? in
            guard slot.day == day, let start = slot.startMinute else { return nil }
            return (slot, start)
        }
        guard let first = timed.map(\.start).min() else { return nil }

        columns = stageOrder.compactMap { stage in
            let column = timed.filter { $0.slot.stageKey == stage }.sorted { $0.start < $1.start }
            guard !column.isEmpty else { return nil }
            let blocks = column.enumerated().map { index, entry -> Block in
                let end = entry.slot.endMinute
                    ?? (index + 1 < column.count ? column[index + 1].start : entry.start + Self.openEndedLength)
                return Block(slot: entry.slot, start: entry.start, length: max(1, end - entry.start))
            }
            return (stage, blocks)
        }
        start = first
        end = columns.flatMap(\.blocks).map { $0.start + $0.length }.max() ?? first
        clockOffset = timed.lazy.compactMap { entry in
            ScheduleDayLayout.clockMinutes(entry.slot.startTime).map { $0 - entry.start }
        }.first ?? 0
    }

    var hourMarks: [Int] {
        let aligned = start + (60 - (start + clockOffset) % 60) % 60
        return Array(stride(from: aligned, through: end, by: 60))
    }

    func hourLabel(_ minute: Int) -> String {
        clockHourLabel((((minute + clockOffset) % 1440) + 1440) % 1440 / 60)
    }

    /// Where a wall clock reading sits on this day's axis, or nil when it falls outside the range
    /// the grid draws. The axis is anchored at the festival day's rollover rather than midnight,
    /// which is what lets 03:00 sit below 23:00 instead of jumping to the top.
    func axisMinute(clockMinutes clock: Int) -> Int? {
        let base = (((clock - clockOffset) % 1440) + 1440) % 1440
        return (0...1).lazy.map { base + $0 * 1440 }.first { $0 >= start && $0 <= end }
    }

    private static func clockMinutes(_ time: String?) -> Int? {
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

/// Set times arrive as a wall clock "HH:MM" with no date attached, so they are reformatted
/// directly rather than round-tripped through Date. A festival night runs past midnight, which is
/// why the meridiem is never dropped to save width: 01:00 and 13:00 are both on the same page.
/// Minutes past local midnight. Local, not GMT: the line marks where the person standing in the
/// field is in the night, and at a west coast festival GMT is already tomorrow.
func clockMinutes(of date: Date, calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

func clockLabel(_ time: String?) -> String? {
    let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
    return String(format: "%d:%02d %@", hour12(parts[0]), parts[1], parts[0] < 12 ? "AM" : "PM")
}

/// The grid's hour gutter, which is always on the hour and wants the width back. Named apart from
/// `ScheduleDayLayout.hourLabel` on purpose: same signature and the member would shadow it, which
/// turns the call inside that method into infinite recursion.
func clockHourLabel(_ hour24: Int) -> String {
    "\(hour12(hour24)) \(hour24 < 12 ? "AM" : "PM")"
}

private func hour12(_ hour24: Int) -> Int {
    let hour = hour24 % 12
    return hour == 0 ? 12 : hour
}

struct MarkSeenDraft: Codable {
    var slotIds: [String]
}

extension Double {
    var usd: String {
        String(format: "$%.2f", self)
    }
}

extension Array {
    /// Groups into sections without reordering: keys come out in the order they were first seen,
    /// so the caller's sort survives. Both list tabs rely on the server's ordering.
    func grouped<Key: Hashable>(by key: (Element) -> Key) -> [(key: Key, values: [Element])] {
        var order: [Key] = []
        var buckets: [Key: [Element]] = [:]
        for element in self {
            let k = key(element)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(element)
        }
        return order.map { (key: $0, values: buckets[$0] ?? []) }
    }
}

/// Festival mode is on for the festival happening now, so getting to the schedule on the day costs
/// nothing and needs no setup. The stored value is only an override. Turn it on to reach a
/// festival's schedule before the first night, or off to put the tab away during one. Either way
/// the override dies with its festival and never leaks into the next one.
enum FestivalMode {
    static let storageKey = "festivalModeOverride"
    /// The server's rollover, restated because the phone decides this one. A night runs past
    /// midnight, so the festival is not over until 06:00 the morning after the last night.
    static let dayRolloverHour = 6

    enum Override: Equatable {
        case auto
        case on(String)
        case off(String)

        init(raw: String) {
            let parts = raw.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { self = .auto; return }
            switch parts[0] {
            case "on": self = .on(String(parts[1]))
            case "off": self = .off(String(parts[1]))
            default: self = .auto
            }
        }

        var raw: String {
            switch self {
            case .auto: return ""
            case .on(let id): return "on:\(id)"
            case .off(let id): return "off:\(id)"
            }
        }

        var eventId: String? {
            switch self {
            case .auto: return nil
            case .on(let id), .off(let id): return id
            }
        }
    }

    /// Whose schedule could belong in the tab bar, best first, so a club show sharing the weekend
    /// with a festival cannot shadow the one that has a schedule. The caller keeps the first that
    /// has one. Pass a one-event list to ask about that one show.
    ///
    /// An explicit on wins outright, because turning it on early is a deliberate act.
    static func candidates(in events: [Event], override: Override, now: Date = Date()) -> [Event] {
        if case .on(let id) = override,
           let armed = events.first(where: { $0.id == id }), !hasEnded(armed, now: now) {
            return [armed]
        }
        let running = events.filter { isRunning($0, now: now) }
        if case .off(let id) = override { return running.filter { $0.id != id } }
        return running
    }

    /// On from the first midnight through 06:00 after the last night. Both ends err towards on,
    /// because arriving a day early and leaving after a long last night are the two ways a rave-goer
    /// actually meets a festival.
    static func isRunning(_ event: Event, now: Date = Date()) -> Bool {
        guard let iso = event.startDate, let start = localDayFormatter.date(from: iso) else { return false }
        return now >= start && !hasEnded(event, now: now)
    }

    static func hasEnded(_ event: Event, now: Date = Date()) -> Bool {
        guard let iso = event.endDate ?? event.startDate,
              let end = localDayFormatter.date(from: iso),
              let deadline = localCalendar.date(byAdding: .hour, value: 24 + dayRolloverHour, to: end)
        else { return true }
        return now >= deadline
    }

    /// The festival day `now` falls in, when the schedule has one, so the day picker opens on
    /// tonight rather than on day 1.
    static func currentDay(in days: [String], now: Date = Date()) -> String? {
        let anchor = localCalendar.component(.hour, from: now) < dayRolloverHour
            ? localCalendar.date(byAdding: .day, value: -1, to: now) ?? now
            : now
        let iso = localDayFormatter.string(from: anchor)
        return days.contains(iso) ? iso : nil
    }
}

/// Local, not GMT: the deadline is 06:00 where the phone is standing.
private let localDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let localCalendar = Calendar(identifier: .gregorian)

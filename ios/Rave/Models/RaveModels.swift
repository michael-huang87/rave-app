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

struct EventDraft: Codable {
    var show: String
    var venue: String?
    var city: String?
    var startDate: String?
    var endDate: String?
    var ticket: Double
    var travel: Double
    var drinksFoodMerch: Double
}

struct SpendDraft: Codable {
    var ticket: Double
    var travel: Double
    var drinksFoodMerch: Double
}

struct SetDraft: Codable {
    var title: String
    var artists: [String]
    var date: String?
}

struct BulkSetsDraft: Codable {
    var artists: [String]
    var date: String?
}

struct BulkSetsResponse: Codable {
    var created: [SetEntry]
    var skipped: [String]
}

struct SetPatch: Codable {
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
        String(format: "%02d:00", (((minute + clockOffset) % 1440) + 1440) % 1440 / 60)
    }

    private static func clockMinutes(_ time: String?) -> Int? {
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
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

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
    var source: String?
    var sourceTab: String?
    var sets: [SetEntry]?
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

struct RecapBucket: Codable {
    var sets: Int
    var artists: Int
    var setTitles: Int?
    var shows: Int
    var events: Int
    var venues: Int
    var cities: Int
    var spend: Double
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

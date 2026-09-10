import Foundation

/// On-disk last successful GET. Lives in Application Support so iOS does not
/// evict it the way it can evict Caches. Envelope: `{ saved_at, payload }`.
struct LastReadEnvelope<T: Codable>: Codable {
    var savedAt: Date
    var payload: T
}

enum LastReadKey: Equatable {
    case events
    case event(String)
    case sets
    case recap
    case stats

    var filename: String {
        switch self {
        case .events: return "events.json"
        case .sets: return "sets.json"
        case .recap: return "recap.json"
        case .stats: return "stats.json"
        case .event(let id):
            let safe = id.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            return "event-\(safe).json"
        }
    }
}

struct ReadResult<T> {
    var value: T
    var fromCache: Bool
    var cachedAt: Date?
}

struct LastReadStore {
    let directory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Rave/LastRead", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func save<T: Codable>(_ payload: T, key: LastReadKey) {
        let envelope = LastReadEnvelope(savedAt: Date(), payload: payload)
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(to: directory.appendingPathComponent(key.filename), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, key: LastReadKey) -> LastReadEnvelope<T>? {
        let url = directory.appendingPathComponent(key.filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LastReadEnvelope<T>.self, from: data)
    }
}

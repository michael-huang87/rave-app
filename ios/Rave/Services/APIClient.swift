import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad API URL"
        case .http(let code): return "Server returned \(code)"
        case .decode: return "Could not read the server response"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Point this at the machine running `backend/` (localhost in Simulator).
    var baseURL = URL(string: "http://127.0.0.1:8000")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func events(status: EventStatus? = nil, year: Int? = nil) async throws -> [Event] {
        var items: [URLQueryItem] = []
        if let status { items.append(.init(name: "status", value: status.rawValue)) }
        if let year { items.append(.init(name: "year", value: String(year))) }
        return try await get("/events", query: items)
    }

    func event(id: String) async throws -> Event {
        try await get("/events/\(id)")
    }

    func recap() async throws -> Recap {
        try await get("/recap")
    }

    func createEvent(_ draft: EventDraft) async throws -> Event {
        try await send("/events", method: "POST", body: draft)
    }

    func updateEvent(id: String, show: String, venue: String?, city: String?, startDate: String?, endDate: String?) async throws -> Event {
        struct Patch: Codable {
            var show: String
            var venue: String?
            var city: String?
            var startDate: String?
            var endDate: String?
        }
        return try await send("/events/\(id)", method: "PATCH", body: Patch(show: show, venue: venue, city: city, startDate: startDate, endDate: endDate))
    }

    func logSpend(eventId: String, spend: SpendDraft) async throws -> Event {
        try await send("/events/\(eventId)/spend", method: "PATCH", body: spend)
    }

    func logSet(eventId: String, draft: SetDraft) async throws -> SetEntry {
        try await send("/events/\(eventId)/sets", method: "POST", body: draft)
    }

    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.badURL }
        comps.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        return url
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let url = try makeURL(path, query: query)
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.check(response)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }

    private func send<Body: Encodable, T: Decodable>(_ path: String, method: String, body: Body) async throws -> T {
        let url = try makeURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response)
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
    }
}

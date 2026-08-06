import Foundation

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case paymentRequired(String)
    case rateLimited
    case server(String)
    case decoding
    case offline

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session ended. Sign in again."
        case .paymentRequired(let message): message
        case .rateLimited: "That's a lot of requests. Give it a minute."
        case .server(let message): message
        case .decoding: "The server sent something we couldn't read."
        case .offline: "No connection. Check your network and try again."
        }
    }
}

private struct APIErrorBody: Decodable { let detail: String? }

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var accessToken: String?
    private var refreshToken: String?
    private var refreshTask: Task<Void, Error>?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter.awlcFull.date(from: text) { return date }
            if let date = ISO8601DateFormatter.awlcPlain.date(from: text) { return date }
            if let date = DateFormatter.awlcDay.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(text)")
            )
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.awlcDay)

        accessToken = Keychain.read("access")
        refreshToken = Keychain.read("refresh")
    }

    var isSignedIn: Bool { refreshToken != nil }

    func setTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        Keychain.save(access, for: "access")
        Keychain.save(refresh, for: "refresh")
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        Keychain.delete("access")
        Keychain.delete("refresh")
    }

    func currentRefreshToken() -> String? { refreshToken }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, query: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: "POST", query: query, body: body)
    }

    func post<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: "POST", query: query, body: Optional<Empty>.none)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(path: path, method: "PATCH", query: [:], body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Bool {
        let _: Empty? = try await sendOptional(path: path, method: "DELETE", query: [:], body: Optional<Empty>.none)
        return true
    }

    @discardableResult
    func postVoid<B: Encodable>(_ path: String, body: B) async throws -> Bool {
        let _: Empty? = try await sendOptional(path: path, method: "POST", query: [:], body: body)
        return true
    }

    @discardableResult
    func postVoid(_ path: String, query: [String: String] = [:]) async throws -> Bool {
        let _: Empty? = try await sendOptional(path: path, method: "POST", query: query, body: Optional<Empty>.none)
        return true
    }

    func upload<T: Decodable>(
        _ path: String,
        imageData: Data,
        filename: String = "meal.jpg",
        mime: String = "image/jpeg",
        query: [String: String] = [:]
    ) async throws -> T {
        let boundary = "awlc-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = try makeRequest(path: path, method: "POST", query: query)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request, allowRetry: true)
    }

    // MARK: - Plumbing

    private struct Empty: Codable {}

    private func makeRequest(path: String, method: String, query: [String: String]) throws -> URLRequest {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.server("Bad request URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable, B: Encodable>(
        path: String, method: String, query: [String: String], body: B?
    ) async throws -> T {
        var request = try makeRequest(path: path, method: method, query: query)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request, allowRetry: true)
    }

    private func sendOptional<T: Decodable, B: Encodable>(
        path: String, method: String, query: [String: String], body: B?
    ) async throws -> T? {
        var request = try makeRequest(path: path, method: method, query: query)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let data: Data? = try await performRaw(request, allowRetry: true)
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func perform<T: Decodable>(_ request: URLRequest, allowRetry: Bool) async throws -> T {
        let data = try await performRaw(request, allowRetry: allowRetry) ?? Data()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func performRaw(_ request: URLRequest, allowRetry: Bool) async throws -> Data? {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response.") }

        switch http.statusCode {
        case 200...299:
            return data
        case 401 where allowRetry && refreshToken != nil:
            try await refreshSession()
            var retry = request
            if let accessToken { retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
            return try await performRaw(retry, allowRetry: false)
        case 401:
            clearTokens()
            throw APIError.unauthorized
        case 402:
            throw APIError.paymentRequired(message(from: data) ?? "Premium unlocks this feature.")
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(message(from: data) ?? "Request failed (\(http.statusCode)).")
        }
    }

    private func message(from data: Data) -> String? {
        (try? decoder.decode(APIErrorBody.self, from: data))?.detail
    }

    private func refreshSession() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken else { throw APIError.unauthorized }

        let task = Task<Void, Error> {
            var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                clearTokens()
                throw APIError.unauthorized
            }
            let pair = try decoder.decode(TokenPair.self, from: data)
            setTokens(access: pair.accessToken, refresh: pair.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }
}

extension ISO8601DateFormatter {
    static let awlcFull: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let awlcPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension DateFormatter {
    static let awlcDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

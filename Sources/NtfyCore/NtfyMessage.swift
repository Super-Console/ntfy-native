import Foundation

/// A single JSON event from ntfy's `/topic/json` streaming endpoint.
public struct NtfyMessage: Decodable, Identifiable, Sendable {
    public let id: String
    public let time: Int64?
    public let event: String?
    public let topic: String?
    public let title: String?
    public let message: String?
    public let priority: Int?
    public let tags: [String]?
    public let click: String?

    public var isNotification: Bool { event == nil || event == "message" }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(time ?? 0)) }
}

public enum NtfyURL {
    public static func stream(server: String, topic: String) throws -> URL {
        guard var components = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let safeTopic = topic.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        components.path = "/" + [basePath, safeTopic, "json"].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url, ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        return url
    }

    public static func publish(server: String, topic: String) throws -> URL {
        guard var components = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let safeTopic = topic.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        components.path = "/" + [basePath, safeTopic].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url, ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        return url
    }
}

public enum NtfyClientError: Error, Sendable {
    case httpStatus(Int)
    case invalidResponse
}

/// Shared publish path used by the app and the live integration smoke test.
public enum NtfyPublisher {
    @discardableResult
    public static func publish(
        server: String,
        topic: String,
        title: String,
        message: String,
        token: String = "",
        session: URLSession = .shared
    ) async throws -> NtfyMessage {
        var request = URLRequest(url: try NtfyURL.publish(server: server, topic: topic))
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = message.data(using: .utf8)
        if !title.isEmpty { request.setValue(title, forHTTPHeaderField: "Title") }
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NtfyClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw NtfyClientError.httpStatus(response.statusCode) }
        return try JSONDecoder().decode(NtfyMessage.self, from: data)
    }
}

import Foundation
import NtfyCore

@main
enum NtfyLiveSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let server = arguments.first ?? "https://ntfy.sh"
        let topic = arguments.count > 1
            ? arguments[1]
            : "ntfy-native-verify-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let marker = "live-roundtrip-\(UUID().uuidString.lowercased())"
        let title = "ntfy-native live verification"

        var request = URLRequest(url: try NtfyURL.stream(server: server, topic: topic))
        request.setValue("application/stream+json", forHTTPHeaderField: "Accept")
        let receiver = Task.detached { () throws -> NtfyMessage in
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw NtfyClientError.invalidResponse
            }
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8),
                      let event = try? JSONDecoder().decode(NtfyMessage.self, from: data) else { continue }
                if event.isNotification && event.message == marker { return event }
            }
            throw URLError(.networkConnectionLost)
        }

        try await Task.sleep(for: .seconds(2))
        let sent = try await NtfyPublisher.publish(server: server, topic: topic, title: title, message: marker)
        let received = try await withThrowingTaskGroup(of: NtfyMessage.self) { group in
            group.addTask { try await receiver.value }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else { throw URLError(.unknown) }
            group.cancelAll()
            return first
        }

        guard sent.id == received.id,
              received.topic == topic,
              received.title == title,
              received.message == marker else {
            throw NtfyClientError.invalidResponse
        }
        print("PASS ntfy server round-trip: topic=\(topic), event=\(received.id), title/body match")
    }
}

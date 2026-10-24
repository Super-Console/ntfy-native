import XCTest
@testable import NtfyCore

final class NtfyURLTests: XCTestCase {
    func testDefaultStreamURL() throws {
        XCTAssertEqual(try NtfyURL.stream(server: "https://ntfy.sh", topic: "alerts").absoluteString, "https://ntfy.sh/alerts/json")
    }

    func testSelfHostedBasePathIsPreserved() throws {
        XCTAssertEqual(try NtfyURL.stream(server: "https://example.test/ntfy/", topic: "my-topic").absoluteString, "https://example.test/ntfy/my-topic/json")
    }

    func testRejectsNonHTTPURL() {
        XCTAssertThrowsError(try NtfyURL.stream(server: "file:///tmp", topic: "topic"))
    }

    func testDecodesNtfyMessageEvent() throws {
        let payload = #"{"id":"abc123","time":1700000000,"event":"message","topic":"alerts","title":"Build","message":"Finished","priority":4,"tags":["white_check_mark"]}"#.data(using: .utf8)!
        let message = try JSONDecoder().decode(NtfyMessage.self, from: payload)
        XCTAssertTrue(message.isNotification)
        XCTAssertEqual(message.id, "abc123")
        XCTAssertEqual(message.title, "Build")
        XCTAssertEqual(message.message, "Finished")
        XCTAssertEqual(message.priority, 4)
        XCTAssertEqual(message.tags, ["white_check_mark"])
    }

    func testIgnoresKeepaliveEvents() throws {
        let payload = #"{"id":"keepalive","event":"keepalive"}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(NtfyMessage.self, from: payload).isNotification)
    }
}

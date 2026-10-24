import ServiceManagement
import XCTest
@testable import NtfyCore

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testFreshInstallationCanRegisterFromNotFound() {
        let service = FakeLoginItemService(status: .notFound)
        let controller = LaunchAtLoginController(service: service, isAppBundle: true)
        XCTAssertTrue(controller.isAvailable)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.notice, "")
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.notice, "")
    }

    func testApprovalDoesNotPretendRegistrationFailedOrRegisterAgain() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service, isAppBundle: true)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.notice.isEmpty)
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testDisableUsesUnregisterAndReadsBackStatus() {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LaunchAtLoginController(service: service, isAppBundle: true)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.notice, "")
    }

    func testFailedRegistrationDoesNotTurnOnToggle() {
        let service = FakeLoginItemService(status: .notFound)
        service.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: 22)
        let controller = LaunchAtLoginController(service: service, isAppBundle: true)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.notice.contains("SMAppServiceErrorDomain 22"))
    }

    func testUnconfirmedRegistrationDoesNotClaimEnabled() {
        let service = FakeLoginItemService(status: .notFound)
        service.registeredStatus = .notFound
        let controller = LaunchAtLoginController(service: service, isAppBundle: true)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.notice.isEmpty)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var registeredStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var registerCalls = 0
    var unregisterCalls = 0

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        status = registeredStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .notRegistered
    }
}

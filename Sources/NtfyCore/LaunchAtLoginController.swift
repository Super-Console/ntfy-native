import Combine
import Foundation
import ServiceManagement
import os

@MainActor
public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
public final class LaunchAtLoginController: ObservableObject {
    @Published public private(set) var isEnabled = false
    @Published public private(set) var notice = ""
    @Published public private(set) var isAvailable: Bool

    private let service: any LoginItemService
    private let logger = Logger(subsystem: "com.timmy.ntfy-native", category: "login-item")

    public init(service: any LoginItemService = SMAppService.mainApp, isAppBundle: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.service = service
        self.isAvailable = isAppBundle
        refresh()
    }

    public func refresh() {
        let status = service.status
        isEnabled = status == .enabled || status == .requiresApproval
        logger.info("login service status=\(status.rawValue, privacy: .public)")
        if !isAvailable {
            notice = NSLocalizedString("login.notice.unavailable", bundle: .module, comment: "")
        } else if status == .requiresApproval {
            notice = NSLocalizedString("login.notice.approval", bundle: .module, comment: "")
        } else {
            notice = ""
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                // A fresh installation can report .notFound until its first registration.
                // Do not interpret that as a signing error or prevent register().
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refresh()
            if enabled && !isEnabled {
                notice = NSLocalizedString("login.notice.unconfirmed", bundle: .module, comment: "")
            }
        } catch {
            refresh()
            let error = error as NSError
            logger.error("login item change failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            let format = NSLocalizedString("login.notice.failed", bundle: .module, comment: "")
            notice = String(format: format, locale: Locale.current, arguments: [error.domain, error.code])
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

import AppKit
import SwiftUI
import UserNotifications
import NtfyCore
import os

private let networkLogger = Logger(subsystem: "com.timmy.ntfy-native", category: "network")

@main
enum NtfyNativeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = NtfyApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
struct NtfySubscription: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var topic: String = ""
    var note: String = ""
}

@MainActor
final class NtfyModel: ObservableObject {
    @Published var server = UserDefaults.standard.string(forKey: "server") ?? "https://ntfy.sh"
    @Published var subscriptions: [NtfySubscription] = [] {
        didSet { persistSubscriptions() }
    }
    @Published var token = SecretStore.read()
    @Published var messages: [NtfyMessage] = []
    @Published var status = AppStrings.text("status.disconnected")
    @Published var isConnected = false
    @Published var draftTitle = ""
    @Published var draftMessage = ""
    @Published var notificationStatus = AppStrings.text("status.checkingNotifications")

    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var activeConnectionIDs: Set<UUID> = []
    private var connectedIDs: Set<UUID> = []
    private var connectionGeneration = UUID()
    private var seenMessageIDs = Set<String>()
    private var seenMessageOrder: [String] = []
    private let session = URLSession(configuration: .ephemeral)

    init() {
        if let data = UserDefaults.standard.data(forKey: "subscriptions"),
           let saved = try? JSONDecoder().decode([NtfySubscription].self, from: data) {
            subscriptions = saved
        } else {
            let legacyTopic = UserDefaults.standard.string(forKey: "topic") ?? ""
            subscriptions = legacyTopic.isEmpty ? [] : [NtfySubscription(topic: legacyTopic)]
        }
        if !subscriptions.isEmpty {
            requestNotificationAuthorizationIfNeeded()
        }
        if !subscriptions.isEmpty {
            Task { @MainActor [weak self] in self?.connectAll() }
        }
    }

    var publishingTopic: String {
        subscriptions.first(where: { !$0.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.topic ?? ""
    }

    func saveAndConnect() {
        UserDefaults.standard.set(server, forKey: "server")
        UserDefaults.standard.set(publishingTopic, forKey: "topic")
        let status = SecretStore.write(token)
        guard status == errSecSuccess else {
            self.status = AppStrings.format("status.keychainSaveFailed", status)
            return
        }
        requestNotificationAuthorizationIfNeeded()
        connectAll()
    }

    private func persistSubscriptions() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        UserDefaults.standard.set(data, forKey: "subscriptions")
        UserDefaults.standard.set(publishingTopic, forKey: "topic")
    }

    func addSubscription() { subscriptions.append(NtfySubscription()) }

    func removeSubscription(_ id: UUID) {
        subscriptions.removeAll { $0.id == id }
        streamTasks[id]?.cancel()
        streamTasks[id] = nil
        activeConnectionIDs.remove(id)
        connectedIDs.remove(id)
        isConnected = !connectedIDs.isEmpty
    }

    private func requestNotificationAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            updateNotificationStatus(settings.authorizationStatus)
            networkLogger.info("notification authorization status=\(settings.authorizationStatus.rawValue, privacy: .public)")
            guard settings.authorizationStatus == .notDetermined else { return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                networkLogger.info("notification authorization granted=\(granted, privacy: .public)")
                updateNotificationStatus((await center.notificationSettings()).authorizationStatus)
            } catch {
                networkLogger.error("notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func refreshNotificationStatus() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            updateNotificationStatus(status)
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.timmy.ntfy-native") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateNotificationStatus(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: notificationStatus = AppStrings.text("notification.notDetermined")
        case .denied: notificationStatus = AppStrings.text("notification.denied")
        case .authorized: notificationStatus = AppStrings.text("notification.allowed")
        case .provisional: notificationStatus = AppStrings.text("notification.provisional")
        @unknown default: notificationStatus = AppStrings.text("notification.unknown")
        }
    }

    func connectAll() {
        connectionGeneration = UUID()
        streamTasks.values.forEach { $0.cancel() }
        streamTasks.removeAll()
        activeConnectionIDs.removeAll()
        connectedIDs.removeAll()
        let configured = subscriptions.filter { !$0.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !configured.isEmpty else {
            status = AppStrings.text("status.topicRequired")
            isConnected = false
            return
        }
        status = AppStrings.text("status.connecting")
        isConnected = false
        for subscription in configured { connect(subscription) }
    }

    private func connect(_ subscription: NtfySubscription) {
        let connectionID = subscription.id
        let generation = connectionGeneration
        activeConnectionIDs.insert(connectionID)
        streamTasks[connectionID] = Task {
            var retry = 0
            while !Task.isCancelled {
                do {
                    let url = try NtfyURL.stream(server: server, topic: subscription.topic)
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 90
                    request.setValue("application/stream+json", forHTTPHeaderField: "Accept")
                    if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard (200..<300).contains(response.statusCode) else { throw NtfyClientError.httpStatus(response.statusCode) }
                    guard activeConnectionIDs.contains(connectionID), connectionGeneration == generation else { break }
                    connectedIDs.insert(connectionID)
                    isConnected = true
                    status = AppStrings.format("status.connectedCount", connectedIDs.count)
                    let connectedAt = Date()
                    networkLogger.info("stream connected (retry attempt \(retry, privacy: .public))")
                    for try await line in bytes.lines {
                        guard !Task.isCancelled, activeConnectionIDs.contains(connectionID), connectionGeneration == generation,
                              let data = line.data(using: .utf8),
                              let message = try? JSONDecoder().decode(NtfyMessage.self, from: data) else { continue }
                        if message.isNotification && acceptMessageID(message.id) {
                            messages.insert(message, at: 0)
                            messages = Array(messages.prefix(50))
                            notify(message)
                            networkLogger.info("message received and notification queued")
                        }
                    }
                    guard activeConnectionIDs.contains(connectionID), connectionGeneration == generation else { break }
                    if Date().timeIntervalSince(connectedAt) >= 30 { retry = 0 }
                    networkLogger.notice("stream ended; reconnecting")
                    throw URLError(.networkConnectionLost)
                } catch {
                    guard activeConnectionIDs.contains(connectionID), connectionGeneration == generation else { break }
                    connectedIDs.remove(connectionID)
                    isConnected = !connectedIDs.isEmpty
                    guard !Task.isCancelled else { break }
                    if case let NtfyClientError.httpStatus(code) = error, (400..<500).contains(code) {
                        status = code == 401 || code == 403
                            ? AppStrings.format("status.accessDenied", code)
                            : AppStrings.format("status.httpError", code)
                        break
                    }
                    if (error as? URLError)?.code == .badURL {
                        status = AppStrings.text("status.invalidServer")
                        break
                    }
                    status = retry == 0
                        ? AppStrings.text("status.reconnecting")
                        : AppStrings.format("status.retry", min(30, 1 << min(retry, 5)))
                    try? await Task.sleep(for: .seconds(min(30, 1 << min(retry, 5))))
                    retry += 1
                }
            }
            if connectionGeneration == generation {
                activeConnectionIDs.remove(connectionID)
                connectedIDs.remove(connectionID)
                isConnected = !connectedIDs.isEmpty
            }
        }
    }

    func disconnect() {
        activeConnectionIDs.removeAll()
        connectedIDs.removeAll()
        streamTasks.values.forEach { $0.cancel() }
        streamTasks.removeAll()
        isConnected = false
        status = AppStrings.text("status.disconnectedShort")
    }

    private func acceptMessageID(_ id: String) -> Bool {
        guard seenMessageIDs.insert(id).inserted else { return false }
        seenMessageOrder.append(id)
        if seenMessageOrder.count > 500 {
            seenMessageIDs.remove(seenMessageOrder.removeFirst())
        }
        return true
    }

    func publish() async {
        let topic = publishingTopic
        guard !topic.isEmpty else { status = AppStrings.text("status.topicRequired"); return }
        do {
            try await NtfyPublisher.publish(server: server, topic: topic, title: draftTitle,
                                            message: draftMessage, token: token, session: session)
            draftMessage = ""
            status = AppStrings.text("status.published")
        } catch {
            if case let NtfyClientError.httpStatus(code) = error {
                status = AppStrings.format("status.publishHTTPError", code)
            } else {
                status = AppStrings.format("status.publishError", error.localizedDescription)
            }
        }
    }

    private func notify(_ message: NtfyMessage) {
        let content = UNMutableNotificationContent()
        content.title = message.title?.isEmpty == false ? message.title! : note(for: message.topic) ?? "ntfy"
        content.body = message.message ?? AppStrings.text("notification.newMessage")
        content.sound = .default
        if let click = message.click { content.userInfo["click"] = click }
        let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                try await center.add(request)
                try await Task.sleep(for: .seconds(1))
                let delivered = await withCheckedContinuation { continuation in
                    center.getDeliveredNotifications { notifications in
                        continuation.resume(returning: notifications.contains { $0.request.identifier == message.id })
                    }
                }
                networkLogger.info("notification delivered_to_center=\(delivered, privacy: .public)")
            } catch {
                networkLogger.error("notification scheduling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func note(for topic: String?) -> String? {
        guard let topic else { return nil }
        return subscriptions.first(where: { $0.topic == topic })?.note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
final class NtfyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NtfyNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["click"] as? String,
              let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false,
              let url = components.url else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }
}

struct MenuContent: View {
    @ObservedObject var model: NtfyModel
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(model.isConnected ? .green : .secondary).frame(width: 8, height: 8)
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(action: showSettings) {
                    Image(systemName: "gearshape").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.text("accessibility.settings"))
                .help(AppStrings.text("accessibility.settings"))
                .keyboardShortcut(",", modifiers: .command)
            }
            Divider()
            if model.messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                    Text(AppStrings.text("empty.title")).font(.headline)
                    Text(AppStrings.text("empty.description"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(message.title?.isEmpty == false ? message.title! : model.note(for: message.topic) ?? "ntfy")
                                        .font(.headline).lineLimit(1)
                                    Spacer()
                                    Text(message.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(message.message ?? "").font(.callout).textSelection(.enabled).lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }.frame(height: 240)
            }
            HStack {
                Button(model.isConnected ? AppStrings.text("button.disconnect") : AppStrings.text("button.connect")) { model.isConnected ? model.disconnect() : model.saveAndConnect() }
                    .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button(AppStrings.text("menu.quit")) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

struct SettingsView: View {
    @ObservedObject var model: NtfyModel
    @ObservedObject var loginItem: LaunchAtLoginController
    let dismiss: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, token, title, message }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.text("settings.title")).font(.title2.weight(.semibold))
            Text(AppStrings.text("settings.connection")).font(.headline)
            TextField(AppStrings.text("settings.server"), text: $model.server).textFieldStyle(.roundedBorder)
                .help(AppStrings.text("settings.server.help"))
                .focused($focusedField, equals: .server)
                .accessibilityLabel(AppStrings.text("settings.server"))
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.text("settings.subscriptions")).font(.headline)
                Text(AppStrings.text("settings.subscriptionPrivacy"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($model.subscriptions) { $subscription in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField(AppStrings.text("settings.topic"), text: $subscription.topic)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(AppStrings.text("settings.topic"))
                            Button(role: .destructive) { model.removeSubscription(subscription.id) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppStrings.text("button.removeSubscription"))
                        }
                        TextField(AppStrings.text("settings.note"), text: $subscription.note)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(AppStrings.text("settings.note"))
                    }
                }
                Button { model.addSubscription() } label: {
                    Label(AppStrings.text("button.addSubscription"), systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            SecureField(AppStrings.text("settings.bearerToken"), text: $model.token).textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .token)
            Text(AppStrings.text("settings.tokenHelp"))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text(AppStrings.text("settings.publish")).font(.headline)
                Text(AppStrings.text("settings.publishTargetPrivacy"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TextField(AppStrings.text("settings.titleOptional"), text: $model.draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppStrings.text("settings.message"), text: $model.draftMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .message)
                        .onSubmit { Task { await model.publish() } }
                    Button(AppStrings.text("button.publish")) { Task { await model.publish() } }
                        .disabled(model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.publishingTopic.isEmpty)
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.text("settings.systemNotifications")).font(.callout)
                    Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppStrings.text("button.notificationSettings")) { model.openNotificationSettings() }.font(.caption)
            }
            if loginItem.isAvailable {
                Toggle(AppStrings.text("settings.launchAtLogin"), isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .accessibilityLabel(AppStrings.text("settings.launchAtLogin"))
                .accessibilityIdentifier("launch-at-login")
                .frame(minHeight: 28)
            }
            if !loginItem.notice.isEmpty {
                HStack {
                    Text(loginItem.notice).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(AppStrings.text("button.openLoginItems")) { loginItem.openSystemSettings() }
                        .controlSize(.small)
                }
            }
            HStack {
                Button(AppStrings.text("button.back"), action: dismiss)
                Spacer()
                Button(AppStrings.text("button.saveAndConnect")) { model.saveAndConnect(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            focusedField = nil
            loginItem.refresh()
            model.refreshNotificationStatus()
        }
    }
}

enum NtfyMenuBarSymbol {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let bubble = NSBezierPath()
        bubble.move(to: NSPoint(x: 6.4, y: 4.0))
        bubble.line(to: NSPoint(x: 4.2, y: 2.5))
        bubble.line(to: NSPoint(x: 4.9, y: 5.0))
        bubble.curve(to: NSPoint(x: 2.9, y: 7.1), controlPoint1: NSPoint(x: 4.0, y: 5.7), controlPoint2: NSPoint(x: 2.9, y: 6.0))
        bubble.line(to: NSPoint(x: 2.9, y: 11.0))
        bubble.curve(to: NSPoint(x: 5.4, y: 13.5), controlPoint1: NSPoint(x: 2.9, y: 12.4), controlPoint2: NSPoint(x: 4.0, y: 13.5))
        bubble.line(to: NSPoint(x: 12.6, y: 13.5))
        bubble.curve(to: NSPoint(x: 15.1, y: 11.0), controlPoint1: NSPoint(x: 14.0, y: 13.5), controlPoint2: NSPoint(x: 15.1, y: 12.4))
        bubble.line(to: NSPoint(x: 15.1, y: 6.7))
        bubble.curve(to: NSPoint(x: 12.6, y: 4.2), controlPoint1: NSPoint(x: 15.1, y: 5.3), controlPoint2: NSPoint(x: 14.0, y: 4.2))
        bubble.close()

        let prompt = NSBezierPath()
        prompt.move(to: NSPoint(x: 6.0, y: 10.8))
        prompt.line(to: NSPoint(x: 8.0, y: 9.0))
        prompt.line(to: NSPoint(x: 6.0, y: 7.2))
        prompt.move(to: NSPoint(x: 9.3, y: 7.2))
        prompt.line(to: NSPoint(x: 12.0, y: 7.2))

        NSColor.black.setStroke()
        bubble.lineWidth = 1.35
        bubble.lineCapStyle = .round
        bubble.lineJoinStyle = .round
        bubble.stroke()
        prompt.lineWidth = 1.25
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

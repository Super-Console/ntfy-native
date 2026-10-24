import AppKit
import Combine
import NtfyCore
import SwiftUI
import UserNotifications

@MainActor
final class NtfyApplicationDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NtfyNotificationDelegate.shared
        if CommandLine.arguments.contains("--test-notification") {
            // One-shot local packaging smoke test: no topic, token, subscription,
            // notification history removal, or network request is involved.
            Task { @MainActor in
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .authorized else {
                    NSApp.terminate(nil)
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = AppStrings.text("testNotification.title")
                content.body = AppStrings.text("testNotification.body")
                do {
                    try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                    try? await Task.sleep(for: .seconds(3))
                } catch {
                    NSLog("Local notification test failed: %@", error.localizedDescription)
                }
                NSApp.terminate(nil)
            }
            return
        }
        menuController = MenuPanelController(model: NtfyModel())
        installApplicationMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "ntfy")
        let settingsItem = NSMenuItem(title: AppStrings.text("menu.settings"), action: #selector(MenuPanelController.openSettings), keyEquivalent: ",")
        settingsItem.target = menuController
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: AppStrings.text("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: AppStrings.text("menu.edit"))
        editMenu.addItem(withTitle: AppStrings.text("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: AppStrings.text("menu.redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: AppStrings.text("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: AppStrings.text("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: AppStrings.text("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: AppStrings.text("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}

@MainActor
final class MenuPanelController: NSObject, NSWindowDelegate {
    private let model: NtfyModel
    private let loginItem = LaunchAtLoginController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = MenuPanel()
    private var hostingView: NSHostingView<AnyView>?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var messageObservation: AnyCancellable?
    private var loginObservation: AnyCancellable?
    private var showingSettings = false

    init(model: NtfyModel) {
        self.model = model
        super.init()
        if let button = statusItem.button {
            button.image = NtfyMenuBarSymbol.image
            button.imagePosition = .imageOnly
            button.toolTip = "ntfy"
            button.setAccessibilityLabel("ntfy")
            button.target = self
            button.action = #selector(togglePanel)
        }
        panel.delegate = self
        installContent()
        messageObservation = model.$messages.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.showingSettings else { return }
                self.resizeAndPosition()
            }
        }
        loginObservation = loginItem.$notice.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.showingSettings else { return }
                self.resizeAndPosition()
            }
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            presentPanel()
        }
    }

    @objc func openSettings() {
        showSettings(true)
        presentPanel()
    }

    private func presentPanel() {
        loginItem.refresh()
        resizeAndPosition()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        statusItem.button?.highlight(true)
        startMonitoringOutsideClicks()
    }

    private func showSettings(_ show: Bool) {
        showingSettings = show
        loginItem.refresh()
        installContent()
        resizeAndPosition()
        panel.makeFirstResponder(nil)
    }

    private func installContent() {
        let root: AnyView
        if showingSettings {
            root = AnyView(SettingsView(model: model, loginItem: loginItem) { [weak self] in self?.showSettings(false) })
        } else {
            root = AnyView(MenuContent(model: model) { [weak self] in self?.showSettings(true) })
        }
        let host = TransparentHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        host.setAccessibilityIdentifier(showingSettings ? "ntfy-settings" : "ntfy-messages")
        hostingView = host
        panel.title = showingSettings ? AppStrings.text("panel.settingsTitle") : AppStrings.text("panel.messagesTitle")

        // One native material owns the entire surface. No MenuBarExtra backing
        // material, sheet fill, or second SwiftUI glass layer underneath it.
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = MenuPanel.cornerRadius
            glass.contentView = host
            surface = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.addSubview(host)
            surface = material
        }
        surface.wantsLayer = true
        surface.layer?.cornerRadius = MenuPanel.cornerRadius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = surface
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            host.topAnchor.constraint(equalTo: surface.topAnchor),
            host.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
    }

    private func resizeAndPosition() {
        guard let host = hostingView, let button = statusItem.button,
              let buttonWindow = button.window else { return }
        host.invalidateIntrinsicContentSize()
        let fittingSize = host.fittingSize
        let size = NSSize(width: showingSettings ? 400 : 360, height: ceil(fittingSize.height))
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = max(visible.minY + 8, anchor.minY - size.height - 6)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: panel.isVisible)
    }

    private func startMonitoringOutsideClicks() {
        guard localClickMonitor == nil else { return }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                self.hidePanel()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    func windowDidBecomeKey(_ notification: Notification) { loginItem.refresh() }
}

private final class TransparentHostingView: NSHostingView<AnyView> {
    override var isOpaque: Bool { false }
}

private final class MenuPanel: NSPanel {
    static let cornerRadius: CGFloat = 22

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? MenuPanelController)?.hidePanel()
    }
}

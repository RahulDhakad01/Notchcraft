import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    private var overlayController: OverlayWindowController?
    private let appState = AppState()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var launchAtLoginItem: NSMenuItem?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        applyBranding()
        overlayController = OverlayWindowController(appState: appState)
        overlayController?.showWindow(nil)

        setupStatusItem()
        installLifecycleObservers()
        installEscapeMonitor()
        appState.refreshLaunchAtLoginStatus()
        refreshStatusMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.markCleanShutdown()
        removeLifecycleObservers()
        removeEscapeMonitor()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusItemImage()
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "NotchCraft"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Open Notch", action: #selector(openNotch), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Reset UI", action: #selector(resetUI), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Restart App", action: #selector(restartApp), keyEquivalent: ""))
        menu.addItem(.separator())
        let launchItem = NSMenuItem(title: "Launch on Startup", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchCraft", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
        statusMenu = menu
        launchAtLoginItem = launchItem
    }

    private func applyBranding() {
        guard let brandImage = loadDockBrandImage() else { return }
        NSApp.applicationIconImage = brandImage
    }

    private func makeStatusItemImage() -> NSImage? {
        if let brandImage = loadMenuBarBrandImage()?.copy() as? NSImage {
            brandImage.size = NSSize(width: 18, height: 18)
            brandImage.isTemplate = false
            return brandImage
        }

        return NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: "NotchCraft")
    }

    private func loadDockBrandImage() -> NSImage? {
        if let image = loadImage(named: "AppIcon", extension: "icns") {
            return image
        }

        return loadImage(named: "AppIcon", extension: "png")
    }

    private func loadMenuBarBrandImage() -> NSImage? {
        loadImage(named: "navbar", extension: "png") ?? loadDockBrandImage()
    }

    private func loadImage(named name: String, extension fileExtension: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default

        lifecycleObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.appState.handleSystemWillSleep()
                }
            }
        )

        lifecycleObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.appState.handleSystemDidWake()
                    self?.overlayController?.refreshFrame(animated: false, forceCenter: true)
                }
            }
        )

        lifecycleObservers.append(
            defaultCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.appState.handleAppDidBecomeActive()
                }
            }
        )

        lifecycleObservers.append(
            defaultCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.appState.handleAppDidResignActive()
                }
            }
        )

        lifecycleObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else {
                    return
                }

                Task { @MainActor in
                    self?.appState.recordActivatedApplication(application)
                }
            }
        )

        lifecycleObservers.append(
            defaultCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.appState.handleScreenConfigurationChange()
                    self?.overlayController?.refreshFrame(animated: false, forceCenter: true)
                }
            }
        )
    }

    private func removeLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default

        lifecycleObservers.forEach {
            workspaceCenter.removeObserver($0)
            defaultCenter.removeObserver($0)
        }
        lifecycleObservers.removeAll()
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self, self.appState.isExpanded else { return event }

            self.appState.closeOverlay(reason: "Notch closed.")
            self.overlayController?.refreshFrame(animated: true)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    private func refreshStatusMenuState() {
        appState.refreshLaunchAtLoginStatus()
        launchAtLoginItem?.state = appState.launchAtLoginEnabled ? .on : .off
        launchAtLoginItem?.isEnabled = appState.launchAtLoginAvailable
        launchAtLoginItem?.toolTip = appState.launchAtLoginHelperText
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenuState()
    }

    @objc private func openNotch() {
        overlayController?.openOverlay()
    }

    @objc private func resetUI() {
        overlayController?.resetOverlayUI()
        refreshStatusMenuState()
    }

    @objc private func restartApp() {
        relaunchCurrentProcess()
    }

    @objc private func toggleLaunchAtLogin() {
        appState.setLaunchAtLoginEnabled(!appState.launchAtLoginEnabled)
        refreshStatusMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func relaunchCurrentProcess() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        } else if let executablePath = ProcessInfo.processInfo.arguments.first {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
            try? process.run()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

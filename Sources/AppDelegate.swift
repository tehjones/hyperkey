import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isAccessibilityTrusted = false
    private var isActive = false
    private var hasRequestedAccessibility = false
    private var isRelaunchPending = false
    private var isRelaunching = false

    private var keyHandler: KeyHandler?
    private var permissionTimer: Timer?
    private var relaunchWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem!
    private var setupWindowController: SetupWindowController?
    private var appActivationObserver: NSObjectProtocol?
    private var appDeactivationObserver: NSObjectProtocol?
    private var didObserveSystemSettings = false

    private static let relaunchGuardKey = "didRelaunchForAccessibilityActivation"

    private static let legacyLaunchAgentPath: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sergey.hyperkey"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(bundleID).plist"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        migrateLegacyLaunchAgent()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        isAccessibilityTrusted = AXIsProcessTrusted()
        updateInterface()
        startSystemSettingsObservers()

        Diagnostics.permission("startup \(runtimeSummary) trusted=\(isAccessibilityTrusted)")

        if isAccessibilityTrusted {
            activate()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showSetup()
            }
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        relaunchWorkItem?.cancel()
        keyHandler?.stop()

        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let appDeactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appDeactivationObserver)
        }

        // We intentionally do not reset the hidutil mapping on quit. Resetting
        // would wipe unrelated mappings, and macOS clears this mapping on reboot.
    }

    private func activate() {
        guard isAccessibilityTrusted else {
            deactivate()
            return
        }

        keyHandler?.stop()
        keyHandler = KeyHandler()
        keyHandler?.start()

        if keyHandler?.isRunning == true {
            HIDUtil.remapCapsLockToF19()
            isActive = true
            isRelaunchPending = false
            UserDefaults.standard.set(false, forKey: Self.relaunchGuardKey)
            Diagnostics.permission("activation-succeeded \(runtimeSummary)")
        } else {
            keyHandler = nil
            isActive = false
            Diagnostics.permission("activation-failed \(runtimeSummary)")
        }

        updateInterface()
    }

    private func deactivate() {
        keyHandler?.stop()
        keyHandler = nil
        isActive = false
        updateInterface()
    }

    private func refreshPermissionState() {
        let wasTrusted = isAccessibilityTrusted
        isAccessibilityTrusted = AXIsProcessTrusted()

        if !isAccessibilityTrusted {
            if isActive {
                deactivate()
            } else if wasTrusted != isAccessibilityTrusted {
                updateInterface()
            }
            return
        }

        guard !wasTrusted else {
            return
        }

        Diagnostics.permission("permission-granted \(runtimeSummary)")
        activate()

        if !isActive {
            if didObserveSystemSettings || Self.isSystemSettingsFrontmost {
                isRelaunchPending = true
                updateInterface()
            } else {
                scheduleRelaunch(after: 0.5)
            }
        }
    }

    private func updateInterface() {
        updateIcon()
        rebuildMenu()
        setupWindowController?.update(view: makeSetupView())
    }

    private func updateIcon() {
        let image = Bundle.main.image(forResource: NSImage.Name("hyperkey-menu-bar-iconTemplate"))
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "HyperKey")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true

        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("HyperKey")
        statusItem.button?.toolTip = statusText
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if isActive {
            let activeItem = NSMenuItem(title: "HyperKey Active", action: nil, keyEquivalent: "")
            activeItem.state = .on
            activeItem.isEnabled = false
            menu.addItem(activeItem)
        } else if !isAccessibilityTrusted {
            let setupItem = NSMenuItem(
                title: hasRequestedAccessibility ? "Finish Setting Up HyperKey…" : "Set Up HyperKey…",
                action: #selector(showSetup),
                keyEquivalent: ""
            )
            setupItem.target = self
            menu.addItem(setupItem)
        } else if isRelaunchPending || isRelaunching {
            let finishingItem = NSMenuItem(title: "Finishing Setup…", action: nil, keyEquivalent: "")
            finishingItem.isEnabled = false
            menu.addItem(finishingItem)
        } else {
            let failedItem = NSMenuItem(title: "HyperKey Isn’t Active", action: nil, keyEquivalent: "")
            failedItem.isEnabled = false
            menu.addItem(failedItem)

            let retryItem = NSMenuItem(
                title: "Try Again",
                action: #selector(retryActivation),
                keyEquivalent: ""
            )
            retryItem.target = self
            menu.addItem(retryItem)
        }

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About HyperKey",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private var statusText: String {
        if isActive {
            return "HyperKey is active"
        }
        if !isAccessibilityTrusted {
            return "HyperKey needs Accessibility permission"
        }
        if isRelaunchPending || isRelaunching {
            return "HyperKey is finishing setup"
        }
        return "HyperKey isn’t active"
    }

    @objc private func showSetup() {
        let view = makeSetupView()
        if let setupWindowController {
            setupWindowController.update(view: view)
        } else {
            setupWindowController = SetupWindowController(view: view)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        setupWindowController?.present()
    }

    private func closeSetup() {
        setupWindowController?.close()
    }

    private func makeSetupView() -> SetupView {
        SetupView(
            isAccessibilityTrusted: isAccessibilityTrusted,
            isActive: isActive,
            hasRequestedAccessibility: hasRequestedAccessibility,
            isFinishingSetup: isRelaunchPending || isRelaunching,
            onRequestAccessibility: { [weak self] in
                self?.requestAccessibilityPermission()
            },
            onOpenSettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            onRetry: { [weak self] in
                self?.retryActivation()
            },
            onClose: { [weak self] in
                self?.closeSetup()
            }
        )
    }

    private func requestAccessibilityPermission() {
        hasRequestedAccessibility = true
        isRelaunchPending = false
        UserDefaults.standard.set(false, forKey: Self.relaunchGuardKey)
        updateInterface()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        Diagnostics.permission("permission-requested \(runtimeSummary) trusted=\(isAccessibilityTrusted)")

        if isAccessibilityTrusted {
            activate()
        } else {
            updateInterface()
        }
    }

    private func openAccessibilitySettings() {
        hasRequestedAccessibility = true
        UserDefaults.standard.set(false, forKey: Self.relaunchGuardKey)
        updateInterface()

        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        Diagnostics.permission("settings-opened \(runtimeSummary)")
        NSWorkspace.shared.open(url)
    }

    @objc private func retryActivation() {
        guard isAccessibilityTrusted else {
            showSetup()
            return
        }

        UserDefaults.standard.set(false, forKey: Self.relaunchGuardKey)
        isRelaunchPending = false
        activate()
        if !isActive {
            scheduleRelaunch(after: 0.5)
        }
    }

    private func scheduleRelaunch(after delay: TimeInterval) {
        guard isAppBundleRuntime,
              !isRelaunching,
              !UserDefaults.standard.bool(forKey: Self.relaunchGuardKey)
        else {
            isRelaunchPending = false
            updateInterface()
            return
        }

        relaunchWorkItem?.cancel()
        isRelaunchPending = true
        updateInterface()

        let work = DispatchWorkItem { [weak self] in
            self?.relaunchExactBundle()
        }
        relaunchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func relaunchExactBundle() {
        relaunchWorkItem = nil
        guard isAppBundleRuntime, !isRelaunching else {
            return
        }

        UserDefaults.standard.set(true, forKey: Self.relaunchGuardKey)
        isRelaunchPending = false
        isRelaunching = true
        updateInterface()
        Diagnostics.permission("relaunch-attempt bundleURL=\(Bundle.main.bundleURL.path)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    Diagnostics.permission("relaunch-failed error=\(error)")
                    self.isRelaunching = false
                    self.updateInterface()
                    return
                }

                Diagnostics.permission("relaunch-succeeded newPID=\(app?.processIdentifier ?? -1)")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var isAppBundleRuntime: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func startSystemSettingsObservers() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                Self.isSystemSettings(app)
            else {
                return
            }

            self?.didObserveSystemSettings = true
            self?.updateInterface()
            Diagnostics.permission("settings-activated")
        }

        appDeactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  Self.isSystemSettings(app),
                  didObserveSystemSettings
            else {
                return
            }

            Diagnostics.permission("settings-deactivated")
            refreshPermissionState()
            if isAccessibilityTrusted && !isActive && isRelaunchPending {
                scheduleRelaunch(after: 0.3)
            } else {
                didObserveSystemSettings = false
            }
        }
    }

    private static var isSystemSettingsFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return isSystemSettings(app)
    }

    private static func isSystemSettings(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.apple.systempreferences"
            || app.bundleIdentifier == "com.apple.SystemSettings"
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                break
            }
        } catch {
            Diagnostics.permission("launch-at-login-failed error=\(error)")
        }
        rebuildMenu()
    }

    private func migrateLegacyLaunchAgent() {
        let path = Self.legacyLaunchAgentPath
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
            try FileManager.default.removeItem(atPath: path)
        } catch {
            Diagnostics.permission("launch-at-login-migration-failed error=\(error)")
        }
    }

    @objc private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "HyperKey",
            .applicationVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            .credits: NSAttributedString(
                string: "Caps Lock → Hyper key (hold) / F19 (tap)",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var runtimeSummary: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "debug"
        return "version=\(version) pid=\(ProcessInfo.processInfo.processIdentifier) bundleURL=\(Bundle.main.bundleURL.path)"
    }
}

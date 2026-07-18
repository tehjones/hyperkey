import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isActive = false
    private var keyHandler: KeyHandler?
    private var permissionTimer: Timer?
    private var statusItem: NSStatusItem!

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.sergey.hyperkey"

    private static let launchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(bundleID).plist"
    }()

    private var launchAtLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentPath)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        rebuildMenu()

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        activate()

        // Continuously monitor permission state — handles activation, retry,
        // and deactivation if the user revokes permission.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted && !isActive {
                activate()
            } else if !trusted && isActive {
                deactivate()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        deactivate()
        // Note: we intentionally do NOT reset the hidutil mapping on quit.
        // Resetting would wipe any other user key mappings. The Caps Lock → F19
        // mapping is harmless when the app isn't running (F19 is unused by default)
        // and gets cleared on reboot anyway.
    }

    private func activate() {
        keyHandler?.stop()
        keyHandler = KeyHandler()
        keyHandler?.start()

        // Only remap Caps Lock after the event tap is running.
        // If we remap without an active tap, Caps Lock becomes a dead key
        // (produces F19 that nothing intercepts).
        if keyHandler?.isRunning == true {
            HIDUtil.remapCapsLockToF19()
            isActive = true
        } else {
            isActive = false
        }

        updateIcon()
        rebuildMenu()
    }

    private func deactivate() {
        keyHandler?.stop()
        keyHandler = nil
        isActive = false
        updateIcon()
        rebuildMenu()
    }

    private func updateIcon() {
        let image = Bundle.main.image(forResource: NSImage.Name("hyperkey-menu-bar-iconTemplate"))
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "HyperKey")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true

        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("HyperKey")
        statusItem.button?.toolTip = isActive
            ? "HyperKey is active"
            : "HyperKey needs Accessibility permission"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = isActive
            ? "Active"
            : "Inactive — check Accessibility permissions"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.state = isActive ? .on : .off
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLogin ? .on : .off
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

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        setLaunchAtLogin(sender.state != .on)
        rebuildMenu()
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        let path = Self.launchAgentPath
        if enabled {
            let plist: [String: Any] = [
                "Label": Self.bundleID,
                "ProgramArguments": ["/usr/bin/open", "-b", Self.bundleID],
                "RunAtLoad": true,
            ]
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            (plist as NSDictionary).write(to: url, atomically: true)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
        launchAtLogin = FileManager.default.fileExists(atPath: path)
    }
}

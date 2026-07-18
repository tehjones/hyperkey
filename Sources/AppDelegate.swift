import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isActive = false
    var keyHandler: KeyHandler?
    private var permissionTimer: Timer?

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.sergey.hyperkey"

    private static let launchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(bundleID).plist"
    }()

    @Published var launchAtLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentPath)
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
        }
    }

    private func deactivate() {
        keyHandler?.stop()
        keyHandler = nil
        isActive = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
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

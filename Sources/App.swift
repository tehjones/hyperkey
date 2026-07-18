import SwiftUI

@main
struct HyperKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("HyperKey", image: "hyperkey-menu-bar-iconTemplate") {
            MenuContent(appDelegate: appDelegate)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        if appDelegate.isActive {
            Button("✓ Active") {}
        } else {
            Button("✗ Inactive — check Accessibility permissions") {}
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appDelegate.launchAtLogin },
            set: { appDelegate.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("About HyperKey") {
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .applicationName: "HyperKey",
                .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                .credits: NSAttributedString(
                    string: "Caps Lock → Hyper key (hold) / F19 (tap)",
                    attributes: [.font: NSFont.systemFont(ofSize: 11)]
                ),
            ])
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

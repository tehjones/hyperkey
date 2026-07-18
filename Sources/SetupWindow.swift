import AppKit
import SwiftUI

final class SetupWindowController: NSWindowController {
    private let hostingController: NSHostingController<SetupView>

    init(view: SetupView) {
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Set Up HyperKey"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 380))
        window.center()

        self.hostingController = hostingController
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(view: SetupView) {
        hostingController.rootView = view
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SetupView: View {
    let isAccessibilityTrusted: Bool
    let isActive: Bool
    let isEnabled: Bool
    let isFinishingSetup: Bool
    let onRequestAccessibility: () -> Void
    let onOpenSettings: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Make Caps Lock do more")
                .font(.title2.weight(.semibold))
                .padding(.top, 14)

            Text("Hold Caps Lock for Hyper shortcuts. Tap it to send F19.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            PermissionCard(
                isGranted: isAccessibilityTrusted,
                onAllow: onRequestAccessibility
            )
            .padding(.top, 26)

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Spacer(minLength: 22)

            Divider()

            HStack {
                if !isActive {
                    Button("Not Now", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }

                Spacer()

                if !isAccessibilityTrusted {
                    Button("Open System Settings…", action: onOpenSettings)
                } else if isActive || !isEnabled {
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                } else if isAccessibilityTrusted && !isFinishingSetup {
                    Button("Try Again", action: onRetry)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 16)
        }
        .padding(30)
        .frame(width: 520, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusMessage: String {
        if isActive {
            return "You’re ready. HyperKey is active from the menu bar."
        }
        if isFinishingSetup {
            return "HyperKey will reopen to finish setup."
        }
        if isAccessibilityTrusted {
            if !isEnabled {
                return "HyperKey is inactive. Turn it on from the menu bar."
            }
            return "Accessibility is allowed, but HyperKey couldn’t start."
        }
        return "Click Allow to add HyperKey. It uses Accessibility only to handle your keyboard shortcuts."
    }
}

private struct PermissionCard: View {
    let isGranted: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "accessibility")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(.headline)
                Text("Listen for Caps Lock combinations and add shortcut modifiers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: onAllow)
                    .accessibilityLabel("Allow Accessibility")
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

import ApplicationServices
import CoreGraphics
import Foundation

/// Intercepts F19 events (remapped from Caps Lock via hidutil) and implements:
/// - Tap (press + release, no other key in between): send F19
/// - Hold (press + another key): add Hyper flags (Cmd+Shift+Ctrl+Opt) to the other key
final class KeyHandler {
    private static let f19KeyCode: CGKeyCode = 0x50  // 80 decimal
    private static let hyperFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// User data field used to tag synthetic events so the tap ignores them.
    /// 42 == kCGEventSourceUserData, the standard user-data field for CGEvents.
    private static let syntheticEventField = CGEventField(rawValue: 42)!
    private static let syntheticEventMarker: Int64 = 0x4879_7065_724B_6579  // "HyperKey" in ASCII

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<KeyHandler>?
    private(set) var isRunning = false

    // Hyper + hjkl → arrow keys (vim-style navigation)
    private static let arrowKeyMap: [CGKeyCode: CGKeyCode] = [
        0x04: 0x7B,  // h → Left
        0x26: 0x7D,  // j → Down
        0x28: 0x7E,  // k → Up
        0x25: 0x7C,  // l → Right
    ]

    // State for tap-vs-hold detection
    private var f19IsDown = false
    private var otherKeyPressedWhileF19Down = false
    // Keys currently remapped to arrows — tracks across f19 release so keyUp is correct
    private var activeArrowKeys = Set<CGKeyCode>()

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    let handler = Unmanaged<KeyHandler>.fromOpaque(refcon!).takeUnretainedValue()
                    return handler.handle(type: type, event: event)
                },
                userInfo: retained.toOpaque()
            )
        else {
            print("Failed to create event tap — Accessibility permission required.")
            retained.release()
            retainedSelf = nil
            isRunning = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        retainedSelf?.release()
        retainedSelf = nil
        isRunning = false
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if macOS disabled it due to timeout.
        // Do NOT re-enable if permission was revoked — that causes a
        // rapid enable/disable loop that freezes keyboard input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            f19IsDown = false
            otherKeyPressedWhileF19Down = false
            activeArrowKeys.removeAll()
            if AXIsProcessTrusted(), let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Pass through our own synthetic events to avoid infinite loops
        if event.getIntegerValueField(Self.syntheticEventField) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            return handleKeyDown(event: event, keyCode: keyCode)
        case .keyUp:
            return handleKeyUp(event: event, keyCode: keyCode)
        case .flagsChanged:
            return handleFlagsChanged(event: event, keyCode: keyCode)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// F19 arrives as a regular keyDown since hidutil remapped Caps Lock → F19.
    private func handleKeyDown(event: CGEvent, keyCode: CGKeyCode) -> Unmanaged<CGEvent>? {
        if keyCode == Self.f19KeyCode {
            if !f19IsDown {
                // Initial F19 press — start tracking
                f19IsDown = true
                otherKeyPressedWhileF19Down = false
            }
            // Suppress both initial press and any key-repeat events
            return nil
        }

        if f19IsDown {
            otherKeyPressedWhileF19Down = true

            // hjkl → arrow keys
            if let arrowCode = Self.arrowKeyMap[keyCode] {
                activeArrowKeys.insert(keyCode)
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(arrowCode))
                return Unmanaged.passUnretained(event)
            }

            // Everything else → Hyper mode
            event.flags.insert(Self.hyperFlags)
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent, keyCode: CGKeyCode) -> Unmanaged<CGEvent>? {
        if keyCode == Self.f19KeyCode {
            let wasTap = !otherKeyPressedWhileF19Down
            f19IsDown = false
            otherKeyPressedWhileF19Down = false

            if wasTap {
                postF19()
            }
            return nil  // suppress the raw F19 up
        }

        // Arrow key release — must check before f19IsDown since f19 may already be released
        if activeArrowKeys.remove(keyCode) != nil {
            if let arrowCode = Self.arrowKeyMap[keyCode] {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(arrowCode))
                return Unmanaged.passUnretained(event)
            }
        }

        if f19IsDown {
            // Release of a key that was modified with Hyper
            event.flags.insert(Self.hyperFlags)
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// Handle modifier flag changes (shift, ctrl, etc. pressed while F19 held).
    private func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode) -> Unmanaged<CGEvent>? {
        if f19IsDown && keyCode != Self.f19KeyCode {
            otherKeyPressedWhileF19Down = true
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Synthetic events

    private func postF19() {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: Self.f19KeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: Self.f19KeyCode, keyDown: false)
        else { return }
        down.setIntegerValueField(Self.syntheticEventField, value: Self.syntheticEventMarker)
        up.setIntegerValueField(Self.syntheticEventField, value: Self.syntheticEventMarker)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}

import Foundation

enum HIDUtil {
    private static let capsLockSrc = 0x700000039
    private static let f19Dst = 0x70000006E

    /// Remap Caps Lock to F19 at the HID level using hidutil.
    /// This eliminates all Caps Lock quirks (delay, toggle behavior).
    /// Preserves any existing user key mappings.
    static func remapCapsLockToF19() {
        // Remove the ~300ms Caps Lock delay that macOS applies at the HID level.
        // This delay happens BEFORE the key remapping and would cause the first
        // press to feel laggy or get dropped entirely.
        disableCapsLockDelay()

        var mappings = currentMappings()

        // Remove any existing Caps Lock mapping, then add ours
        mappings.removeAll { $0["HIDKeyboardModifierMappingSrc"] == capsLockSrc }
        mappings.append([
            "HIDKeyboardModifierMappingSrc": capsLockSrc,
            "HIDKeyboardModifierMappingDst": f19Dst,
        ])

        setMappings(mappings)
    }

    private static func disableCapsLockDelay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", #"{"CapsLockDelayOverride":0}"#]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("hidutil failed: \(error)")
        }
    }

    private static func currentMappings() -> [[String: Int]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // hidutil outputs OpenStep plist format where numeric values may parse
        // as NSString or NSNumber depending on macOS version. Handle both.
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let array = plist as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict in
            guard let src = toInt(dict["HIDKeyboardModifierMappingSrc"]),
                  let dst = toInt(dict["HIDKeyboardModifierMappingDst"]) else {
                return nil
            }
            return ["HIDKeyboardModifierMappingSrc": src, "HIDKeyboardModifierMappingDst": dst]
        }
    }

    private static func toInt(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func setMappings(_ mappings: [[String: Int]]) {
        guard let json = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings]),
              let jsonString = String(data: json, encoding: .utf8)
        else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", jsonString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("hidutil failed: \(error)")
        }
    }
}

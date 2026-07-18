import Foundation

enum Diagnostics {
    private static let queue = DispatchQueue(label: "com.sergey.hyperkey.diagnostics")

    static func permission(_ message: @autoclosure () -> String) {
        let output = message()
        queue.async {
            appendPermissionLog(output)
        }
    }

    private static func appendPermissionLog(_ message: String) {
        guard let libraryURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let directory = libraryURL.appendingPathComponent("Logs/HyperKey", isDirectory: true)
        let logURL = directory.appendingPathComponent("permission.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = "\(Date()) \(message)\n".data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}

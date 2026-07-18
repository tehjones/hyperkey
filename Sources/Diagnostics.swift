import Foundation

enum Diagnostics {
    private static let queue = DispatchQueue(label: "com.sergey.hyperkey.diagnostics")
    private static let maxPermissionLogBytes = 256 * 1024

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
        rotatePermissionLogIfNeeded(at: logURL)

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

    private static func rotatePermissionLogIfNeeded(at logURL: URL) {
        guard let values = try? logURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize >= maxPermissionLogBytes
        else {
            return
        }

        let rotatedURL = logURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: logURL, to: rotatedURL)
    }
}

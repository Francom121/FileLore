import Foundation

/// File-based diagnostic logger for the Quick Look extension.
///
/// Same rationale as the Finder Sync `DebugLog`: unified logging redacts
/// `NSLog` output from the ExtensionKit-hosted extension, which leaves
/// preview debugging blind. This writes plain timestamped lines to a text
/// file inside the extension's sandbox container instead: in this sandboxed
/// process `homeDirectoryForCurrentUser` IS the container's `Data` directory
/// (`~/Library/Containers/com.filelore.app.QuickLook/Data`), which is always
/// writable.
///
/// All writes are serialized on a private queue and every failure is
/// swallowed — diagnostics must never break the extension.
enum DebugLog {

    /// Absolute path of the log file (inside the sandbox container).
    static let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("filelore-ql-debug.log", isDirectory: false)
    }()

    /// The log is rolled once it exceeds this many bytes.
    private static let maxBytes: UInt64 = 256 * 1024

    private static let queue = DispatchQueue(label: "com.filelore.app.QuickLook.DebugLog")

    /// Only used on `queue`, so no extra synchronization is needed.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Appends one timestamped line to the log file. Never throws.
    static func log(_ message: String) {
        queue.async {
            write(message)
        }
    }

    /// Serial-queue body of `log`. Creates the file on first use, rolls it
    /// when it has grown past `maxBytes`, then appends the line.
    private static func write(_ message: String) {
        let line = "\(timestampFormatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let fileManager = FileManager.default
        let path = fileURL.path(percentEncoded: false)

        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        rollIfNeeded(fileManager: fileManager, path: path)

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics only — never propagate.
        }
    }

    /// Once the file exceeds `maxBytes`, keeps only the trailing half
    /// (aligned to a line boundary) so recent lines survive.
    private static func rollIfNeeded(fileManager: FileManager, path: String) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? UInt64,
              size > maxBytes,
              let handle = try? FileHandle(forReadingFrom: fileURL)
        else { return }

        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: size / 2)
            let tail = try handle.readToEnd() ?? Data()
            // Skip to the next '\n' (0x0A) so the kept tail starts on a line boundary.
            let start = tail.firstIndex(of: 0x0A).map { tail.index(after: $0) } ?? tail.startIndex
            let kept = Data("[DebugLog] rolled — kept most recent half\n".utf8) + tail[start...]
            try kept.write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics only — never propagate.
        }
    }
}

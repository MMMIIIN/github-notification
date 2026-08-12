import Foundation

/// Append-only diagnostic log at ~/Library/Logs/GitHubNotifier.log.
///
/// Traces the full delivery path — poll → filter → unread diff → menu bar badge
/// — so a notification that never reaches the icon can be located precisely.
/// Writes are serialized on a private queue and never block the poll loop.
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.ghnotifier.debuglog")

    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("GitHubNotifier.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ category: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

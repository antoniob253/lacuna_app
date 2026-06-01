import Foundation

/// Shared App Group container for handing capsule data from the iMessage extension
/// to the main Lacuna app. Both targets must list this identifier in their entitlements.
///
/// All methods are `nonisolated` because they're hit from off-main paths
/// (download tasks, sweep operations).
enum MessagesAppGroup {
    nonisolated static let identifier = "group.antoniobaltic.embargo"
    nonisolated private static let incomingFolder = "incoming"

    enum Error: Swift.Error {
        case containerUnavailable
    }

    nonisolated static func containerURL() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw Error.containerUnavailable
        }
        return url
    }

    nonisolated static func incomingDirectory() throws -> URL {
        let dir = try containerURL().appendingPathComponent(incomingFolder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Stage the payload bytes so the main app can read them after `extensionContext.open()`.
    nonisolated static func writeIncoming(data: Data, id: String) throws {
        let url = try incomingDirectory().appendingPathComponent("\(id).capsule")
        try data.write(to: url, options: .atomic)
    }

    /// Read + delete (one-shot consume) of staged payload by id.
    nonisolated static func consumeIncoming(id: String) -> Data? {
        guard let url = try? incomingDirectory().appendingPathComponent("\(id).capsule"),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return data
    }

    /// Sweep stale staged payloads older than the given interval. Safety net so the
    /// shared container doesn't accumulate orphans when imports fail mid-flight.
    nonisolated static func purgeOlderThan(_ interval: TimeInterval) {
        guard let dir = try? incomingDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
              ) else { return }
        let cutoff = Date.now.addingTimeInterval(-interval)
        for url in entries {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mod, mod < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

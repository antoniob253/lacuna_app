import Foundation

/// Shared App Group container for handing capsule data from the iMessage extension
/// to the main Lacuna app. Twin of the extension's identical type — both must be
/// kept in sync so the wire format never drifts between targets.
///
/// All methods are `nonisolated` because they're hit from off-main paths
/// (CloudKit upload tracker, extension hand-off, sweep tasks).
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

    nonisolated static func writeIncoming(data: Data, id: String) throws {
        let url = try incomingDirectory().appendingPathComponent("\(id).capsule")
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func consumeIncoming(id: String) -> Data? {
        guard let url = try? incomingDirectory().appendingPathComponent("\(id).capsule"),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return data
    }

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

import CloudKit
import CryptoKit
import Foundation

/// Downloads + decrypts capsule payloads referenced by `v=2` MSMessage URLs.
///
/// The matching upload side lives in the main app at
/// `Lacuna/Utilities/CapsuleTransport.swift`. Both must agree on the container
/// id, record type, and field names — kept in sync manually since the targets
/// don't share source.
enum CapsuleTransport {
    nonisolated static let containerID = "iCloud.antoniobaltic.embargo"
    nonisolated static let recordType = "CapsuleTransport"
    nonisolated static let payloadField = "payload"
    /// Hard ceiling on download time so the recipient never gets stuck in a
    /// "downloading..." state when the network is flaky.
    nonisolated static let downloadTimeout: TimeInterval = 30

    enum TransportError: Error, LocalizedError {
        case downloadFailed(underlying: Error?)
        case recordNotFound
        case payloadMissing
        case decryptionFailed
        case noNetwork
        case timedOut

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "couldn't download the capsule"
            case .recordNotFound: "this capsule has expired or was removed"
            case .payloadMissing: "the capsule data is missing"
            case .decryptionFailed: "couldn't decrypt the capsule"
            case .noNetwork: "no network connection"
            case .timedOut: "download took too long. tap to try again"
            }
        }
    }

    nonisolated private static var container: CKContainer { CKContainer(identifier: containerID) }
    nonisolated private static var database: CKDatabase { container.publicCloudDatabase }

    nonisolated static func download(recordID: String, key: SymmetricKey) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Self.performDownload(recordID: recordID, key: key)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(downloadTimeout))
                throw TransportError.timedOut
            }
            guard let first = try await group.next() else {
                throw TransportError.downloadFailed(underlying: nil)
            }
            group.cancelAll()
            return first
        }
    }

    nonisolated private static func performDownload(recordID: String, key: SymmetricKey) async throws -> Data {
        let id = CKRecord.ID(recordName: recordID)

        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            throw TransportError.recordNotFound
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw TransportError.noNetwork
        } catch {
            throw TransportError.downloadFailed(underlying: error)
        }

        guard let asset = record[payloadField] as? CKAsset,
              let fileURL = asset.fileURL,
              let combined = try? Data(contentsOf: fileURL) else {
            throw TransportError.payloadMissing
        }

        guard let sealed = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealed, using: key) else {
            throw TransportError.decryptionFailed
        }

        return plaintext
    }
}

extension SymmetricKey {
    init?(fromBase64URL string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        self.init(data: data)
    }
}

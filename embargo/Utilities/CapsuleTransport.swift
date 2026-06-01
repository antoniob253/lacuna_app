import CloudKit
import CryptoKit
import Foundation

/// Encrypted, key-in-URL transport for capsules that don't fit inline in an
/// MSMessage URL (photos, longer voice notes).
///
/// **Privacy model**: the capsule payload is sealed with a random 256-bit
/// AES-GCM key on the sender's device. Only the encrypted blob is uploaded to
/// CloudKit's public database. The decryption key travels exclusively inside
/// the recipient's MSMessage URL — Apple sees the ciphertext but cannot read
/// the contents. After the recipient downloads, the record sits in CloudKit
/// for 30 days (sender-stamped `expiresAt`) and is best-effort cleaned up by
/// the sender's app on launch.
enum CapsuleTransport {
    nonisolated static let containerID = "iCloud.antoniobaltic.embargo"
    nonisolated static let recordType = "CapsuleTransport"
    nonisolated static let payloadField = "payload"
    nonisolated static let expiresAtField = "expiresAt"
    nonisolated static let recordTTL: TimeInterval = 30 * 24 * 60 * 60

    enum TransportError: Error, LocalizedError {
        case encryptionFailed
        case uploadFailed(underlying: Error?)
        case downloadFailed(underlying: Error?)
        case recordNotFound
        case payloadMissing
        case decryptionFailed
        case noNetwork
        case notSignedIntoiCloud
        case quotaExceeded

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: "couldn't encrypt the capsule"
            case .uploadFailed: "couldn't upload the capsule"
            case .downloadFailed: "couldn't download the capsule"
            case .recordNotFound: "this capsule has expired or was removed"
            case .payloadMissing: "the capsule data is missing"
            case .decryptionFailed: "couldn't decrypt the capsule"
            case .noNetwork: "no network connection"
            case .notSignedIntoiCloud: "sign in to icloud to send media via imessage"
            case .quotaExceeded: "your icloud is full"
            }
        }
    }

    nonisolated private static var container: CKContainer { CKContainer(identifier: containerID) }
    nonisolated private static var database: CKDatabase { container.publicCloudDatabase }

    // MARK: - Account check

    /// Quick check that the device is signed into iCloud and the account is
    /// usable. Lets the sender flow surface a clean error before doing the
    /// (slow) upload attempt.
    nonisolated static func accountIsReady() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - Upload (sender side)

    struct UploadResult: Sendable {
        let recordID: String
        let key: SymmetricKey
    }

    nonisolated static func upload(payload: Data) async throws -> UploadResult {
        // Seal the payload locally with a fresh per-capsule key
        let key = SymmetricKey(size: .bits256)
        guard let sealed = try? AES.GCM.seal(payload, using: key),
              let combined = sealed.combined else {
            throw TransportError.encryptionFailed
        }

        // CKAsset wants a file URL; stage the ciphertext to tmp
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).enc")
        do {
            try combined.write(to: tempURL, options: .atomic)
        } catch {
            throw TransportError.uploadFailed(underlying: error)
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordName = UUID().uuidString
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[payloadField] = CKAsset(fileURL: tempURL)
        record[expiresAtField] = Date.now.addingTimeInterval(recordTTL) as NSDate

        do {
            _ = try await database.save(record)
        } catch let ckError as CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                throw TransportError.noNetwork
            case .notAuthenticated:
                throw TransportError.notSignedIntoiCloud
            case .quotaExceeded:
                throw TransportError.quotaExceeded
            default:
                throw TransportError.uploadFailed(underlying: ckError)
            }
        } catch {
            throw TransportError.uploadFailed(underlying: error)
        }

        // Track the record ID locally so we can sweep it after expiry
        UploadedRecordTracker.add(recordID: recordName, expiresAt: Date.now.addingTimeInterval(recordTTL))

        return UploadResult(recordID: recordName, key: key)
    }

    /// Best-effort delete of an uploaded record. Used when the user cancels
    /// the iMessage composer — no point keeping ciphertext nobody will read.
    nonisolated static func delete(recordID: String) async {
        let id = CKRecord.ID(recordName: recordID)
        _ = try? await database.deleteRecord(withID: id)
        UploadedRecordTracker.remove(recordID: recordID)
    }

    /// Sweep expired records the user uploaded from this device. Call on app
    /// launch — runs detached and silent.
    nonisolated static func sweepExpiredRecords() async {
        let expired = UploadedRecordTracker.expiredRecordIDs(now: Date.now)
        guard !expired.isEmpty else { return }
        let ckIDs = expired.map { CKRecord.ID(recordName: $0) }
        _ = try? await database.modifyRecords(saving: [], deleting: ckIDs)
        UploadedRecordTracker.remove(recordIDs: expired)
    }
}

// MARK: - Local tracker for uploaded records

/// Persists the record IDs we've uploaded so we can clean them up later.
/// Lives in App Group so the iMessage extension could read it too if ever needed.
/// Marked nonisolated method-by-method because callers run off the main actor.
enum UploadedRecordTracker {
    nonisolated private static let key = "uploadedRecordIDs.v1"

    nonisolated private struct Entry: Codable {
        let recordID: String
        let expiresAt: Date
    }

    nonisolated private static var defaults: UserDefaults {
        UserDefaults(suiteName: MessagesAppGroup.identifier) ?? .standard
    }

    nonisolated static func add(recordID: String, expiresAt: Date) {
        var entries = load()
        entries.append(Entry(recordID: recordID, expiresAt: expiresAt))
        save(entries)
    }

    nonisolated static func remove(recordID: String) {
        let entries = load().filter { $0.recordID != recordID }
        save(entries)
    }

    nonisolated static func remove(recordIDs: [String]) {
        let set = Set(recordIDs)
        let entries = load().filter { !set.contains($0.recordID) }
        save(entries)
    }

    nonisolated static func expiredRecordIDs(now: Date) -> [String] {
        load().filter { $0.expiresAt < now }.map(\.recordID)
    }

    nonisolated private static func load() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    nonisolated private static func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Key codec

extension SymmetricKey {
    nonisolated func toBase64URL() -> String {
        withUnsafeBytes { Data($0) }
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated init?(fromBase64URL string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        self.init(data: data)
    }
}

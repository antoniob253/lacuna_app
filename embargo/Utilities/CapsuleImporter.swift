import Foundation
import SwiftData

enum CapsuleImporter {
    enum ImportResult {
        /// Newly imported capsule
        case imported(Capsule)
        /// A capsule with the same sender + creation + unlock was already in the
        /// store. Caller should surface this to the user (so a re-tap doesn't
        /// silently do nothing).
        case alreadyExists(Capsule)
        /// The payload couldn't be decoded — corrupt or wrong format.
        case malformed
    }

    /// Import from a `.capsule` file URL — used when the user opens a `.capsule`
    /// attachment from Files, AirDrop, WhatsApp, etc.
    static func importCapsule(from url: URL, modelContext: ModelContext) -> ImportResult {
        guard url.pathExtension == "capsule" else { return .malformed }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else { return .malformed }
        return importCapsule(from: data, modelContext: modelContext)
    }

    /// Import from raw `CapsulePackage` JSON bytes — used by the iMessage
    /// extension hand-off path, where the payload arrives via App Group rather
    /// than a security-scoped file URL.
    static func importCapsule(from data: Data, modelContext: ModelContext) -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let package = try? decoder.decode(CapsulePackage.self, from: data) else { return .malformed }
        guard let capsuleType = CapsuleType(rawValue: package.type) else { return .malformed }

        // Deduplication: identical sender + creation + unlock triple means we already have it
        let senderName = package.senderName
        let title = package.title
        let unlocksAt = package.unlocksAt
        let createdAt = package.createdAt

        let descriptor = FetchDescriptor<Capsule>(predicate: #Predicate<Capsule> {
            $0.senderName == senderName &&
            $0.unlocksAt == unlocksAt &&
            $0.createdAt == createdAt
        })

        if let existing = try? modelContext.fetch(descriptor).first {
            return .alreadyExists(existing)
        }

        var audioData: Data?
        if let audioBase64 = package.audioData {
            audioData = Data(base64Encoded: audioBase64)
        }

        var imageData: Data?
        if let imageBase64 = package.imageData {
            imageData = Data(base64Encoded: imageBase64)
        }

        let capsule = Capsule(
            title: title,
            type: capsuleType,
            textContent: package.textContent,
            imageData: imageData,
            audioData: audioData,
            unlocksAt: unlocksAt,
            senderName: senderName
        )

        modelContext.insert(capsule)

        // Schedule notification — NotificationManager skips past-due dates itself
        NotificationManager.scheduleCapsuleNotification(
            id: capsule.id.uuidString,
            title: title,
            unlockDate: unlocksAt
        )

        return .imported(capsule)
    }
}

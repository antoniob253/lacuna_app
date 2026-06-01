import CryptoKit
import Foundation
import Messages
import MessageUI
import UIKit

/// Sends a sealed capsule via iMessage's rich-message UI.
///
/// Two transport modes are picked transparently per capsule:
///
/// 1. **Inline** (`v=1`) — full payload base64-encoded into the MSMessage URL.
///    Used for small payloads (typically text capsules). Fastest, no network.
///
/// 2. **CloudKit** (`v=2`) — payload is encrypted with a fresh AES-GCM key,
///    uploaded to CloudKit's public DB, and the MSMessage URL carries only
///    a record id + decryption key + tiny metadata sidecar. Used when the
///    payload doesn't fit inline (photos, longer voice notes).
///
/// The recipient's iMessage extension reads the wire version and either
/// reads the inline data or downloads + decrypts from CloudKit.
enum iMessageSender {
    /// Conservative cap on the URL string. MSMessage URLs survive much larger
    /// in some iOS versions but the behavior is implementation-defined past
    /// ~16 KB. Below this we're rock-solid; above this we go through CloudKit.
    /// Text capsules are typically a few hundred bytes, so they always fit.
    static let maxInlineURLBytes = 16_000

    enum Availability {
        case available
        case deviceCannotSend
    }

    /// MainActor because `MFMessageComposeViewController.canSendText()` is itself
    /// MainActor-isolated. All callers run on MainActor anyway (SwiftUI views).
    static func availability() -> Availability {
        MFMessageComposeViewController.canSendText() ? .available : .deviceCannotSend
    }

    /// Result of preparing a send. The composer is ready to present.
    struct PreparedSend {
        let composer: MFMessageComposeViewController
        /// CloudKit record id, if any. Caller passes this back if the user cancels
        /// the composer so we can clean up the orphaned upload.
        let cloudKitRecordID: String?
    }

    enum PrepareError: Error, LocalizedError {
        case deviceCannotSend
        case encodingFailed
        case uploadFailed(CapsuleTransport.TransportError)

        var errorDescription: String? {
            switch self {
            case .deviceCannotSend: "this device can't send messages"
            case .encodingFailed: "couldn't encode the capsule"
            case .uploadFailed(let e): e.errorDescription
            }
        }
    }

    /// Prepares an MFMessageComposeViewController with an attached MSMessage.
    /// Performs the CloudKit upload synchronously (`async`) for large payloads
    /// so the composer never opens with a half-baked message.
    static func prepareSend(
        capsule: Capsule,
        senderName: String,
        delegate: MFMessageComposeViewControllerDelegate
    ) async throws -> PreparedSend {
        guard MFMessageComposeViewController.canSendText() else { throw PrepareError.deviceCannotSend }

        // Build the Sendable snapshot on the main actor (since Capsule is @Model),
        // then hand the snapshot off to nonisolated workers for encoding/upload.
        let package = CapsulePackage(from: capsule, senderName: senderName)
        let unlocksAt = capsule.unlocksAt
        let title = capsule.title
        let typeLabel = capsule.type.label

        let payloadData = try await encode(package: package)

        // Try inline first
        let inlineURL = inlineURLString(payloadData: payloadData)
        let messageURLString: String
        let cloudKitRecordID: String?

        if inlineURL.utf8.count <= maxInlineURLBytes, URL(string: inlineURL) != nil {
            messageURLString = inlineURL
            cloudKitRecordID = nil
        } else {
            // Inline doesn't fit — go through CloudKit. Pre-check iCloud account
            // status so we surface a clean error before we even try to upload.
            let accountReady = await CapsuleTransport.accountIsReady()
            if !accountReady {
                throw PrepareError.uploadFailed(.notSignedIntoiCloud)
            }
            do {
                let upload = try await CapsuleTransport.upload(payload: payloadData)
                let metadata = try metadataSidecar(
                    senderName: senderName,
                    title: title,
                    typeRaw: package.type,
                    unlocksAt: unlocksAt
                )
                messageURLString = cloudKitURLString(
                    recordID: upload.recordID,
                    key: upload.key,
                    metadataBase64: metadata
                )
                cloudKitRecordID = upload.recordID
            } catch let e as CapsuleTransport.TransportError {
                throw PrepareError.uploadFailed(e)
            } catch {
                throw PrepareError.uploadFailed(.uploadFailed(underlying: error))
            }
        }

        guard let url = URL(string: messageURLString) else { throw PrepareError.encodingFailed }

        // Build the MSMessage (must happen on MainActor — UIKit/Messages requirement)
        let message = MSMessage(session: MSSession())
        message.url = url
        message.summaryText = "a time capsule from \(senderName)"
        message.accessibilityLabel = "a time capsule from \(senderName), \(unlockBadge(for: unlocksAt))"

        let layout = MSMessageTemplateLayout()
        layout.caption = "a time capsule from \(senderName)"
        layout.subcaption = title.isEmpty ? typeLabel : title
        layout.trailingSubcaption = unlockBadge(for: unlocksAt)
        layout.imageTitle = "lacuna"
        layout.image = brandedCardImage()
        message.layout = layout

        let composer = MFMessageComposeViewController()
        composer.message = message
        composer.body = "i sealed a time capsule for you. open it in lacuna: https://apps.apple.com/app/lacuna-time-capsule/id6761478231"
        composer.messageComposeDelegate = delegate

        return PreparedSend(composer: composer, cloudKitRecordID: cloudKitRecordID)
    }

    // MARK: - Encoding (nonisolated, Sendable inputs only)

    nonisolated private static func encode(package: CapsulePackage) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(package) else { throw PrepareError.encodingFailed }
        return data
    }

    nonisolated private static func inlineURLString(payloadData: Data) -> String {
        let base64 = payloadData.base64EncodedString().toURLBase64
        return "lacuna://capsule?v=1&d=\(base64)"
    }

    nonisolated private static func cloudKitURLString(recordID: String, key: SymmetricKey, metadataBase64: String) -> String {
        "lacuna://capsule?v=2&r=\(recordID)&k=\(key.toBase64URL())&m=\(metadataBase64)"
    }

    /// Tiny JSON metadata sidecar so the recipient's card renders without a download.
    /// Takes primitive Sendable inputs so it stays nonisolated and the call site
    /// doesn't have to hop actors.
    nonisolated private static func metadataSidecar(
        senderName: String,
        title: String,
        typeRaw: String,
        unlocksAt: Date
    ) throws -> String {
        let dict: [String: Any] = [
            "senderName": senderName,
            "title": title,
            "type": typeRaw,
            "unlocksAt": ISO8601DateFormatter().string(from: unlocksAt)
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return data.base64EncodedString().toURLBase64
    }

    nonisolated private static func unlockBadge(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "opens \(formatter.string(from: date))"
    }

    // MARK: - Card image (MainActor — uses UIKit rendering)

    private static func brandedCardImage() -> UIImage? {
        let size = CGSize(width: 600, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext

            UIColor(red: 0.969, green: 0.953, blue: 0.933, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let circleRadius: CGFloat = 70
            let circleRect = CGRect(
                x: center.x - circleRadius,
                y: center.y - circleRadius - 18,
                width: circleRadius * 2,
                height: circleRadius * 2
            )
            UIColor(red: 0.047, green: 0.055, blue: 0.067, alpha: 1.0).setFill()
            cg.fillEllipse(in: circleRect)

            if let lock = UIImage(systemName: "lock.fill") {
                let glyphSize: CGFloat = 56
                let lockRect = CGRect(
                    x: center.x - glyphSize / 2,
                    y: center.y - glyphSize / 2 - 18,
                    width: glyphSize,
                    height: glyphSize
                )
                let config = UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .regular)
                let glyph = lock.applyingSymbolConfiguration(config) ?? lock
                let cremeBg = UIColor(red: 0.969, green: 0.953, blue: 0.933, alpha: 1.0)
                glyph.withTintColor(cremeBg, renderingMode: .alwaysOriginal).draw(in: lockRect)
            }

            let title = "lacuna"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(red: 0.047, green: 0.055, blue: 0.067, alpha: 1.0),
                .kern: 4 as NSNumber
            ]
            let titleSize = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(
                at: CGPoint(x: center.x - titleSize.width / 2, y: center.y + circleRadius + 4),
                withAttributes: attrs
            )
        }
    }
}

private extension String {
    nonisolated var toURLBase64: String {
        replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

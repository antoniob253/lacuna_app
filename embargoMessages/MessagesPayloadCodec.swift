import CryptoKit
import Foundation

/// Decodes the capsule payload wire format on the receiving side.
///
/// **Wire formats** — all use the URL `lacuna://capsule?...`:
///
/// - `v=1` (or no `v`): the entire `CapsulePackage` JSON is base64-encoded into
///   the `d` parameter. Used for small text capsules that comfortably fit in
///   an MSMessage URL.
///
/// - `v=2`: the payload is encrypted, uploaded to CloudKit's public DB, and
///   referenced via:
///     - `r` — record ID (CloudKit recordName)
///     - `k` — base64-url AES-GCM 256 key
///     - `m` — base64-url JSON metadata sidecar (sender, title, type, unlocksAt)
///         so the iMessage card renders without a network round-trip.
enum MessagesPayloadCodec {
    static let urlScheme = "lacuna"
    static let urlHost = "capsule"

    static func decode(from url: URL) -> ReceivedCapsulePayload? {
        guard url.scheme == urlScheme, url.host == urlHost,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        let version = items.first(where: { $0.name == "v" })?.value ?? "1"

        switch version {
        case "1":
            return decodeV1(items: items)
        case "2":
            return decodeV2(items: items)
        default:
            return nil
        }
    }

    // MARK: - v1 (inline)

    private static func decodeV1(items: [URLQueryItem]) -> ReceivedCapsulePayload? {
        guard let value = items.first(where: { $0.name == "d" })?.value,
              let raw = Data(base64Encoded: value.fromURLBase64) else { return nil }
        guard let meta = ReceivedCapsulePayload.Metadata.from(jsonData: raw) else { return nil }
        return ReceivedCapsulePayload(
            metadata: meta,
            content: .inline(raw)
        )
    }

    // MARK: - v2 (CloudKit reference)

    private static func decodeV2(items: [URLQueryItem]) -> ReceivedCapsulePayload? {
        guard let recordID = items.first(where: { $0.name == "r" })?.value,
              let keyString = items.first(where: { $0.name == "k" })?.value,
              let key = SymmetricKey(fromBase64URL: keyString),
              let metaString = items.first(where: { $0.name == "m" })?.value,
              let metaData = Data(base64Encoded: metaString.fromURLBase64),
              let meta = ReceivedCapsulePayload.Metadata.from(metadataJSONData: metaData) else { return nil }
        return ReceivedCapsulePayload(
            metadata: meta,
            content: .cloudKit(recordID: recordID, key: key)
        )
    }
}

struct ReceivedCapsulePayload {
    struct Metadata {
        let senderName: String
        let title: String
        let typeLabel: String
        let unlocksAt: Date

        var titleOrType: String { title.isEmpty ? typeLabel : title }

        var unlockSubtitle: String {
            if unlocksAt <= Date.now { return "ready to open" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return "opens \(formatter.string(from: unlocksAt))"
        }

        /// Metadata pulled out of a full `CapsulePackage` JSON blob (v1 path).
        static func from(jsonData: Data) -> Metadata? {
            guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
            return Metadata(
                senderName: (json["senderName"] as? String) ?? "someone",
                title: (json["title"] as? String) ?? "",
                typeLabel: (json["type"] as? String) ?? "text",
                unlocksAt: ISO8601DateFormatter().date(from: (json["unlocksAt"] as? String) ?? "") ?? Date.now
            )
        }

        /// Metadata pulled from the v2 sidecar (small JSON: senderName/title/type/unlocksAt).
        static func from(metadataJSONData: Data) -> Metadata? {
            from(jsonData: metadataJSONData)
        }
    }

    enum Content {
        /// Full payload bytes are already in the URL.
        case inline(Data)
        /// Payload must be downloaded from CloudKit and decrypted with the included key.
        case cloudKit(recordID: String, key: SymmetricKey)
    }

    let metadata: Metadata
    let content: Content
}

extension String {
    var toURLBase64: String {
        replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var fromURLBase64: String {
        var s = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return s
    }

    var urlPercentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

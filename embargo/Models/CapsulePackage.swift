import Foundation

nonisolated struct CapsulePackage: Codable, Sendable {
    let version: Int
    let type: String
    let title: String
    let textContent: String?
    let imageData: String?
    let audioData: String?
    let createdAt: Date
    let unlocksAt: Date
    let senderName: String

    init(from capsule: Capsule, senderName: String) {
        self.version = 1
        self.type = capsule.type.rawValue
        self.title = capsule.title
        self.textContent = capsule.textContent
        self.imageData = capsule.imageData?.base64EncodedString()
        self.senderName = senderName
        self.createdAt = capsule.createdAt
        self.unlocksAt = capsule.unlocksAt

        if let data = capsule.resolvedAudioData {
            self.audioData = data.base64EncodedString()
        } else {
            self.audioData = nil
        }
    }
}

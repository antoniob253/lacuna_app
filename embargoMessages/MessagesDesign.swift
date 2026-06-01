import SwiftUI

/// Mirror of the main app's Design constants — kept tiny so the iMessage extension
/// stays small and self-contained. Source of truth lives in Lacuna's `Design.swift`.
enum MessagesDesign {
    static let bg = Color(.cremeBackground)
    static let fg = Color(.cremeForeground)

    static let trackingNormal: Double = 1
    static let trackingWide: Double = 3
    static let trackingButton: Double = 4
}

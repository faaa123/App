import StudyCore
import SwiftUI
import UIKit

/// Study = deep, calm navy; rest = bright yellow. Shape (icon, band height,
/// bar outline) differs too, so color is never the only cue.
///
/// Fills keep the same hue in light and dark mode (they carry meaning);
/// `mark` (lines and bars on the page background) is tuned per appearance
/// for ≥ 3:1 contrast, and darker still with Increase Contrast.
struct BlockStyle {
    /// Large fills, with `onColor` content on them.
    let color: Color
    let onColor: Color
    /// Lines, bars and icons drawn on the page background.
    let mark: Color
    let icon: String
    let label: String

    static let study = BlockStyle(
        color: Color(hex: 0x2E3A8C),
        onColor: Color(hex: 0xF2F3FF),
        mark: Color(light: 0x3949AB, dark: 0x8C9EFF, lightHigh: 0x26338A, darkHigh: 0xB3C0FF),
        icon: "book.fill",
        label: "勉強")
    static let rest = BlockStyle(
        color: Color(hex: 0xFFC857),
        onColor: Color(hex: 0x3A2A00),
        mark: Color(light: 0x9A6B00, dark: 0xFFC857, lightHigh: 0x6E4C00, darkHigh: 0xFFD98A),
        icon: "cup.and.saucer.fill",
        label: "休憩")

    static func of(_ t: BlockType) -> BlockStyle { t == .study ? study : rest }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that follows the appearance (and Increase Contrast).
    init(light: UInt32, dark: UInt32, lightHigh: UInt32? = nil, darkHigh: UInt32? = nil) {
        self.init(uiColor: UIColor { t in
            let high = t.accessibilityContrast == .high
            switch (t.userInterfaceStyle == .dark, high) {
            case (true, true): return UIColor(hex: darkHigh ?? dark)
            case (true, false): return UIColor(hex: dark)
            case (false, true): return UIColor(hex: lightHigh ?? light)
            case (false, false): return UIColor(hex: light)
            }
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255,
                  green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A rounded content-layer card (system grouped background, not Liquid
/// Glass: glass is reserved for controls floating above content).
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

extension View {
    /// Caps content width and centres it, so text lines and lists do not
    /// stretch across a large landscape iPad.
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

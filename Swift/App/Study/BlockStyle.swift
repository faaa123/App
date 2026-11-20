import StudyCore
import SwiftUI
import UIKit

/// The "墨と青" (ink and blue) palette: a warm grey page, white cards, one
/// ink-black hero card, blue for study and orange for rest.
enum Theme {
    /// Page background behind the cards.
    static let page = Color(light: 0xF2F2EF, dark: 0x0E0F12)
    /// Cards on the page.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1C21)
    /// Small controls inside a card (stepper buttons).
    static let sunken = Color(light: 0xF2F2EF, dark: 0x2A2C33)
    /// The one dark card per screen (current block, streak, day total).
    static let hero = Color(light: 0x16171B, dark: 0x2A2C33)
    static let heroText = Color(hex: 0xF5F5F2)
    static let heroSecondary = Color(hex: 0xA9ABB3)
    /// Blue that reads on the hero card.
    static let heroAccent = Color(hex: 0x8FA2FF)
    /// Blue on the page and on cards (also the app's tint).
    static let accent = Color(light: 0x3550E6, dark: 0x8FA2FF, lightHigh: 0x2238B8, darkHigh: 0xB3C0FF)
    /// Empty part of bars and tracks.
    static let track = Color(light: 0xE3E3DE, dark: 0x33353C)
    /// Free time between blocks (dashed rules).
    static let free = Color(light: 0xA3A5AB, dark: 0x5D5F66)
}

/// Study = ink card with blue marks; rest = orange. Shape (bar vs dot, band
/// height, icon) differs too, so color is never the only cue.
///
/// `color` fills keep their hue in light and dark mode (they carry meaning);
/// `mark` (lines and bars on the page) is tuned per appearance for ≥ 3:1
/// contrast, and stronger still with Increase Contrast.
struct BlockStyle {
    /// Large fills, with `onColor` content on them.
    let color: Color
    let onColor: Color
    /// Secondary text on `color`.
    let onSecondary: Color
    /// Progress drawn on `color`.
    let onAccent: Color
    /// Lines, bars and icons drawn on the page or a card.
    let mark: Color
    let icon: String
    let label: String

    static let study = BlockStyle(
        color: Theme.hero,
        onColor: Theme.heroText,
        onSecondary: Theme.heroSecondary,
        onAccent: Theme.heroAccent,
        mark: Theme.accent,
        icon: "book.fill",
        label: "勉強")
    static let rest = BlockStyle(
        color: Color(hex: 0xFF9F43),
        onColor: Color(hex: 0x2B1A00),
        onSecondary: Color(hex: 0x5C3600),
        onAccent: Color(hex: 0x2B1A00),
        mark: Color(light: 0xA65A00, dark: 0xFFB877, lightHigh: 0x7A4200, darkHigh: 0xFFD0A3),
        icon: "cup.and.saucer.fill",
        label: "休憩")

    static func of(_ t: BlockType) -> BlockStyle { t == .study ? study : rest }
}

/// The small shape that stands for a block type in lists and legends: a tall
/// bar for study, a dot for rest.
struct BlockMark: View {
    let type: BlockType
    var color: Color? = nil
    var height: CGFloat = 22

    var body: some View {
        let style = BlockStyle.of(type)
        Group {
            if type == .study {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color ?? style.mark)
                    .frame(width: 10, height: height)
                    .frame(width: 12)
            } else {
                Circle()
                    .fill(BlockStyle.rest.color)
                    .overlay(Circle().strokeBorder(BlockStyle.rest.mark, lineWidth: 1.5))
                    .frame(width: 12, height: 12)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
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

/// A rounded content-layer card (solid, not Liquid Glass: glass is reserved
/// for controls floating above content).
struct Card<Content: View>: View {
    var padding: CGFloat = 24
    var fill: Color = Theme.surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: 28))
    }
}

extension View {
    /// Keeps the scroll view full width (so its background and edge scrolling
    /// reach the window edges) but centres its content in a readable column
    /// on a large landscape iPad.
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        modifier(ReadableContentMargins(maxWidth: maxWidth))
    }
}

private struct ReadableContentMargins: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

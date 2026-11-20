import StudyCore
import SwiftUI

/// Study = deep, calm navy; rest = bright yellow. Shape (icon, band height)
/// differs too, not only color.
struct BlockStyle {
    /// Large fills, with `onColor` content on them.
    let color: Color
    let onColor: Color
    /// Lines and bars drawn on the dark surface (≥ 3:1 contrast).
    let mark: Color
    let icon: String
    let label: String

    static let study = BlockStyle(
        color: Color(hex: 0x2E3A8C), onColor: Color(hex: 0xE8EAFF), mark: Color(hex: 0x8C9EFF),
        icon: "book.fill", label: "勉強")
    static let rest = BlockStyle(
        color: Color(hex: 0xFFC857), onColor: Color(hex: 0x3A2A00), mark: Color(hex: 0xFFC857),
        icon: "cup.and.saucer.fill", label: "休憩")

    static func of(_ t: BlockType) -> BlockStyle { t == .study ? study : rest }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Caps content width and centres it, so lists do not stretch across a large
/// landscape iPad.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 760

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

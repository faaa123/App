import StudyCore
import SwiftUI

/// Block colors follow the Cupertino design system (design/cupertino):
/// system colors used by meaning, so dark mode and Increase Contrast come
/// from the OS. Study = indigo (the HIG's category color for focus), rest =
/// teal. Shape (bar vs dot, band height, icon) differs too, so color is never
/// the only cue. The accent (blue) stays for buttons, selection and links.
struct BlockStyle {
    /// Fills, and marks drawn on the page or a card.
    let color: Color
    /// Content on a `color` fill.
    let onColor: Color
    let icon: String
    let label: String

    /// Lines, bars and icons on the page (the same system color).
    var mark: Color { color }

    static let study = BlockStyle(color: .indigo, onColor: .white, icon: "book.fill", label: "勉強")
    static let rest = BlockStyle(color: .teal, onColor: .black, icon: "cup.and.saucer.fill", label: "休憩")

    static func of(_ t: BlockType) -> BlockStyle { t == .study ? study : rest }
}

/// The small shape that stands for a block type in lists and legends: a tall
/// bar for study, a dot for rest.
struct BlockMark: View {
    let type: BlockType
    var color: Color? = nil
    var height: CGFloat = 22

    var body: some View {
        let fill = color ?? BlockStyle.of(type).color
        Group {
            if type == .study {
                Capsule()
                    .fill(fill)
                    .frame(width: 8, height: height)
            } else {
                Circle()
                    .fill(fill)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 12, height: height)
        .accessibilityHidden(true)
    }
}

/// A content-layer card: a grouped section's background and corner radius
/// (`bg-grouped-secondary`, `radius-lg`). No glass, no shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
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

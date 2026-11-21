import StudyCore
import SwiftUI

/// Block colors follow the Cupertino design system (design/cupertino) with
/// no hue at all, and little difference: a study block is an ordinary card
/// (grouped secondary background) with ink marks, a rest block a light
/// system gray card with gray marks. The accent (blue) stays for buttons,
/// selection and links. Shape (bar vs dot, band height), icon and label tell
/// the two apart, never color alone.
struct BlockStyle {
    /// Large fills (the Now card, the running row).
    let color: Color
    /// Content on a `color` fill.
    let onColor: Color
    /// Lines, bars and dots drawn on the page or a card.
    let mark: Color
    let icon: String
    let label: String

    static let study = BlockStyle(color: Color(.secondarySystemGroupedBackground), onColor: .primary,
                                  mark: Color(.label), icon: "book.fill", label: "勉強")
    static let rest = BlockStyle(color: Color(.systemGray5), onColor: .primary,
                                 mark: Color(.systemGray3), icon: "cup.and.saucer.fill", label: "休憩")

    /// Background of the running block's row in lists (either type), so it
    /// stands out from the white rows around it.
    static let currentRow = Color(.systemGray5)

    static func of(_ t: BlockType) -> BlockStyle { t == .study ? study : rest }
}

/// The small shape that stands for a block type in lists and legends: a tall
/// bar for study, a dot for rest.
struct BlockMark: View {
    let type: BlockType
    var color: Color? = nil
    var height: CGFloat = 22

    var body: some View {
        let fill = color ?? BlockStyle.of(type).mark
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

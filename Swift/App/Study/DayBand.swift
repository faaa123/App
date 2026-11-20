import StudyCore
import SwiftUI

/// Today's blocks as one horizontal band: past = filled, current = partly
/// filled, future = outlined, free time = empty gap, rest = half height.
/// `blocks` must be sorted by start (as `StudyController.blocks` is).
struct DayBand: View {
    let blocks: [Block]
    let nowOffset: Int

    /// Distance kept between label centres (and from the end labels).
    private static let minLabelGap: CGFloat = 56

    var body: some View {
        let from = blocks.first!.start, to = blocks.last!.end
        VStack(spacing: 6) {
            Canvas { ctx, size in draw(ctx, size, from: from, to: to) }
                .frame(height: 40)
                .accessibilityElement()
                .accessibilityLabel("本日 \(LogicalDay.clock(from))〜\(LogicalDay.clock(to))、\(blocks.count)ブロック")
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    HStack {
                        Text(LogicalDay.clock(from))
                        Spacer()
                        Text(LogicalDay.clock(to))
                    }
                    ForEach(marks(from: from, to: to, width: w)) { m in
                        Text(LogicalDay.clock(m.id))
                            .font(.caption2)
                            .fixedSize()
                            .position(x: m.x, y: 8)
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(height: 18)
        }
    }

    /// Clock labels every 2 or 3 hours, dropped where they would crowd a
    /// neighbour or the start / end labels.
    private struct Mark: Identifiable {
        let x: CGFloat
        /// The hour's offset.
        let id: Int
    }

    private func marks(from: Int, to: Int, width w: CGFloat) -> [Mark] {
        let step = (to - from) > 12 * 60 ? 3 : 2
        var out: [Mark] = []
        var last: CGFloat = 0
        for h in hourOffsets(from, to) where LogicalDay.clockParts(h).hour % step == 0 {
            let x = CGFloat(h - from) / CGFloat(to - from) * w
            if x - last < Self.minLabelGap || w - x < Self.minLabelGap { continue }
            out.append(Mark(x: x, id: h))
            last = x
        }
        return out
    }

    /// Full hours strictly between from and to (the logical day starts on the
    /// hour, so they are the multiples of 60).
    private func hourOffsets(_ from: Int, _ to: Int) -> StrideTo<Int> {
        stride(from: (from / 60 + 1) * 60, to: to, by: 60)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, from: Int, to: Int) {
        let span = CGFloat(to - from)
        func x(_ o: Int) -> CGFloat { CGFloat(o - from) / span * size.width }
        // Faint hour ticks behind the blocks.
        for h in hourOffsets(from, to) {
            var p = Path()
            p.move(to: CGPoint(x: x(h), y: 0))
            p.addLine(to: CGPoint(x: x(h), y: size.height))
            ctx.stroke(p, with: .color(.white.opacity(0.25)), lineWidth: 1)
        }
        for b in blocks {
            let color = BlockStyle.of(b.type).mark
            // Shape tells study and rest apart too: rest is half height.
            let rest = b.type == .rest
            let top = rest ? size.height * 0.25 : 0
            let bottom = rest ? size.height * 0.75 : size.height
            let rect = CGRect(x: x(b.start) + 1, y: top, width: max(x(b.end) - x(b.start) - 2, 1), height: bottom - top)
            let shape = Path(roundedRect: rect, cornerRadius: 6)
            // Future part: faint fill + outline.
            ctx.fill(shape, with: .color(color.opacity(0.18)))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 5),
                       with: .color(color.opacity(0.7)), lineWidth: 2)
            // Done part.
            let doneEnd = nowOffset >= b.end ? b.end : max(nowOffset, b.start)
            if doneEnd > b.start {
                var c = ctx
                c.clip(to: Path(CGRect(x: 0, y: top, width: x(doneEnd), height: bottom - top)))
                c.fill(shape, with: .color(color))
            }
        }
        if nowOffset >= from && nowOffset <= to {
            var p = Path()
            p.move(to: CGPoint(x: x(nowOffset), y: -4))
            p.addLine(to: CGPoint(x: x(nowOffset), y: size.height + 4))
            ctx.stroke(p, with: .color(.white), lineWidth: 2)
        }
    }
}

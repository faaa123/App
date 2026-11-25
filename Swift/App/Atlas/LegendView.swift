import GeoCore
import SwiftUI

/// The key for one theme, floating over the map's corner.
struct LegendView: View {
    var theme: Theme
    var season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
            content
        }
        .font(.caption)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        theme == .winds ? "\(theme.title)（\(season.name)）" : theme.title
    }

    @ViewBuilder private var content: some View {
        switch theme {
        case .plates:
            ForEach(PlateBoundaryKind.allCases, id: \.self) { k in
                row(LineSwatch(color: MapStyle.plate(k), style: MapStyle.plateStroke(k)),
                    "\(k.name)（\(k.examples)）")
            }
        case .climate:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(KoppenClass.allCases, id: \.self) { c in
                    GridRow {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(MapStyle.koppen(c))
                            .frame(width: 22, height: 13)
                        Text(c.code).monospaced().fontWeight(.semibold)
                        Text(c.name).foregroundStyle(.secondary)
                    }
                }
            }
        case .currents:
            row(ArrowSwatch(color: MapStyle.current(warm: true)), "暖流")
            row(ArrowSwatch(color: MapStyle.current(warm: false)), "寒流")
            Text("模式図（教科書の図をもとに簡略化）").font(.caption2).foregroundStyle(.secondary)
        case .winds:
            row(BandSwatch(color: MapStyle.pressure(.low)), "低圧帯")
            row(BandSwatch(color: MapStyle.pressure(.high)), "高圧帯")
            row(ArrowSwatch(color: MapStyle.wind(.trade)), "恒常風（貿易風・偏西風・極偏東風）")
            row(ArrowSwatch(color: MapStyle.wind(.monsoon)), "季節風（モンスーン）")
            Text("模式図。気圧帯は夏の半球側へ移る").font(.caption2).foregroundStyle(.secondary)
        case .landforms:
            row(BandSwatch(color: MapStyle.orogeny(.young)), OrogenyAge.young.name)
            row(BandSwatch(color: MapStyle.orogeny(.old)), OrogenyAge.old.name)
            row(LineSwatch(color: MapStyle.range, style: StrokeStyle(lineWidth: 3, lineCap: .round)), "主な山脈")
            row(LineSwatch(color: MapStyle.river, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)), "主な河川")
        }
    }

    private func row(_ swatch: some View, _ text: String) -> some View {
        HStack(spacing: 8) {
            swatch.frame(width: 28, height: 14)
            Text(text)
        }
    }
}

private struct LineSwatch: View {
    var color: Color
    var style: StrokeStyle

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 2, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            ctx.stroke(p, with: .color(color), style: style)
        }
    }
}

private struct ArrowSwatch: View {
    var color: Color

    var body: some View {
        Image(systemName: "arrow.right")
            .fontWeight(.bold)
            .foregroundStyle(color)
    }
}

private struct BandSwatch: View {
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(height: 13)
    }
}

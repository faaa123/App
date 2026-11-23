import GeoCore
import SwiftUI

/// Map colors and line styles. Thematic colors have no system equivalent,
/// so they are tints of the system palette (which adapts per OS release).
/// The map itself is always drawn in the light appearance: an atlas's white
/// paper.
enum MapStyle {
    static let paper = Color(.systemBackground)
    static let surround = Color(.secondarySystemBackground)
    static let coast = Color(.label)
    static let border = Color(.systemGray2)
    static let graticule = Color(.systemGray5)
    static let equator = Color(.systemGray3)
    static let river = Color.blue
    static let labelHalo = Color(.systemBackground)

    static func plate(_ k: PlateBoundaryKind) -> Color {
        switch k {
        case .divergent: .red
        case .convergent: .blue
        case .transform: .green
        }
    }

    /// Line styles differ too, so the kinds read without color.
    static func plateStroke(_ k: PlateBoundaryKind) -> StrokeStyle {
        switch k {
        case .divergent: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        case .convergent: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        case .transform: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 3])
        }
    }

    static func koppen(_ c: KoppenClass) -> Color {
        switch c {
        case .af: Color.red.opacity(0.85)
        case .am: Color.red.opacity(0.55)
        case .aw: Color.orange.opacity(0.6)
        case .bw: Color.yellow.opacity(0.85)
        case .bs: Color.yellow.opacity(0.4)
        case .cs: Color.green.opacity(0.35)
        case .cw: Color.mint.opacity(0.6)
        case .cfa: Color.green.opacity(0.75)
        case .cfb: Color.teal.opacity(0.45)
        case .df: Color.blue.opacity(0.5)
        case .dw: Color.purple.opacity(0.55)
        case .et: Color(.systemGray).opacity(0.45)
        case .ef: Color(.systemGray).opacity(0.15)
        }
    }

    static func current(warm: Bool) -> Color { warm ? .red : .blue }

    static func pressure(_ k: PressureKind) -> Color {
        k == .low ? Color.orange.opacity(0.22) : Color.blue.opacity(0.14)
    }

    static func pressureText(_ k: PressureKind) -> Color {
        k == .low ? .orange : .blue
    }

    static func wind(_ k: WindKind) -> Color {
        k == .monsoon ? .purple : Color(.secondaryLabel)
    }

    static func orogeny(_ a: OrogenyAge) -> Color {
        a == .young ? Color.orange.opacity(0.3) : Color.green.opacity(0.3)
    }

    static let range = Color.brown
}

import Foundation

/// The five maps, one per tab.
public enum Theme: String, CaseIterable, Sendable, Identifiable {
    case plates
    case climate
    case currents
    case winds
    case landforms

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plates: "プレート境界"
        case .climate: "ケッペンの気候区分"
        case .currents: "海流"
        case .winds: "恒常風と気圧帯"
        case .landforms: "山脈・河川と造山帯"
        }
    }

    public var tabTitle: String {
        switch self {
        case .plates: "プレート"
        case .climate: "気候区分"
        case .currents: "海流"
        case .winds: "風・気圧帯"
        case .landforms: "地形"
        }
    }

    public var symbol: String {
        switch self {
        case .plates: "square.split.diagonal.2x2"
        case .climate: "thermometer.sun"
        case .currents: "water.waves"
        case .winds: "wind"
        case .landforms: "mountain.2"
        }
    }
}

public enum PlateBoundaryKind: String, CaseIterable, Sendable {
    case divergent
    case convergent
    case transform

    public var name: String {
        switch self {
        case .divergent: "広がる境界"
        case .convergent: "狭まる境界"
        case .transform: "ずれる境界"
        }
    }

    public var examples: String {
        switch self {
        case .divergent: "海嶺・地溝帯"
        case .convergent: "海溝・衝突帯"
        case .transform: "トランスフォーム断層"
        }
    }
}

/// The groups used in Japanese high-school geography.
public enum KoppenClass: String, CaseIterable, Sendable {
    case af = "Af", am = "Am", aw = "Aw"
    case bs = "BS", bw = "BW"
    case cs = "Cs", cw = "Cw", cfa = "Cfa", cfb = "Cfb"
    case df = "Df", dw = "Dw"
    case et = "ET", ef = "EF"

    public var code: String { rawValue }

    public var name: String {
        switch self {
        case .af: "熱帯雨林気候"
        case .am: "熱帯モンスーン気候"
        case .aw: "サバナ気候"
        case .bs: "ステップ気候"
        case .bw: "砂漠気候"
        case .cs: "地中海性気候"
        case .cw: "温暖冬季少雨気候"
        case .cfa: "温暖湿潤気候"
        case .cfb: "西岸海洋性気候"
        case .df: "亜寒帯湿潤気候"
        case .dw: "亜寒帯冬季少雨気候"
        case .et: "ツンドラ気候"
        case .ef: "氷雪気候"
        }
    }

    /// A, B, C, D or E.
    public var group: Character { rawValue.first ?? "A" }
}

/// A labelled point.
public struct MapLabel: Sendable {
    public var text: String
    public var at: GeoPoint

    public init(_ text: String, _ lon: Double, _ lat: Double) {
        self.text = text
        self.at = GeoPoint(lon, lat)
    }
}

public enum PlateNames {
    public static let all: [MapLabel] = [
        MapLabel("ユーラシアプレート", 80, 52),
        MapLabel("北アメリカプレート", -100, 48),
        MapLabel("太平洋プレート", -150, 5),
        MapLabel("フィリピン海プレート", 134, 19),
        MapLabel("インド・オーストラリアプレート", 105, -25),
        MapLabel("アフリカプレート", 15, 5),
        MapLabel("南アメリカプレート", -45, -18),
        MapLabel("ナスカプレート", -92, -20),
        MapLabel("ココスプレート", -98, 8),
        MapLabel("カリブプレート", -75, 14),
        MapLabel("アラビアプレート", 47, 22),
        MapLabel("南極プレート", 30, -72),
    ]
}

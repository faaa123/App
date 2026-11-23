import Foundation

/// A schematic ocean current, drawn as a smooth arrow through `path`.
public struct OceanCurrent: Sendable {
    public var name: String
    public var warm: Bool
    /// Control points in flow order. Longitudes run on past ±180 where a
    /// current crosses the date line.
    public var path: [GeoPoint]

    public init(_ name: String, warm: Bool, _ path: [(Double, Double)]) {
        self.name = name
        self.warm = warm
        self.path = path.map { GeoPoint($0.0, $0.1) }
    }

    /// Where the name goes: the middle control point.
    public var labelPoint: GeoPoint { path[path.count / 2] }
}

/// Textbook-level schematic of the main surface currents (not survey data).
public enum OceanCurrents {
    public static let all: [OceanCurrent] = [
        // North Pacific
        OceanCurrent("北赤道海流", warm: true, [(250, 12), (220, 13), (190, 14), (160, 14), (135, 14), (126, 15)]),
        OceanCurrent("黒潮（日本海流）", warm: true, [(124, 19), (122, 24), (126, 28), (131, 31), (137, 33.5), (142, 35.5), (150, 37)]),
        OceanCurrent("対馬海流", warm: true, [(127, 32), (130, 35), (134, 37.5), (139, 41)]),
        OceanCurrent("北太平洋海流", warm: true, [(153, 40), (170, 42), (190, 43), (210, 44), (228, 45)]),
        OceanCurrent("アラスカ海流", warm: true, [(229, 49), (224, 55), (214, 58.5), (203, 57)]),
        OceanCurrent("カリフォルニア海流", warm: false, [(232, 46), (235, 40), (240, 33), (246, 25)]),
        OceanCurrent("親潮（千島海流）", warm: false, [(164, 58), (158, 51), (150, 45), (145, 41)]),
        OceanCurrent("リマン海流", warm: false, [(141, 50), (137, 45), (132, 42)]),
        OceanCurrent("赤道反流", warm: true, [(130, 6), (160, 7), (190, 7), (220, 7), (260, 7)]),
        // South Pacific
        OceanCurrent("南赤道海流", warm: true, [(278, -3), (250, -6), (220, -9), (190, -12), (160, -13)]),
        OceanCurrent("東オーストラリア海流", warm: true, [(156, -15), (154, -22), (154, -30), (152, -37)]),
        OceanCurrent("ペルー海流（フンボルト海流）", warm: false, [(-76, -44), (-75, -32), (-77, -20), (-82, -7)]),
        // North Atlantic
        OceanCurrent("北赤道海流", warm: true, [(-20, 17), (-38, 15), (-56, 15)]),
        OceanCurrent("メキシコ湾流", warm: true, [(-81, 25), (-79, 30), (-75, 35), (-67, 39), (-54, 41)]),
        OceanCurrent("北大西洋海流", warm: true, [(-48, 44), (-35, 48), (-20, 53), (-8, 59), (4, 64), (15, 70)]),
        OceanCurrent("カナリア海流", warm: false, [(-16, 40), (-14, 32), (-18, 24), (-22, 19)]),
        OceanCurrent("ラブラドル海流", warm: false, [(-62, 66), (-57, 58), (-52, 51), (-50, 45)]),
        OceanCurrent("東グリーンランド海流", warm: false, [(-12, 78), (-20, 71), (-33, 64), (-42, 60)]),
        OceanCurrent("ギニア海流", warm: true, [(-17, 7), (-6, 4), (5, 3)]),
        // South Atlantic
        OceanCurrent("南赤道海流", warm: true, [(8, -3), (-10, -4), (-25, -6), (-33, -7)]),
        OceanCurrent("ブラジル海流", warm: true, [(-35, -10), (-38, -17), (-41, -23), (-47, -31), (-52, -38)]),
        OceanCurrent("ベンゲラ海流", warm: false, [(17, -36), (13, -28), (11, -20), (8, -12)]),
        OceanCurrent("フォークランド海流", warm: false, [(-65, -54), (-60, -47), (-56, -40)]),
        // Indian Ocean
        OceanCurrent("南赤道海流", warm: true, [(110, -14), (90, -14), (70, -13), (52, -13)]),
        OceanCurrent("アガラス海流", warm: true, [(42, -14), (37, -24), (31, -32), (22, -36)]),
        OceanCurrent("西オーストラリア海流", warm: false, [(113, -36), (113, -28), (109, -20)]),
        // Southern Ocean: four arrows round the pole.
        OceanCurrent("南極環流（西風海流）", warm: false, [(-60, -58), (-35, -53), (-10, -48), (10, -46)]),
        OceanCurrent("南極環流（西風海流）", warm: false, [(20, -45), (50, -46), (80, -47), (110, -48)]),
        OceanCurrent("南極環流（西風海流）", warm: false, [(120, -50), (145, -51), (170, -54), (195, -56)]),
        OceanCurrent("南極環流（西風海流）", warm: false, [(205, -57), (235, -58), (265, -59), (290, -59)]),
    ]
}


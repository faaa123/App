import Foundation

public enum OrogenyAge: Sendable {
    /// 新期造山帯 (Alpine-Himalayan and Circum-Pacific belts)
    case young
    /// 古期造山帯
    case old

    public var name: String { self == .young ? "新期造山帯" : "古期造山帯" }
}

/// A belt drawn as a broad band along `path`.
public struct OrogenicBelt: Sendable {
    public var age: OrogenyAge
    public var path: [GeoPoint]
    /// Band width in degrees of latitude.
    public var width: Double

    init(_ age: OrogenyAge, width: Double, _ path: [(Double, Double)]) {
        self.age = age
        self.width = width
        self.path = path.map { GeoPoint($0.0, $0.1) }
    }
}

/// A named mountain range drawn along `path`.
public struct MountainRange: Sendable {
    public var name: String
    public var age: OrogenyAge
    public var path: [GeoPoint]

    init(_ name: String, _ age: OrogenyAge, _ path: [(Double, Double)]) {
        self.name = name
        self.age = age
        self.path = path.map { GeoPoint($0.0, $0.1) }
    }

    public var labelPoint: GeoPoint { path[path.count / 2] }
}

/// Textbook-level schematic of the orogenic belts and main ranges.
public enum Landforms {
    public static let belts: [OrogenicBelt] = [
        // Alpine-Himalayan belt
        OrogenicBelt(.young, width: 7, [(-9, 32), (-2, 35), (6, 40), (12, 45), (20, 43), (28, 40), (38, 39),
                                        (46, 37), (53, 31), (62, 31), (70, 35), (78, 33), (88, 29), (96, 26),
                                        (98, 16), (99, 6), (102, -3), (110, -8), (122, -9)]),
        // Circum-Pacific belt: the Americas ...
        OrogenicBelt(.young, width: 9, [(-71, -53), (-72, -42), (-70, -30), (-69, -20), (-76, -10), (-78, 0),
                                        (-75, 8), (-83, 10), (-92, 15), (-103, 20), (-108, 28), (-111, 36),
                                        (-116, 44), (-122, 52), (-132, 58), (-145, 61), (-155, 59),
                                        (-165, 55), (-178, 52)]),
        // ... and the western Pacific, from the Aleutians to New Zealand.
        OrogenicBelt(.young, width: 6, [(182, 52), (165, 55), (158, 52), (150, 46), (144, 42), (140, 37),
                                        (135, 34), (130, 31), (126, 25), (121, 18), (124, 10), (126, 4),
                                        (131, -2), (140, -5), (150, -7), (160, -10), (168, -16), (177, -22),
                                        (178, -36), (173, -41), (168, -46)]),
        OrogenicBelt(.old, width: 6, [(-86, 33), (-81, 37), (-76, 41), (-70, 45), (-63, 48)]),
        OrogenicBelt(.old, width: 5, [(59, 50), (59, 57), (60, 63), (64, 68)]),
        OrogenicBelt(.old, width: 5, [(6, 59), (9, 62), (14, 66), (19, 69), (25, 70)]),
        OrogenicBelt(.old, width: 6, [(145, -14), (147, -20), (150, -27), (151, -32), (147, -37)]),
        OrogenicBelt(.old, width: 4, [(27, -26), (29, -29), (28, -32), (24, -33)]),
        OrogenicBelt(.old, width: 5, [(70, 41), (76, 42), (82, 43), (88, 43), (95, 43)]),
        OrogenicBelt(.old, width: 4, [(85, 51), (90, 49), (96, 47)]),
    ]

    public static let ranges: [MountainRange] = [
        MountainRange("ロッキー山脈", .young, [(-124, 60), (-117, 53), (-112, 47), (-107, 40), (-106, 33)]),
        MountainRange("アンデス山脈", .young, [(-73, 10), (-77, 2), (-77, -8), (-70, -18), (-69, -30), (-71, -42), (-72, -50)]),
        MountainRange("アルプス山脈", .young, [(6, 44), (8, 46), (11, 47), (15, 47)]),
        MountainRange("アトラス山脈", .young, [(-9, 31), (-4, 33), (3, 35), (9, 36)]),
        MountainRange("カフカス山脈", .young, [(38, 44), (44, 43), (49, 41)]),
        MountainRange("ザグロス山脈", .young, [(45, 36), (49, 33), (53, 29), (57, 27)]),
        MountainRange("ヒマラヤ山脈", .young, [(73, 36), (78, 33), (84, 29), (90, 28), (95, 28)]),
        MountainRange("アパラチア山脈", .old, [(-86, 34), (-81, 37), (-77, 40), (-72, 44)]),
        MountainRange("ウラル山脈", .old, [(59, 51), (59, 57), (60, 63), (65, 68)]),
        MountainRange("スカンディナヴィア山脈", .old, [(7, 59), (10, 62), (14, 65.5), (19, 69)]),
        MountainRange("グレートディヴァイディング山脈", .old, [(145, -15), (147, -21), (150, -27), (151, -32), (147, -37)]),
        MountainRange("ドラケンスバーグ山脈", .old, [(30, -26), (29.5, -29), (27.5, -31)]),
        MountainRange("テンシャン山脈", .old, [(70, 41), (76, 42), (82, 43), (88, 43), (94, 43)]),
    ]
}

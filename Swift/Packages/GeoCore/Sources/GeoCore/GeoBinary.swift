import Foundation

/// The compact format of the zoomed-in detail (Tools/build_geodata.py
/// writes it): JSON would take seconds to parse at this size.
///
/// Little endian: `GEOB`, u32 feature count; per feature u32 part count;
/// per part u32 point count, then float32 lon, lat pairs.
public enum GeoBinary {
    public enum DecodeError: Error, Equatable {
        case badHeader
        case truncated
    }

    public static func decode(_ data: Data) throws -> [GeoFeature] {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var at = 0
            func u32() throws -> Int {
                guard at + 4 <= raw.count else { throw DecodeError.truncated }
                let v = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                at += 4
                return Int(v)
            }
            func f32() -> Double {
                let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                at += 4
                return Double(Float(bitPattern: bits))
            }
            guard raw.count >= 4, Array(raw[0..<4]) == Array("GEOB".utf8) else { throw DecodeError.badHeader }
            at = 4
            let featureCount = try u32()
            var features: [GeoFeature] = []
            features.reserveCapacity(featureCount)
            for _ in 0..<featureCount {
                let partCount = try u32()
                var parts: [[GeoPoint]] = []
                parts.reserveCapacity(partCount)
                for _ in 0..<partCount {
                    let n = try u32()
                    guard at + n * 8 <= raw.count else { throw DecodeError.truncated }
                    var part: [GeoPoint] = []
                    part.reserveCapacity(n)
                    for _ in 0..<n {
                        let lon = f32()
                        part.append(GeoPoint(lon, f32()))
                    }
                    parts.append(part)
                }
                features.append(GeoFeature(parts: parts))
            }
            return features
        }
    }

    /// The inverse of `decode`, for tests and tools.
    public static func encode(_ features: [GeoFeature]) -> Data {
        var d = Data("GEOB".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func f32(_ v: Double) { withUnsafeBytes(of: Float(v).bitPattern.littleEndian) { d.append(contentsOf: $0) } }
        u32(features.count)
        for f in features {
            u32(f.parts.count)
            for part in f.parts {
                u32(part.count)
                for p in part {
                    f32(p.lon)
                    f32(p.lat)
                }
            }
        }
        return d
    }
}

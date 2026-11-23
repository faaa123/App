// swift-tools-version: 6.0
import PackageDescription

// Map math and atlas data for GeoAtlas: no UIKit/SwiftUI, so `swift test`
// runs on Linux too.
let package = Package(
    name: "GeoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GeoCore", targets: ["GeoCore"]),
    ],
    targets: [
        .target(name: "GeoCore"),
        .testTarget(name: "GeoCoreTests", dependencies: ["GeoCore"]),
    ]
)

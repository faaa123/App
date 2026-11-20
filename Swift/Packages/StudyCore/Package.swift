// swift-tools-version: 6.0
import PackageDescription

// Pure Swift study logic: no UIKit/SwiftUI, so `swift test` runs on
// Linux and Windows too.
let package = Package(
    name: "StudyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StudyCore", targets: ["StudyCore"]),
    ],
    targets: [
        .target(name: "StudyCore"),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"]),
    ]
)

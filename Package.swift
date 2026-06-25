// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dont-die-on-me-now",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "DontDieOnMeNow",
            targets: ["DontDieOnMeNow"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "DontDieOnMeNow"
        ),
        .testTarget(
            name: "DontDieOnMeNowTests",
            dependencies: ["DontDieOnMeNow"]
        ),
    ]
)


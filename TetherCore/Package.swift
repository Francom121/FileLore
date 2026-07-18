// swift-tools-version: 6.0
// TetherCore is the shared engine for the FileLore app (module name kept to avoid churn).
import PackageDescription

let package = Package(
    name: "TetherCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TetherCore", targets: ["TetherCore"]),
    ],
    targets: [
        .target(
            name: "TetherCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TetherCoreTests",
            dependencies: ["TetherCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

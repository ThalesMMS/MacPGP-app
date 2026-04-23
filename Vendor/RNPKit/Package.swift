// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RNPKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RNPKit",
            targets: ["RNPKit"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "RNPBridge",
            path: "../RNPBridge/RNPBridge.xcframework"
        ),
        .target(
            name: "RNPKit",
            dependencies: ["RNPBridge"],
            linkerSettings: [
                .linkedLibrary("bz2"),
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z"),
                .linkedFramework("Security")
            ]
        )
    ]
)

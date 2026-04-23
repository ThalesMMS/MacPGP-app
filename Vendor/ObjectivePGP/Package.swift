// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ObjectivePGP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ObjectivePGP",
            targets: ["ObjectivePGP"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "RNPBridge",
            path: "../RNPBridge/RNPBridge.xcframework"
        ),
        .target(
            name: "ObjectivePGP",
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

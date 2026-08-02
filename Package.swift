// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenFree",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenFree", targets: ["ScreenFree"]),
        .library(name: "ScreenFreeCore", targets: ["ScreenFreeCore"])
    ],
    targets: [
        .target(name: "ScreenFreeCore"),
        .executableTarget(
            name: "ScreenFree",
            dependencies: ["ScreenFreeCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ScreenFreeCoreTests",
            dependencies: ["ScreenFreeCore"]
        ),
        .testTarget(
            name: "ScreenFreeMediaTests",
            dependencies: ["ScreenFree", "ScreenFreeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)

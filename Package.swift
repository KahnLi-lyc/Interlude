// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interlude",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "Interlude", targets: ["Interlude"])
    ],
    targets: [
        .target(
            name: "Interlude",
            path: "Sources/Interlude",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "InterludeTests",
            dependencies: ["Interlude"],
            path: "Tests/InterludeTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

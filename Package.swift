// swift-tools-version: 6.2
import PackageDescription

// 依存の向きはこのファイルのターゲットの依存関係で強制する。違反はコンパイルエラーになる。
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Barlunari",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BarlunariApp", targets: ["BarlunariApp"]),
        .executable(name: "barlunari-snapshots", targets: ["barlunari-snapshots"]),
        .executable(name: "barlunari-ui-driver", targets: ["barlunari-ui-driver"]),
    ],
    targets: [
        .target(name: "BarlunariDomain", swiftSettings: swiftSettings),
        .target(
            name: "BarlunariApplication",
            dependencies: ["BarlunariDomain"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "BarlunariInfrastructure",
            dependencies: ["BarlunariDomain", "BarlunariApplication"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "BarlunariPresentation",
            dependencies: ["BarlunariDomain", "BarlunariApplication"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "BarlunariPreviewSupport",
            dependencies: ["BarlunariDomain", "BarlunariApplication"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "BarlunariApp",
            dependencies: [
                "BarlunariDomain",
                "BarlunariApplication",
                "BarlunariInfrastructure",
                "BarlunariPresentation",
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "barlunari-snapshots",
            dependencies: [
                "BarlunariDomain",
                "BarlunariApplication",
                "BarlunariPresentation",
                "BarlunariPreviewSupport",
            ],
            path: "Sources/barlunari-snapshots",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "barlunari-ui-driver",
            dependencies: [
                "BarlunariDomain",
                "BarlunariApplication",
                "BarlunariPresentation",
                "BarlunariPreviewSupport",
            ],
            path: "Sources/barlunari-ui-driver",
            swiftSettings: swiftSettings
        ),

        .testTarget(
            name: "BarlunariDomainTests",
            dependencies: ["BarlunariDomain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BarlunariApplicationTests",
            dependencies: ["BarlunariDomain", "BarlunariApplication", "BarlunariPreviewSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BarlunariInfrastructureTests",
            dependencies: [
                "BarlunariDomain",
                "BarlunariApplication",
                "BarlunariInfrastructure",
                "BarlunariPreviewSupport",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BarlunariPresentationTests",
            dependencies: [
                "BarlunariDomain",
                "BarlunariApplication",
                "BarlunariPresentation",
                "BarlunariPreviewSupport",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

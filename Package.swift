// swift-tools-version: 6.2
import PackageDescription

// 依存の向きはこのファイルのターゲットの依存関係で強制する。違反はコンパイルエラーになる。
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "MenuDate",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MenuDateApp", targets: ["MenuDateApp"]),
        .executable(name: "menudate-snapshots", targets: ["menudate-snapshots"]),
        .executable(name: "menudate-ui-driver", targets: ["menudate-ui-driver"]),
    ],
    targets: [
        .target(name: "MenuDateDomain", swiftSettings: swiftSettings),
        .target(
            name: "MenuDateApplication",
            dependencies: ["MenuDateDomain"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MenuDateInfrastructure",
            dependencies: ["MenuDateDomain", "MenuDateApplication"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MenuDatePresentation",
            dependencies: ["MenuDateDomain", "MenuDateApplication"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MenuDatePreviewSupport",
            dependencies: ["MenuDateDomain", "MenuDateApplication"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "MenuDateApp",
            dependencies: [
                "MenuDateDomain",
                "MenuDateApplication",
                "MenuDateInfrastructure",
                "MenuDatePresentation",
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "menudate-snapshots",
            dependencies: [
                "MenuDateDomain",
                "MenuDateApplication",
                "MenuDatePresentation",
                "MenuDatePreviewSupport",
            ],
            path: "Sources/menudate-snapshots",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "menudate-ui-driver",
            dependencies: [
                "MenuDateDomain",
                "MenuDateApplication",
                "MenuDatePresentation",
                "MenuDatePreviewSupport",
            ],
            path: "Sources/menudate-ui-driver",
            swiftSettings: swiftSettings
        ),

        .testTarget(
            name: "MenuDateDomainTests",
            dependencies: ["MenuDateDomain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MenuDateApplicationTests",
            dependencies: ["MenuDateDomain", "MenuDateApplication", "MenuDatePreviewSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MenuDateInfrastructureTests",
            dependencies: [
                "MenuDateDomain",
                "MenuDateApplication",
                "MenuDateInfrastructure",
                "MenuDatePreviewSupport",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MenuDatePresentationTests",
            dependencies: [
                "MenuDateDomain",
                "MenuDateApplication",
                "MenuDatePresentation",
                "MenuDatePreviewSupport",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

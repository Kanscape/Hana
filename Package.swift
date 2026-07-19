// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanaDisciplineMode",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "DisciplineModeCore", targets: ["DisciplineModeCore"])
    ],
    targets: [
        .target(
            name: "DisciplineModeCore",
            path: "Hana",
            exclude: [
                "AppIcon.icon",
                "Assets.xcassets",
                "Config",
                "ContentView.swift",
                "Hana.entitlements",
                "HanaApp.swift",
                "Models/DownloadGroupExpansionState.swift",
                "Models/HanaBackupArchive.swift",
                "PrivacyInfo.xcprivacy",
                "Models/HanaSettings.swift",
                "Models/HanimeModels.swift",
                "Models/LocalFeatureModels.swift",
                "Models/PersistenceModels.swift",
                "Resources",
                "Services/Core/DisciplineModeStore.swift",
                "Services/Core/HanaBackupCodec.swift",
                "Services/Core/HanaBackupService.swift",
                "Services/Core/HanaInterfaceOrientationController.swift",
                "Services/Core/HanaServiceReloadAction.swift",
                "Services/Core/HanaServices.swift",
                "Services/Downloads",
                "Services/Hanime",
                "Services/Media",
                "Services/Network",
                "Services/Profile",
                "Services/Updates",
                "Views"
            ],
            sources: [
                "Models/DisciplineModeConfiguration.swift",
                "Services/Core/DisciplineModeEvaluator.swift"
            ]
        ),
        .testTarget(
            name: "DisciplineModeCoreTests",
            dependencies: ["DisciplineModeCore"],
            path: "Tests/DisciplineModeCoreTests"
        )
    ]
)

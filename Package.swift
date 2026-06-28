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
            path: "Hana/Features/DisciplineMode/Core"
        ),
        .testTarget(
            name: "DisciplineModeCoreTests",
            dependencies: ["DisciplineModeCore"],
            path: "Tests/DisciplineModeCoreTests"
        )
    ]
)

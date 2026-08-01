// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwedishTaxCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwedishTaxCore", targets: ["SwedishTaxCore"])
    ],
    targets: [
        .target(
            name: "SwedishTaxCore",
            path: "SwedishTax",
            exclude: [
                "App",
                "Resources/Assets.xcassets"
            ],
            sources: ["Core"],
            resources: [
                .copy("Resources/allmanna-tabeller-manad-2026.txt")
            ]
        ),
        .testTarget(
            name: "SwedishTaxCoreTests",
            dependencies: ["SwedishTaxCore"],
            path: "SwedishTaxTests"
        )
    ]
)

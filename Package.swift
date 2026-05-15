// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DougDomain",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DougDomain", targets: ["DougDomain"]),
    ],
    targets: [
        .target(
            name: "DougDomain",
            path: "Doug",
            exclude: [
                "Views",
                "ViewModels",
                "Services",
                "Theme",
                "Models/SwiftData",
                "DougApp.swift",
                "ContentView.swift",
            ],
            sources: [
                "Domain/",
                "Models/Static/",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DougDomainTests",
            dependencies: ["DougDomain"],
            path: "DougTests/Domain",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

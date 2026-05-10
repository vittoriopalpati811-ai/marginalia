// swift-tools-version: 5.10
// Marginalia iOS library package.
//
// NOTA PER IL MAC: questo Package.swift definisce la business logic.
// All'accesso su Mac, crea un progetto Xcode e aggiungi questo package
// come dipendenza locale. Poi aggiungi due target:
//   1. App target (iOS App) che importa Marginalia
//   2. Widget Extension target che importa MarginaliaWidgets
//
// Vedi ARCHITECTURE.md sezione 6 per i passi dettagliati.

import PackageDescription

let package = Package(
    name: "Marginalia",
    defaultLocalization: "it",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "Marginalia", targets: ["Marginalia"]),
        .library(name: "MarginaliaWidgets", targets: ["MarginaliaWidgets"]),
    ],
    dependencies: [
        // Supabase Swift SDK
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.5.0"
        ),
    ],
    targets: [
        .target(
            name: "Marginalia",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources/Marginalia"
        ),
        .target(
            name: "MarginaliaWidgets",
            dependencies: [
                "Marginalia",
            ],
            path: "Sources/MarginaliaWidgets"
        ),
        .testTarget(
            name: "MarginaliaTests",
            dependencies: ["Marginalia"],
            path: "Tests/MarginaliaTests",
            resources: [
                .copy("../Fixtures"),
            ]
        ),
    ]
)

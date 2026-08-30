// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StockWatchTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StockWatchTool", type: .static, targets: ["StockWatchTool"])
    ],
    traits: [
        .trait(
            name: "Benchmark",
            description: "Expose internal test hooks only to the Release benchmark build"
        )
    ],
    dependencies: [
        .package(path: "../../OneBoxCore"),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        ),
    ],
    targets: [
        .target(
            name: "StockWatchTool",
            dependencies: [
                .product(name: "OneBoxRuntime", package: "OneBoxCore"),
                .product(name: "OneBoxDesignSystem", package: "OneBoxCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
            ],
            exclude: [
                "Resources/Sounds/README.md"
            ],
            resources: [
                .copy("Resources/Sounds/bull-moo.wav"),
                .copy("Resources/Sounds/bear-growl.wav"),
            ],
            swiftSettings: [
                .define(
                    "STOCKWATCH_BENCHMARK",
                    .when(traits: ["Benchmark"])
                )
            ]
        ),
        .testTarget(
            name: "StockWatchToolTests",
            dependencies: [
                "StockWatchTool",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "StockWatchPerformanceTests",
            dependencies: ["StockWatchTool"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

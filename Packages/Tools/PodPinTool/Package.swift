// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PodPinTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PodPinTool", type: .static, targets: ["PodPinTool"])
    ],
    traits: [
        .trait(
            name: "Benchmark",
            description: "Expose the offline Release workspace benchmark target",
        ),
        .trait(
            name: "Testing",
            description: "Expose internal hooks only to explicit Release package tests",
        ),
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
            name: "PodPinTool",
            dependencies: [
                .product(name: "OneBoxRuntime", package: "OneBoxCore"),
                .product(name: "OneBoxDesignSystem", package: "OneBoxCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .define(
                    "PODPIN_BENCHMARK",
                    .when(traits: ["Benchmark"]),
                ),
                .define(
                    "PODPIN_TESTING",
                    .when(traits: ["Testing"]),
                ),
            ],
        ),
        .testTarget(
            name: "PodPinToolTests",
            dependencies: [
                "PodPinTool",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            exclude: [
                "Resources/Fixtures/README.md"
            ],
            resources: [
                .copy("Resources/Fixtures/podpin-sample.m4a")
            ]
        ),
        .testTarget(
            name: "PodPinPerformanceTests",
            dependencies: ["PodPinTool"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.2

import PackageDescription
import _Concurrency

let package = Package(
    name: "OneBoxCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "OneBoxRuntime", type: .static, targets: ["OneBoxRuntime"]),
        .library(
            name: "OneBoxDesignSystem",
            type: .static,
            targets: ["OneBoxDesignSystem"]
        ),
        .library(name: "OneBoxHost", type: .static, targets: ["OneBoxHost"]),
    ],
    targets: [
        .target(name: "OneBoxRuntime"),
        .target(
            name: "OneBoxDesignSystem",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "OneBoxHost",
            dependencies: ["OneBoxRuntime", "OneBoxDesignSystem"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "OneBoxRuntimeTests",
            dependencies: ["OneBoxRuntime"]
        ),
        .testTarget(
            name: "OneBoxDesignSystemTests",
            dependencies: ["OneBoxDesignSystem"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

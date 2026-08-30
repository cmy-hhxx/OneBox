// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AsciiArtTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AsciiArtTool", type: .static, targets: ["AsciiArtTool"])
    ],
    dependencies: [
        .package(path: "../../OneBoxCore")
    ],
    targets: [
        .target(
            name: "AsciiArtTool",
            dependencies: [
                .product(name: "OneBoxRuntime", package: "OneBoxCore"),
                .product(name: "OneBoxDesignSystem", package: "OneBoxCore"),
            ],
            resources: [
                .copy("Resources/onebox-mark-light.png")
            ]
        ),
        .testTarget(
            name: "AsciiArtToolTests",
            dependencies: ["AsciiArtTool"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

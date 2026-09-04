// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownAttributed",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownAttributed", targets: ["MarkdownAttributed"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MarkdownAttributed",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkdownAttributedTests",
            dependencies: [
                "MarkdownAttributed",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Tests"
        ),
    ]
)

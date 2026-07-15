// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownAttributed",
    platforms: [
        .macOS(.v13)
    ],
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
            path: "Sources"
        ),
        .testTarget(name: "MarkdownAttributedTests", dependencies: ["MarkdownAttributed"], path: "Tests"),
    ]
)

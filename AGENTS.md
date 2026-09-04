# Swift Markdown Attributed

A Markdown → `NSAttributedString` renderer built on Apple's [swift-markdown](https://github.com/apple/swift-markdown) (cmark-gfm), for native AppKit previews — an `NSTextView` / TextKit 2 replacement for a WKWebView.

- Module `MarkdownAttributed` in `Sources/MarkdownAttributed`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: AttributedRenderer, MarkdownAttributed, MarkdownStyle, MarkdownTableAttachment

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.

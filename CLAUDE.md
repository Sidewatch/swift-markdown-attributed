# Swift Markdown Attributed

A Markdown → `NSAttributedString` renderer built on Apple's [swift-markdown](https://github.com/apple/swift-markdown) (cmark-gfm), for native AppKit previews — an `NSTextView` / TextKit 2 replacement for a WKWebView.

- **Archived 18 Sep 2026** — no longer a Sidewatch dependency; read-only. Nothing here needs work.
- Module `MarkdownAttributed` in `Sources/MarkdownAttributed`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: AttributedRenderer, MarkdownAttributed, MarkdownStyle, MarkdownTableAttachment

## Rules

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.

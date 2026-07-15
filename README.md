# Swift Markdown Attributed

A Markdown → `NSAttributedString` renderer built on Apple's [swift-markdown](https://github.com/apple/swift-markdown) (cmark-gfm), for native AppKit previews — an `NSTextView` / TextKit 2 replacement for a WKWebView.

## Features

- ⚡ **One-call API** — `MarkdownAttributed.render(_:style:)` takes a Markdown string and a `MarkdownStyle` (fonts, colors, spacing — every knob has a stock default) and returns the finished `NSAttributedString`
- 📝 **CommonMark** — headings 1–6 (per-level fonts via `MarkdownStyle.headingFont(forLevel:)`), paragraphs, emphasis, nested lists, block quotes, fenced + indented code, thematic breaks
- 🐙 **GitHub-Flavored** — tables, task lists, strikethrough
- 📐 **Real typography** — hanging list indents and quote indents via `NSParagraphStyle`, per-level heading fonts
- 🧮 **Tables as live views** — each table is a `MarkdownTableAttachment` whose TextKit 2 view provider hosts an `NSGridView`; cell content goes through the same inline renderer and is reachable as data on the attachment (`headerCells` / `rows`)
- 🔗 **Links & images** — `.link` attributes; images become `NSTextAttachment`s (file URLs resolved against `MarkdownStyle.baseURL`, missing images fall back to alt text, nothing is fetched over the network)
- 🎨 **Injected hooks** — plug in your own syntax highlighter via `MarkdownStyle.codeFormatter`; quoted ranges carry a `.markdownQuoteDepth` attribute so hosts can draw quote bars in `quoteBarColor`
- 🪶 **One dependency** — Apple's swift-markdown
- 🧪 **Fully tested** — unit tests over the rendered attribute runs: fonts, indents, links, images, quote depths, and table cell data

## Requirements

- macOS 13.0+ (AppKit)
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-markdown-attributed.git", branch: "main")
]
```

## Usage

```swift
import MarkdownAttributed

// One call with the stock style…
textView.textStorage?.setAttributedString(
    MarkdownAttributed.render("# Hello\n\nSome **bold** text and a [link](https://apple.com).")
)

// …or customize fonts, colors, spacing, and hooks:
var style = MarkdownStyle.default
style.bodyFont = .systemFont(ofSize: 14)
style.baseURL = documentDirectoryURL                    // resolves ![…](relative.png)
style.codeFormatter = { code, language in               // your syntax highlighter
    highlighter.highlight(code, language: language)
}
let text = MarkdownAttributed.render(markdown, style: style)
```

Tables require a TextKit 2 text view (`NSTextView(usingTextLayoutManager: true)`) — the table attachment vends an `NSTextAttachmentViewProvider` that hosts an `NSGridView`. The cell strings are also exposed directly on `MarkdownTableAttachment` (`headerCells` / `rows`) if you want to render them yourself.

## License

MIT

# Swift Markdown Attributed

A Markdown → `NSAttributedString` renderer built on Apple's [swift-markdown](https://github.com/apple/swift-markdown) (cmark-gfm), for native AppKit previews — an `NSTextView` / TextKit 2 replacement for a WKWebView.

## Features

- ⚡ **One-call API** — `MarkdownAttributed.render(_:style:)` takes a Markdown string and a `MarkdownStyle` (fonts, colors, spacing — every knob has a stock default) and returns the finished `NSAttributedString`
- 📝 **CommonMark** — headings 1–6 (per-level fonts via `MarkdownStyle.headingFont(forLevel:)`), paragraphs, emphasis, nested lists, block quotes, fenced + indented code, thematic breaks, hard + soft line breaks
- 🐙 **GitHub-Flavored** — tables (column alignments and `||`/`^` cell spans included), task lists, strikethrough, autolinks
- 🏷️ **Raw HTML, verbatim** — HTML blocks render monospaced on the code background (never sent to the code formatter); inline HTML tags render literally in inline-code styling — nothing is silently dropped
- 🧩 **Full element coverage** — every node swift-markdown can produce renders sensibly: symbol links in code voice, block directives and `^[inline attributes]` render their children transparently, Doxygen commands (`\param`/`\returns`/`\note`) get bold labels, custom nodes emit their text/children — enforced by a guard-rail test that walks a kitchen-sink document and fails if any node type renders nothing
- 📐 **Real typography** — hanging list indents and quote indents via `NSParagraphStyle`, composed through nesting (tables and HTML blocks indent inside lists and quotes), per-level heading fonts
- 🧮 **Tables as live views** — each table is a `MarkdownTableAttachment` whose TextKit 2 view provider hosts an `NSGridView` with delimiter-row alignments applied per column and spanning cells merged; cell content goes through the same inline renderer and is reachable as data on the attachment (`headerCells` / `rows` / `columnAlignments` / `rowSpans`)
- 🔗 **Links & images** — `.link` attributes; images become `NSTextAttachment`s (file URLs resolved against `MarkdownStyle.baseURL`, missing images fall back to alt text, nothing is fetched over the network)
- 🎨 **Injected hooks** — plug in your own syntax highlighter via `MarkdownStyle.codeFormatter`; quoted ranges carry a `.markdownQuoteDepth` attribute so hosts can draw quote bars in `quoteBarColor`
- 🪶 **One dependency** — Apple's swift-markdown
- 🧪 **Fully tested** — unit tests over the rendered attribute runs: fonts, indents, links, images, quote depths, table cell data/alignments/spans, plus a kitchen-sink coverage suite and the node-type guard rail

## Requirements

- macOS 14+ (AppKit)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-markdown-attributed.git", branch: "main")
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

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT

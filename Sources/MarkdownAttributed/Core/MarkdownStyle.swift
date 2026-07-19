//
//  MarkdownStyle.swift
//  SwiftMarkdownAttributed
//
//  The visual configuration for the Markdown → NSAttributedString renderer:
//  fonts, colors, spacing, plus optional injected hooks (a syntax-highlighting
//  code formatter and a base URL for resolving relative image paths).
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit

/// The visual configuration used by ``MarkdownAttributed/render(_:style:)``.
///
/// Every knob has a sensible default (``default``); mutate a copy to customize:
///
/// ```swift
/// var style = MarkdownStyle.default
/// style.bodyFont = .systemFont(ofSize: 14)
/// style.codeFormatter = { code, language in highlighter.highlight(code, as: language) }
/// style.baseURL = documentDirectoryURL   // resolves ![…](relative.png)
/// let text = MarkdownAttributed.render(markdown, style: style)
/// ```
public struct MarkdownStyle {

    // MARK: Fonts

    /// The font for body text (paragraphs, lists, block quotes).
    public var bodyFont: NSFont

    /// The level-1 heading font. Lower levels reuse its descriptor at a scaled
    /// point size — see ``headingFont(forLevel:)``.
    public var headingFont: NSFont

    /// The font for inline code and (when ``codeFormatter`` is nil) code blocks.
    /// Inline code is re-sized to match the surrounding text.
    public var monospacedFont: NSFont

    // MARK: Colors

    /// The primary text color.
    public var textColor: NSColor

    /// The color for de-emphasized text: block-quote content, list markers,
    /// thematic breaks, and image alt-text fallbacks.
    public var secondaryTextColor: NSColor

    /// The foreground color for links (which also carry the `.link` attribute).
    public var linkColor: NSColor

    /// The background color behind inline code and code blocks.
    public var codeBackgroundColor: NSColor

    /// The color a host view should use to draw block-quote bars. The renderer
    /// marks quoted ranges with ``NSAttributedString/Key/markdownQuoteDepth``
    /// (and indents them); drawing the bar itself is up to the host.
    public var quoteBarColor: NSColor

    /// Stroke color for table chrome (outer border, row/column rules). `nil`
    /// uses ``secondaryTextColor`` at 25% opacity — visible on light and dark
    /// backgrounds without theming.
    public var tableBorderColor: NSColor?

    /// Optional fill behind a table's header row (GitHub tints it slightly).
    /// `nil` (the default) draws no header background.
    public var tableHeaderBackground: NSColor?

    // MARK: Spacing

    /// Vertical spacing after each block (paragraph, heading, list, code block).
    public var paragraphSpacing: CGFloat

    /// Line-height multiple for body prose (GitHub uses 1.5 — the airy spacing is a
    /// big part of the "reads like a rendered README" feel). Headings and code blocks
    /// apply their own tighter multiples internally.
    public var lineHeightMultiple: CGFloat

    /// Horizontal indent added per list-nesting level; also the hanging indent
    /// that aligns wrapped list lines past their marker.
    public var listIndent: CGFloat

    /// Horizontal indent added per block-quote nesting level.
    public var quoteIndent: CGFloat

    // MARK: Injected hooks

    /// Optional syntax highlighter for fenced/indented code blocks. Called with
    /// the code (without its trailing newline) and the fence language, if any.
    /// When nil, code blocks render in ``monospacedFont`` + ``textColor``.
    public var codeFormatter: ((_ code: String, _ language: String?) -> NSAttributedString)?

    /// Optional base URL for resolving relative image paths. Only file URLs are
    /// loaded (the renderer never touches the network); an unresolvable or
    /// missing image falls back to its alt text.
    public var baseURL: URL?

    // MARK: Init

    /// Creates a style; every parameter defaults to the stock value, so pass
    /// only the knobs you want to change (or mutate a copy of ``default``).
    public init(
        bodyFont: NSFont = .systemFont(ofSize: 13),
        headingFont: NSFont = .systemFont(ofSize: 26, weight: .semibold),
        monospacedFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular),
        textColor: NSColor = .labelColor,
        secondaryTextColor: NSColor = .secondaryLabelColor,
        linkColor: NSColor = .linkColor,
        codeBackgroundColor: NSColor = NSColor.labelColor.withAlphaComponent(0.07),
        quoteBarColor: NSColor = .separatorColor,
        tableBorderColor: NSColor? = nil,
        tableHeaderBackground: NSColor? = nil,
        paragraphSpacing: CGFloat = 14,
        lineHeightMultiple: CGFloat = 1.5,
        listIndent: CGFloat = 28,
        quoteIndent: CGFloat = 16,
        codeFormatter: ((_ code: String, _ language: String?) -> NSAttributedString)? = nil,
        baseURL: URL? = nil
    ) {
        self.bodyFont = bodyFont
        self.headingFont = headingFont
        self.monospacedFont = monospacedFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeBackgroundColor = codeBackgroundColor
        self.quoteBarColor = quoteBarColor
        self.tableBorderColor = tableBorderColor
        self.tableHeaderBackground = tableHeaderBackground
        self.paragraphSpacing = paragraphSpacing
        self.lineHeightMultiple = lineHeightMultiple
        self.listIndent = listIndent
        self.quoteIndent = quoteIndent
        self.codeFormatter = codeFormatter
        self.baseURL = baseURL
    }

    /// The stock style: system fonts, semantic AppKit colors, GitHub-like spacing
    /// (1.5 line-height, 14pt block spacing, body-relative heading sizes).
    public static let `default` = MarkdownStyle()

    /// The font for a heading of `level` (1…6). Sizes follow GitHub's scale, taken
    /// **relative to the body size** (H1 = 2em, H2 = 1.5em, H3 = 1.25em, H4 = 1em,
    /// H5 = 0.875em, H6 = 0.85em), rendered in ``headingFont``'s family/weight (its
    /// own point size is ignored — only the descriptor's traits carry over).
    public func headingFont(forLevel level: Int) -> NSFont {
        let scales: [CGFloat] = [2.0, 1.5, 1.25, 1.0, 0.875, 0.85]
        let scale = scales[max(1, min(6, level)) - 1]
        let size = (bodyFont.pointSize * scale).rounded()
        return NSFont(descriptor: headingFont.fontDescriptor, size: size)
            ?? .systemFont(ofSize: size, weight: .semibold)
    }
}

public extension NSAttributedString.Key {
    /// Present (as an `Int` nesting depth, 1-based) on every range rendered
    /// inside a block quote, so a host layout pass can draw quote bars in
    /// ``MarkdownStyle/quoteBarColor`` alongside the indented text.
    static let markdownQuoteDepth = NSAttributedString.Key("MarkdownAttributed.quoteDepth")

    /// Present (as `true`) on every range that is a fenced/indented code block or
    /// raw-HTML block, so a host layout pass can draw a full-width, padded, rounded
    /// background behind it (GitHub-style) rather than the ragged per-glyph tint the
    /// attributed `.backgroundColor` gives on its own.
    static let markdownCodeBlock = NSAttributedString.Key("MarkdownAttributed.codeBlock")

    /// Present (as the heading's `Int` level, 1…6) on a heading's text range, so a
    /// host layout pass can draw a GitHub-style bottom hairline under H1/H2.
    static let markdownHeadingLevel = NSAttributedString.Key("MarkdownAttributed.headingLevel")

    /// Present (as `true`) on inline-code / inline-HTML / symbol-link ranges, so a
    /// host layout pass can draw a rounded, padded "pill" behind them (GitHub-style)
    /// instead of relying on the ragged per-glyph `.backgroundColor` tint alone.
    static let markdownInlineCode = NSAttributedString.Key("MarkdownAttributed.inlineCode")

    /// Present (as `true`) on a thematic break's (otherwise blank) line, so a host
    /// layout pass can draw a full-width horizontal rule. Without a host drawer the
    /// break renders as empty space.
    static let markdownThematicBreak = NSAttributedString.Key("MarkdownAttributed.thematicBreak")
}

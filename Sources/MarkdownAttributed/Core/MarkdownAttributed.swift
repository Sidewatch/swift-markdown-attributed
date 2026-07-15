//
//  MarkdownAttributed.swift
//  SwiftMarkdownAttributed
//
//  Renders a CommonMark + GitHub-Flavored-Markdown document to an
//  NSAttributedString via Apple's swift-markdown (cmark-gfm), for native
//  AppKit previews (NSTextView / TextKit 2) — no WKWebView required.
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit
import Markdown

/// Renders Markdown to a styled `NSAttributedString`.
///
/// A full CommonMark + GitHub-Flavored-Markdown document (parsed by Apple's
/// swift-markdown / cmark-gfm) is walked and emitted as attributed text —
/// headings, emphasis, nested lists and quotes, task lists, links, images,
/// code blocks, thematic breaks, and tables (as an `NSTextAttachment` whose
/// TextKit 2 view provider hosts an `NSGridView`).
///
/// ```swift
/// import MarkdownAttributed
///
/// textView.textStorage?.setAttributedString(
///     MarkdownAttributed.render("# Hello\n\nSome **bold** text.")
/// )
/// ```
public enum MarkdownAttributed {

    /// Parses `markdown` and returns the rendered attributed string.
    ///
    /// The input is treated as a complete Markdown document. Styling — fonts,
    /// colors, spacing, the optional code formatter and image base URL — comes
    /// from `style`.
    ///
    /// - Parameters:
    ///   - markdown: The Markdown source to render.
    ///   - style: The visual configuration; defaults to ``MarkdownStyle/default``.
    /// - Returns: The rendered attributed string (no trailing newline).
    public static func render(_ markdown: String, style: MarkdownStyle = .default) -> NSAttributedString {
        let document = Markdown.Document(parsing: markdown)
        var renderer = AttributedRenderer(style: style)
        let rendered = NSMutableAttributedString(attributedString: renderer.visit(document))
        if rendered.string.hasSuffix("\n") {
            rendered.deleteCharacters(in: NSRange(location: rendered.length - 1, length: 1))
        }
        return rendered
    }
}

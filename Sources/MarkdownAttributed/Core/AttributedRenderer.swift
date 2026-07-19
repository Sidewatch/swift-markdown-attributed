//
//  AttributedRenderer.swift
//  SwiftMarkdownAttributed
//
//  The MarkupVisitor behind MarkdownAttributed.render(_:style:): walks the
//  parsed tree and emits attributed text. Inline state (font traits, link,
//  strikethrough) and block context (quote depth, list depth, pending list
//  marker) are tracked as visitor state; blocks end with a newline and carry
//  an NSParagraphStyle for spacing/indent.
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit
import Markdown

/// Walks a parsed Markdown tree and emits a styled `NSAttributedString`.
///
/// Kept internal to the module: it is the rendering machinery behind
/// ``MarkdownAttributed/render(_:style:)`` and not part of the public surface.
struct AttributedRenderer: MarkupVisitor {
    typealias Result = NSAttributedString

    let style: MarkdownStyle

    /// The block-level font inline runs inherit — the body font normally, the
    /// per-level heading font while inside a heading.
    private var currentFont: NSFont
    /// Symbolic traits accumulated from enclosing Strong/Emphasis nodes.
    private var traits: NSFontDescriptor.SymbolicTraits = []
    private var isStrikethrough = false
    /// The destination of the enclosing Link node, if any.
    private var linkDestination: String?
    /// Block-quote nesting depth (0 = not quoted).
    private var quoteDepth = 0
    /// List nesting depth (0 = not in a list).
    private var listDepth = 0
    /// Marker ("• \t", "1.\t", "☐\t") the next paragraph should prepend —
    /// set by visitListItem, consumed by the item's first paragraph.
    private var pendingListMarker: NSAttributedString?

    init(style: MarkdownStyle) {
        self.style = style
        self.currentFont = style.bodyFont
    }

    // MARK: - Fallback

    /// Any node without a dedicated visitor renders as its children, joined —
    /// the transparent-container fallback. Pure containers with no content of
    /// their own (`Document`, `DoxygenAbstract`, `DoxygenDiscussion`, the
    /// table sub-nodes reached via ``visitTable(_:)``) rely on it by design.
    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        join(markup)
    }

    /// Visits and concatenates all of `markup`'s children.
    private mutating func join(_ markup: Markup) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(visit(child))
        }
        return out
    }

    // MARK: - Inline nodes

    mutating func visitText(_ text: Markdown.Text) -> NSAttributedString {
        NSAttributedString(string: text.string, attributes: inlineAttributes())
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: inlineAttributes())
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        // U+2028 is an in-paragraph line separator, so the paragraph style
        // (indent, spacing) still spans the whole visual paragraph.
        NSAttributedString(string: "\u{2028}", attributes: inlineAttributes())
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let saved = traits
        traits.insert(.bold)
        let result = join(strong)
        traits = saved
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let saved = traits
        traits.insert(.italic)
        let result = join(emphasis)
        traits = saved
        return result
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let saved = isStrikethrough
        isStrikethrough = true
        let result = join(strikethrough)
        isStrikethrough = saved
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(string: inlineCode.code, attributes: codeVoiceAttributes())
    }

    /// A symbol link (``` ``Type/member`` ```, parsed with `.parseSymbolLinks`)
    /// renders its destination in code voice, per swift-markdown's guidance.
    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> NSAttributedString {
        NSAttributedString(string: symbolLink.destination ?? "", attributes: codeVoiceAttributes())
    }

    /// A custom inline node (programmatically built trees only — the parser
    /// never produces one) renders its raw text like plain inline text.
    mutating func visitCustomInline(_ customInline: CustomInline) -> NSAttributedString {
        NSAttributedString(string: customInline.text, attributes: inlineAttributes())
    }

    /// `^[text](key: value)` renders its children; the attribute payload is
    /// interpretation metadata this renderer has no channel for, so it is skipped.
    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> NSAttributedString {
        join(attributes)
    }

    /// Renders the link's children with `.link` styling; a childless link
    /// (possible in programmatic trees) falls back to its destination as the
    /// visible text so it never vanishes.
    mutating func visitLink(_ link: Markdown.Link) -> NSAttributedString {
        let saved = linkDestination
        linkDestination = link.destination ?? saved
        var result: NSAttributedString = join(link)
        if result.length == 0, let destination = linkDestination, !destination.isEmpty {
            result = NSAttributedString(string: destination, attributes: inlineAttributes())
        }
        linkDestination = saved
        return result
    }

    /// Local file images become image attachments; anything unresolvable
    /// (remote URL, missing file) falls back to the alt text.
    mutating func visitImage(_ image: Markdown.Image) -> NSAttributedString {
        let alt = image.plainText
        var altAttributes = inlineAttributes()
        altAttributes[.foregroundColor] = style.secondaryTextColor
        let altText = NSAttributedString(
            string: alt.isEmpty ? (image.source ?? "") : alt,
            attributes: altAttributes
        )

        guard let source = image.source, !source.isEmpty,
              let fileURL = resolveImageURL(source),
              let nsImage = NSImage(contentsOf: fileURL), nsImage.isValid
        else { return altText }

        let attachment = NSTextAttachment()
        attachment.image = nsImage
        attachment.bounds = CGRect(origin: .zero, size: nsImage.size)
        return NSAttributedString(attachment: attachment)
    }

    /// Raw inline HTML (`<b>`, `<br>`, …) renders literally in code voice so
    /// the tag is visible and clearly distinguished from prose.
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inlineHTML.rawHTML, attributes: codeVoiceAttributes())
    }

    // MARK: - Block nodes

    /// Emits a paragraph block, prepending the pending list marker (with a
    /// hanging indent) when this is the first paragraph of a list item.
    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let content = join(paragraph)
        let (paragraphStyle, marker) = listAwareBlockStart()
        let result = NSMutableAttributedString()
        if let marker { result.append(marker) }
        result.append(content)
        return finishBlock(result, paragraphStyle: paragraphStyle)
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let saved = currentFont
        currentFont = style.headingFont(forLevel: heading.level)
        let content = join(heading)
        currentFont = saved

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = style.paragraphSpacing
        // GitHub gives a heading more room above than below; adding half the block
        // spacing before (on top of the previous block's trailing spacing) reads as
        // that extra separation. Headings sit tighter internally (1.2).
        paragraphStyle.paragraphSpacingBefore = style.paragraphSpacing * 0.5
        paragraphStyle.lineHeightMultiple = 1.2
        let quoteBase = CGFloat(quoteDepth) * style.quoteIndent
        paragraphStyle.firstLineHeadIndent = quoteBase
        paragraphStyle.headIndent = quoteBase
        return finishBlock(content, paragraphStyle: paragraphStyle)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        quoteDepth += 1
        let result = join(blockQuote)
        quoteDepth -= 1
        return result
    }

    /// Renders a fenced/indented code block via `style.codeFormatter` when set,
    /// otherwise in the monospaced font; always adds the code background.
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        let content: NSMutableAttributedString
        if let formatter = style.codeFormatter {
            content = NSMutableAttributedString(attributedString: formatter(code, codeBlock.language))
        } else {
            content = NSMutableAttributedString(string: code, attributes: [
                .font: style.monospacedFont,
                .foregroundColor: quoteDepth > 0 ? style.secondaryTextColor : style.textColor,
            ])
        }
        content.addAttribute(
            .backgroundColor,
            value: style.codeBackgroundColor,
            range: NSRange(location: 0, length: content.length)
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = style.paragraphSpacing
        paragraphStyle.lineHeightMultiple = 1.4   // GitHub code line-height ~1.45
        let base = CGFloat(quoteDepth) * style.quoteIndent + CGFloat(listDepth) * style.listIndent
        paragraphStyle.firstLineHeadIndent = base
        paragraphStyle.headIndent = base
        return finishBlock(content, paragraphStyle: paragraphStyle)
    }

    /// A raw HTML block renders verbatim, styled like a code block (monospaced
    /// on the code background — the `codeFormatter` hook is *not* consulted).
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let content = NSMutableAttributedString(
            string: html.rawHTML.trimmingCharacters(in: .newlines),
            attributes: [
                .font: style.monospacedFont,
                .foregroundColor: quoteDepth > 0 ? style.secondaryTextColor : style.textColor,
                .backgroundColor: style.codeBackgroundColor,
            ]
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = style.paragraphSpacing
        let base = CGFloat(quoteDepth) * style.quoteIndent + CGFloat(listDepth) * style.listIndent
        paragraphStyle.firstLineHeadIndent = base
        paragraphStyle.headIndent = base
        return finishBlock(content, paragraphStyle: paragraphStyle)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let rule = NSMutableAttributedString(
            string: String(repeating: "\u{2500}", count: 24),
            attributes: [.font: style.bodyFont, .foregroundColor: style.secondaryTextColor]
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = style.paragraphSpacing
        paragraphStyle.paragraphSpacingBefore = style.paragraphSpacing
        let base = CGFloat(quoteDepth) * style.quoteIndent + CGFloat(listDepth) * style.listIndent
        paragraphStyle.firstLineHeadIndent = base
        paragraphStyle.headIndent = base
        return finishBlock(rule, paragraphStyle: paragraphStyle)
    }

    /// A block directive (`@Name { … }`, parsed only with `.parseBlockDirectives`)
    /// is a transparent container: its children render in place; the directive
    /// name and argument text are interpretation metadata and are skipped.
    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> NSAttributedString {
        join(blockDirective)
    }

    /// A custom block node (programmatically built trees only — the parser
    /// never produces one) is a transparent container for its block children.
    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> NSAttributedString {
        join(customBlock)
    }

    // MARK: - Doxygen commands (parsed only with `.parseMinimalDoxygen`)

    /// `\param name …` renders its description labeled "Parameter name: " in bold.
    mutating func visitDoxygenParameter(_ doxygenParam: DoxygenParameter) -> NSAttributedString {
        labeledBlock("Parameter \(doxygenParam.name): ", doxygenParam)
    }

    /// `\returns …` renders its description labeled "Returns: " in bold.
    mutating func visitDoxygenReturns(_ doxygenReturns: DoxygenReturns) -> NSAttributedString {
        labeledBlock("Returns: ", doxygenReturns)
    }

    /// `\note …` renders its content labeled "Note: " in bold.
    mutating func visitDoxygenNote(_ doxygenNote: DoxygenNote) -> NSAttributedString {
        labeledBlock("Note: ", doxygenNote)
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        listDepth += 1
        let result = join(list)
        listDepth -= 1
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        listDepth += 1
        let result = join(list)
        listDepth -= 1
        return result
    }

    /// Stages the item's marker (bullet / number / checkbox) for its first
    /// paragraph to consume, then renders the item's children.
    mutating func visitListItem(_ item: ListItem) -> NSAttributedString {
        let markerText: String
        if let checkbox = item.checkbox {
            markerText = checkbox == .checked ? "\u{2611}" : "\u{2610}" // ☑ / ☐
        } else if let ordered = item.parent as? OrderedList {
            markerText = "\(Int(ordered.startIndex) + item.indexInParent)."
        } else {
            markerText = "\u{2022}" // •
        }
        pendingListMarker = NSAttributedString(string: markerText + "\t", attributes: [
            .font: style.bodyFont,
            .foregroundColor: style.secondaryTextColor,
        ])

        let content = join(item)

        // An empty item ("- " with no text) never had a paragraph to consume
        // the marker — emit the marker on its own line so the row still shows.
        if let marker = pendingListMarker {
            pendingListMarker = nil
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = style.paragraphSpacing
            paragraphStyle.firstLineHeadIndent =
                CGFloat(quoteDepth) * style.quoteIndent + CGFloat(listDepth - 1) * style.listIndent
            content.append(finishBlock(NSMutableAttributedString(attributedString: marker), paragraphStyle: paragraphStyle))
        }
        return content
    }

    // MARK: - Tables

    /// Renders each cell through the inline visitor, then packs the results —
    /// plus the delimiter-row column alignments and any cell spans — into a
    /// ``MarkdownTableAttachment`` block, indented to the current quote/list
    /// depth (consuming the list marker when the table opens a list item).
    mutating func visitTable(_ table: Markdown.Table) -> NSAttributedString {
        let alignments: [NSTextAlignment] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            case nil: return .natural
            }
        }

        // Header cells render bold; all cells go through the same inline visitor.
        let savedTraits = traits
        traits.insert(.bold)
        var header: [NSAttributedString] = []
        var headerSpans: [MarkdownTableAttachment.CellSpan] = []
        for case let cell as Markdown.Table.Cell in table.head.children {
            header.append(join(cell))
            headerSpans.append(.init(colspan: Int(cell.colspan), rowspan: Int(cell.rowspan)))
        }
        traits = savedTraits

        var rows: [[NSAttributedString]] = []
        var rowSpans: [[MarkdownTableAttachment.CellSpan]] = []
        for case let row as Markdown.Table.Row in table.body.children {
            var cells: [NSAttributedString] = []
            var spans: [MarkdownTableAttachment.CellSpan] = []
            for case let cell as Markdown.Table.Cell in row.children {
                cells.append(join(cell))
                spans.append(.init(colspan: Int(cell.colspan), rowspan: Int(cell.rowspan)))
            }
            rows.append(cells)
            rowSpans.append(spans)
        }

        let attachment = MarkdownTableAttachment(
            headerCells: header,
            rows: rows,
            columnAlignments: alignments,
            headerSpans: headerSpans,
            rowSpans: rowSpans,
            borderColor: style.tableBorderColor ?? style.secondaryTextColor.withAlphaComponent(0.25),
            headerBackground: style.tableHeaderBackground
        )
        let (paragraphStyle, marker) = listAwareBlockStart()
        let content = NSMutableAttributedString()
        if let marker { content.append(marker) }
        content.append(NSAttributedString(attachment: attachment))
        return finishBlock(content, paragraphStyle: paragraphStyle)
    }

    // MARK: - Helpers

    /// The attribute run for the current inline context: block font + traits,
    /// text/secondary/link color, strikethrough, and the `.link` attribute.
    private func inlineAttributes() -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes[.font] = traits.isEmpty ? currentFont : currentFont.mdAddingTraits(traits)
        attributes[.foregroundColor] = quoteDepth > 0 ? style.secondaryTextColor : style.textColor
        if isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let destination = linkDestination {
            attributes[.link] = URL(string: destination) ?? destination
            attributes[.foregroundColor] = style.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// The attribute run for code-voice inline spans (inline code, inline
    /// HTML, symbol links): the monospaced font re-sized to the surrounding
    /// text plus the code background, layered over the inline attributes.
    private func codeVoiceAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = inlineAttributes()
        let mono = style.monospacedFont
        attributes[.font] = NSFont(descriptor: mono.fontDescriptor, size: currentFont.pointSize) ?? mono
        attributes[.backgroundColor] = style.codeBackgroundColor
        return attributes
    }

    /// Builds the paragraph style for a block at the current quote/list depth
    /// and consumes the pending list marker when one is staged. Returns the
    /// style plus the marker the block must prepend (nil when the block does
    /// not open a list item).
    ///
    /// Inside a list the style gets a hanging indent: text sits at `head`; the
    /// marker line starts one list level shallower, with a tab stop pulling
    /// its text back to `head`.
    private mutating func listAwareBlockStart() -> (paragraphStyle: NSMutableParagraphStyle, marker: NSAttributedString?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = style.paragraphSpacing
        paragraphStyle.lineHeightMultiple = style.lineHeightMultiple   // GitHub-airy prose
        let quoteBase = CGFloat(quoteDepth) * style.quoteIndent
        var marker: NSAttributedString?
        if listDepth > 0 {
            let head = quoteBase + CGFloat(listDepth) * style.listIndent
            paragraphStyle.headIndent = head
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: head)]
            paragraphStyle.defaultTabInterval = style.listIndent
            if let pending = pendingListMarker {
                pendingListMarker = nil
                marker = pending
                paragraphStyle.firstLineHeadIndent = quoteBase + CGFloat(listDepth - 1) * style.listIndent
            } else {
                paragraphStyle.firstLineHeadIndent = head
            }
        } else {
            paragraphStyle.firstLineHeadIndent = quoteBase
            paragraphStyle.headIndent = quoteBase
        }
        return (paragraphStyle, marker)
    }

    /// Renders a labeled Doxygen container (`\param`, `\returns`, `\note`):
    /// its children, with `label` prefixed in bold to the first paragraph.
    /// A childless command renders as just the label so it never vanishes.
    private mutating func labeledBlock(_ label: String, _ node: Markup) -> NSAttributedString {
        let content = join(node)
        guard content.length > 0 else {
            var attributes = inlineAttributes()
            attributes[.font] = ((attributes[.font] as? NSFont) ?? style.bodyFont).mdAddingTraits(.bold)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = style.paragraphSpacing
            return finishBlock(
                NSMutableAttributedString(string: label, attributes: attributes),
                paragraphStyle: paragraphStyle
            )
        }
        // Inherit the first paragraph's attributes (paragraph style included)
        // so the label sits inside the same visual paragraph, bolded. Never
        // copy an attachment — the label is plain text.
        var attributes = content.attributes(at: 0, effectiveRange: nil)
        attributes.removeValue(forKey: .attachment)
        attributes[.font] = ((attributes[.font] as? NSFont) ?? style.bodyFont).mdAddingTraits(.bold)
        content.insert(NSAttributedString(string: label, attributes: attributes), at: 0)
        return content
    }

    /// Terminates a block: appends the block newline, applies the paragraph
    /// style across the whole range, and tags quoted ranges with their depth.
    private func finishBlock(_ content: NSMutableAttributedString, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        content.append(NSAttributedString(string: "\n"))
        let range = NSRange(location: 0, length: content.length)
        content.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        if quoteDepth > 0 {
            content.addAttribute(.markdownQuoteDepth, value: quoteDepth, range: range)
        }
        return content
    }

    /// Resolves an image source to a local file URL (against `style.baseURL`
    /// when the source is relative). Returns nil for non-file destinations —
    /// the renderer never loads over the network.
    private func resolveImageURL(_ source: String) -> URL? {
        if let url = URL(string: source, relativeTo: style.baseURL), url.isFileURL {
            return url.absoluteURL
        }
        // Sources that aren't valid URL strings (e.g. contain spaces) still
        // resolve as plain paths against a file base URL.
        if let base = style.baseURL, base.isFileURL, !source.contains("://") {
            return URL(fileURLWithPath: source, relativeTo: base).absoluteURL
        }
        return nil
    }
}

private extension NSFont {
    /// Returns self with `traits` (bold/italic) merged into its descriptor.
    func mdAddingTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let merged = fontDescriptor.symbolicTraits.union(traits)
        let descriptor = fontDescriptor.withSymbolicTraits(merged)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

//
//  MarkdownAttributedTests.swift
//  Tests for SwiftMarkdownAttributed
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit
import Markdown
import XCTest
@testable import MarkdownAttributed

final class MarkdownAttributedTests: XCTestCase {

    private let style = MarkdownStyle.default

    // MARK: - Helpers

    /// The attribute dictionary at the first character of `substring`.
    private func attributes(
        of substring: String,
        in rendered: NSAttributedString,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [NSAttributedString.Key: Any] {
        let range = (rendered.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("substring \(substring) not found in \(rendered.string)", file: file, line: line)
            return [:]
        }
        return rendered.attributes(at: range.location, effectiveRange: nil)
    }

    private func font(of substring: String, in rendered: NSAttributedString,
                      file: StaticString = #filePath, line: UInt = #line) -> NSFont? {
        attributes(of: substring, in: rendered, file: file, line: line)[.font] as? NSFont
    }

    private func paragraphStyle(of substring: String, in rendered: NSAttributedString,
                                file: StaticString = #filePath, line: UInt = #line) -> NSParagraphStyle? {
        attributes(of: substring, in: rendered, file: file, line: line)[.paragraphStyle] as? NSParagraphStyle
    }

    private func firstTableAttachment(in rendered: NSAttributedString) -> MarkdownTableAttachment? {
        allTableAttachments(in: rendered).first
    }

    /// Every table attachment in `rendered`, in document order.
    private func allTableAttachments(in rendered: NSAttributedString) -> [MarkdownTableAttachment] {
        var found: [MarkdownTableAttachment] = []
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let table = value as? MarkdownTableAttachment {
                found.append(table)
            }
        }
        return found
    }

    /// Renders `markdown` through the internal renderer with non-default parse
    /// options (symbol links, block directives, Doxygen — the public API
    /// parses with the defaults only). Unlike the public API, the result keeps
    /// its trailing block newline.
    private func renderWithOptions(
        _ markdown: String,
        options: ParseOptions,
        style: MarkdownStyle = .default
    ) -> NSAttributedString {
        let document = Markdown.Document(parsing: markdown, options: options)
        var renderer = AttributedRenderer(style: style)
        return renderer.visit(document)
    }

    /// Depth-first walk over `node` and all of its descendants.
    private func walk(_ node: Markup, _ body: (Markup) -> Void) {
        body(node)
        for child in node.children { walk(child, body) }
    }

    // MARK: - Headings

    func testHeadingLevels1Through6() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let rendered = MarkdownAttributed.render("\(hashes) Title\(level)")
            XCTAssertEqual(rendered.string, "Title\(level)")
            let headingFont = font(of: "Title\(level)", in: rendered)
            XCTAssertEqual(headingFont?.pointSize, style.headingFont(forLevel: level).pointSize,
                           "wrong size for h\(level)")
            XCTAssertTrue(headingFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                          "h\(level) should be bold")
        }
    }

    func testHeadingSizesDecrease() {
        XCTAssertGreaterThan(style.headingFont(forLevel: 1).pointSize, style.headingFont(forLevel: 3).pointSize)
        XCTAssertGreaterThan(style.headingFont(forLevel: 3).pointSize, style.headingFont(forLevel: 6).pointSize)
    }

    func testInlineCodeInsideHeadingMatchesHeadingSize() {
        let rendered = MarkdownAttributed.render("# Use `render` now")
        let codeFont = font(of: "render", in: rendered)
        XCTAssertEqual(codeFont?.pointSize, style.headingFont(forLevel: 1).pointSize)
        XCTAssertTrue(codeFont?.isFixedPitch ?? false)
    }

    // MARK: - Paragraphs & inline styles

    func testParagraphUsesBodyFontAndTextColor() {
        let rendered = MarkdownAttributed.render("Plain text here.")
        XCTAssertEqual(rendered.string, "Plain text here.")
        let attrs = attributes(of: "Plain", in: rendered)
        XCTAssertEqual(attrs[.font] as? NSFont, style.bodyFont)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, style.textColor)
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(ps?.paragraphSpacing, style.paragraphSpacing)
    }

    func testTwoParagraphsSeparatedBySingleNewline() {
        let rendered = MarkdownAttributed.render("First.\n\nSecond.")
        XCTAssertEqual(rendered.string, "First.\nSecond.")
    }

    func testStrongIsBold() {
        let rendered = MarkdownAttributed.render("Some **bold** text.")
        XCTAssertTrue(font(of: "bold", in: rendered)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        XCTAssertFalse(font(of: "Some", in: rendered)?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    func testEmphasisIsItalic() {
        let rendered = MarkdownAttributed.render("An *italic* word.")
        XCTAssertTrue(font(of: "italic", in: rendered)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
    }

    func testBoldItalicCombines() {
        let rendered = MarkdownAttributed.render("***both***")
        let traits = font(of: "both", in: rendered)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold))
        XCTAssertTrue(traits.contains(.italic))
    }

    func testStrikethrough() {
        let rendered = MarkdownAttributed.render("~~gone~~ kept")
        let attrs = attributes(of: "gone", in: rendered)
        XCTAssertEqual(attrs[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(attributes(of: "kept", in: rendered)[.strikethroughStyle])
    }

    // MARK: - Code

    func testInlineCode() {
        let rendered = MarkdownAttributed.render("Use `let x = 1` here.")
        let attrs = attributes(of: "let x = 1", in: rendered)
        XCTAssertTrue((attrs[.font] as? NSFont)?.isFixedPitch ?? false)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
        XCTAssertNil(attributes(of: "here", in: rendered)[.backgroundColor])
    }

    func testFencedCodeBlockDefaultsToMonospaced() {
        let rendered = MarkdownAttributed.render("```swift\nlet x = 1\n```")
        XCTAssertTrue(rendered.string.contains("let x = 1"))
        let attrs = attributes(of: "let x = 1", in: rendered)
        XCTAssertEqual(attrs[.font] as? NSFont, style.monospacedFont)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
    }

    func testIndentedCodeBlock() {
        let rendered = MarkdownAttributed.render("    indented code")
        let attrs = attributes(of: "indented code", in: rendered)
        XCTAssertEqual(attrs[.font] as? NSFont, style.monospacedFont)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
    }

    func testCodeFormatterHookReceivesCodeAndLanguage() {
        let customKey = NSAttributedString.Key("test.highlighted")
        var seenCode: String?
        var seenLanguage: String?
        var custom = MarkdownStyle.default
        custom.codeFormatter = { code, language in
            seenCode = code
            seenLanguage = language
            return NSAttributedString(string: code, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                customKey: true,
            ])
        }

        let rendered = MarkdownAttributed.render("```swift\nlet x = 1\n```", style: custom)
        XCTAssertEqual(seenCode, "let x = 1")
        XCTAssertEqual(seenLanguage, "swift")
        let attrs = attributes(of: "let x = 1", in: rendered)
        XCTAssertEqual(attrs[customKey] as? Bool, true)
        // The block still gets the code background even through the hook.
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, custom.codeBackgroundColor)
    }

    func testCodeFormatterNotUsedForInlineCode() {
        var called = false
        var custom = MarkdownStyle.default
        custom.codeFormatter = { code, _ in
            called = true
            return NSAttributedString(string: code)
        }
        _ = MarkdownAttributed.render("Inline `code` only.", style: custom)
        XCTAssertFalse(called)
    }

    // MARK: - Block quotes

    func testBlockQuoteIndentsAndTagsDepth() {
        let rendered = MarkdownAttributed.render("> quoted text")
        let attrs = attributes(of: "quoted text", in: rendered)
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(ps?.headIndent, style.quoteIndent)
        XCTAssertEqual(ps?.firstLineHeadIndent, style.quoteIndent)
        XCTAssertEqual(attrs[.markdownQuoteDepth] as? Int, 1)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, style.secondaryTextColor)
    }

    func testNestedBlockQuoteIndentsDeeper() {
        let rendered = MarkdownAttributed.render("> outer\n>\n> > inner")
        let outer = attributes(of: "outer", in: rendered)
        let inner = attributes(of: "inner", in: rendered)
        XCTAssertEqual(outer[.markdownQuoteDepth] as? Int, 1)
        XCTAssertEqual(inner[.markdownQuoteDepth] as? Int, 2)
        XCTAssertEqual((inner[.paragraphStyle] as? NSParagraphStyle)?.headIndent, style.quoteIndent * 2)
    }

    func testUnquotedTextHasNoQuoteDepth() {
        let rendered = MarkdownAttributed.render("plain")
        XCTAssertNil(attributes(of: "plain", in: rendered)[.markdownQuoteDepth])
    }

    // MARK: - Lists

    func testUnorderedListHasBulletsAndHangingIndent() {
        let rendered = MarkdownAttributed.render("- one\n- two")
        XCTAssertTrue(rendered.string.contains("\u{2022}\tone"))
        XCTAssertTrue(rendered.string.contains("\u{2022}\ttwo"))
        let ps = paragraphStyle(of: "one", in: rendered)
        XCTAssertEqual(ps?.firstLineHeadIndent, 0)
        XCTAssertEqual(ps?.headIndent, style.listIndent)
        XCTAssertEqual(ps?.tabStops.first?.location, style.listIndent)
    }

    func testOrderedListNumbersAndStartIndex() {
        let rendered = MarkdownAttributed.render("3. third\n4. fourth")
        XCTAssertTrue(rendered.string.contains("3.\tthird"))
        XCTAssertTrue(rendered.string.contains("4.\tfourth"))
    }

    func testNestedListIndentsDeeper() {
        let rendered = MarkdownAttributed.render("- outer\n  - inner")
        let outer = paragraphStyle(of: "outer", in: rendered)
        let inner = paragraphStyle(of: "inner", in: rendered)
        XCTAssertEqual(outer?.headIndent, style.listIndent)
        XCTAssertEqual(inner?.headIndent, style.listIndent * 2)
        XCTAssertEqual(inner?.firstLineHeadIndent, style.listIndent)
    }

    func testTaskList() {
        let rendered = MarkdownAttributed.render("- [x] shipped\n- [ ] todo")
        XCTAssertTrue(rendered.string.contains("\u{2611}\tshipped")) // ☑
        XCTAssertTrue(rendered.string.contains("\u{2610}\ttodo"))    // ☐
    }

    func testListInsideBlockQuoteCombinesIndents() {
        let rendered = MarkdownAttributed.render("> - item")
        let ps = paragraphStyle(of: "item", in: rendered)
        XCTAssertEqual(ps?.headIndent, style.quoteIndent + style.listIndent)
        XCTAssertEqual(ps?.firstLineHeadIndent, style.quoteIndent)
    }

    func testListItemOpeningWithCodeFenceKeepsItsBullet() {
        let rendered = MarkdownAttributed.render("- ```\n  code here\n  ```\n  after text")
        XCTAssertTrue(rendered.string.contains("\u{2022}\tcode here"))
        XCTAssertFalse(rendered.string.contains("\u{2022}\tafter text"))
    }

    func testFenceOnlyListItemDoesNotEmitTrailingBulletRow() {
        let rendered = MarkdownAttributed.render("- ```\n  only code\n  ```\n- second item")
        XCTAssertEqual(rendered.string, "\u{2022}\tonly code\n\u{2022}\tsecond item")
    }

    func testListItemOpeningWithHTMLBlockKeepsItsBullet() {
        let rendered = MarkdownAttributed.render("- <div>x</div>")
        XCTAssertTrue(rendered.string.contains("\u{2022}\t<div>x</div>"))
    }

    func testEmptyListItem() {
        let rendered = MarkdownAttributed.render("- a\n-\n- b")
        XCTAssertEqual(rendered.string, "\u{2022}\ta\n\u{2022}\t\n\u{2022}\tb")
    }

    func testEmptyListItemHoldingOnlyANestedListKeepsItsRow() {
        let rendered = MarkdownAttributed.render("- parent text\n-\n  - sub item")
        XCTAssertEqual(rendered.string, "\u{2022}\tparent text\n\u{2022}\t\n\u{2022}\tsub item")
        // The flushed parent row sits at the parent's depth, not the sub-item's.
        let rows = rendered.string.components(separatedBy: "\n")
        XCTAssertEqual(rows.count, 3)
        let emptyRowStart = (rendered.string as NSString).range(of: "\u{2022}\t\n").location
        let ps = rendered.attributes(at: emptyRowStart, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(ps?.firstLineHeadIndent, 0)
    }

    // MARK: - Links

    func testLinkAttributeAndColor() {
        let rendered = MarkdownAttributed.render("[Apple](https://apple.com)")
        let attrs = attributes(of: "Apple", in: rendered)
        XCTAssertEqual(attrs[.link] as? URL, URL(string: "https://apple.com"))
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, style.linkColor)
        XCTAssertEqual(attrs[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }

    func testLinkStylingDoesNotLeak() {
        let rendered = MarkdownAttributed.render("[Apple](https://apple.com) and after")
        XCTAssertNil(attributes(of: "after", in: rendered)[.link])
        XCTAssertEqual(attributes(of: "after", in: rendered)[.foregroundColor] as? NSColor, style.textColor)
    }

    // MARK: - Images

    /// Writes a tiny valid PNG into a temp directory and returns the directory URL.
    private func makeTempImage(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownAttributedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let png = try XCTUnwrap(rep?.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name))
        return directory
    }

    func testImageResolvedAgainstBaseURLBecomesAttachment() throws {
        let directory = try makeTempImage(named: "pic.png")
        defer { try? FileManager.default.removeItem(at: directory) }
        var custom = MarkdownStyle.default
        custom.baseURL = directory

        let rendered = MarkdownAttributed.render("![alt text](pic.png)", style: custom)
        var attachment: NSTextAttachment?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let found = value as? NSTextAttachment { attachment = found }
        }
        XCTAssertNotNil(attachment, "image should render as an attachment")
        XCTAssertNotNil(attachment?.image)
        XCTAssertEqual(attachment?.image?.size.width, 4)
        XCTAssertFalse(rendered.string.contains("alt text"))
    }

    func testMissingImageFallsBackToAltText() {
        var custom = MarkdownStyle.default
        custom.baseURL = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)", isDirectory: true)
        let rendered = MarkdownAttributed.render("![missing pic](nope.png)", style: custom)
        XCTAssertTrue(rendered.string.contains("missing pic"))
        XCTAssertFalse(rendered.string.contains("\u{FFFC}"), "no attachment character expected")
        XCTAssertEqual(attributes(of: "missing pic", in: rendered)[.foregroundColor] as? NSColor,
                       custom.secondaryTextColor)
    }

    func testRemoteImageIsNotFetched() {
        let rendered = MarkdownAttributed.render("![remote alt](https://example.com/a.png)")
        XCTAssertTrue(rendered.string.contains("remote alt"))
        XCTAssertFalse(rendered.string.contains("\u{FFFC}"))
    }

    // MARK: - Thematic break

    func testThematicBreak() {
        let rendered = MarkdownAttributed.render("above\n\n---\n\nbelow")
        // The break is a blank marker line carrying `.markdownThematicBreak` — the host
        // draws the full-width rule; the attributed string has no rule glyphs of its own.
        XCTAssertTrue(hasThematicBreak(rendered))
    }

    /// True if any range of `s` is tagged as a thematic break.
    private func hasThematicBreak(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttribute(.markdownThematicBreak, in: NSRange(location: 0, length: s.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    // MARK: - Tables

    private let tableMarkdown = """
    | Name | Value |
    | ---- | ----- |
    | **bold** | two |
    | three | [link](https://apple.com) |
    """

    func testTableRendersAsTableAttachmentWithReachableCells() {
        let rendered = MarkdownAttributed.render(tableMarkdown)
        let table = firstTableAttachment(in: rendered)
        XCTAssertNotNil(table, "table should render as a MarkdownTableAttachment")

        // Cell text is reachable straight from the attachment.
        XCTAssertEqual(table?.headerCells.map(\.string), ["Name", "Value"])
        XCTAssertEqual(table?.rows.count, 2)
        XCTAssertEqual(table?.rows[0].map(\.string), ["bold", "two"])
        XCTAssertEqual(table?.rows[1].map(\.string), ["three", "link"])
    }

    func testTableCellsGoThroughInlineRendering() throws {
        let table = try XCTUnwrap(firstTableAttachment(in: MarkdownAttributed.render(tableMarkdown)))

        // Header cells are bold.
        let headerFont = table.headerCells[0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(headerFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        // **bold** in a body cell keeps its bold trait.
        let boldFont = table.rows[0][0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        // A link in a body cell keeps its .link attribute.
        let link = table.rows[1][1].attribute(.link, at: 0, effectiveRange: nil) as? URL
        XCTAssertEqual(link, URL(string: "https://apple.com"))
    }

    func testTableGridViewExposesCellText() throws {
        let table = try XCTUnwrap(firstTableAttachment(in: MarkdownAttributed.render(tableMarkdown)))
        let grid = table.makeGridView()
        XCTAssertEqual(grid.numberOfRows, 3)     // header + 2 body rows
        XCTAssertEqual(grid.numberOfColumns, 2)

        func text(atColumn column: Int, row: Int) -> String? {
            (grid.cell(atColumnIndex: column, rowIndex: row).contentView as? NSTextField)?
                .attributedStringValue.string
        }
        XCTAssertEqual(text(atColumn: 0, row: 0), "Name")
        XCTAssertEqual(text(atColumn: 1, row: 0), "Value")
        XCTAssertEqual(text(atColumn: 0, row: 1), "bold")
        XCTAssertEqual(text(atColumn: 1, row: 2), "link")
    }

    func testTableViewProviderHostsGridUnderTextKit2() throws {
        let rendered = MarkdownAttributed.render(tableMarkdown)
        let table = try XCTUnwrap(firstTableAttachment(in: rendered))

        // Stand up a real TextKit 2 stack to obtain an NSTextLocation.
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(rendered)

        let provider = try XCTUnwrap(
            table.viewProvider(for: nil, location: layoutManager.documentRange.location, textContainer: nil)
        )
        XCTAssertTrue(provider.tracksTextAttachmentViewBounds)
        provider.loadView()
        let container = try XCTUnwrap(provider.view as? MarkdownTableContainerView)
        let grid = container.grid
        let firstCell = (grid.cell(atColumnIndex: 0, rowIndex: 0).contentView as? NSTextField)?
            .attributedStringValue.string
        XCTAssertEqual(firstCell, "Name")
        XCTAssertGreaterThan(grid.fittingSize.width, 0)
    }

    // MARK: - Misc

    func testEmptyInputRendersEmptyString() {
        XCTAssertEqual(MarkdownAttributed.render("").string, "")
    }

    func testNoTrailingNewline() {
        XCTAssertFalse(MarkdownAttributed.render("last line").string.hasSuffix("\n"))
    }

    func testKitchenSinkDoesNotCrash() {
        let markdown = """
        # Title

        Body with **bold**, *italic*, ~~strike~~, `code`, and a [link](https://apple.com).

        > quote level one
        > > quote level two with a list:
        > > 1. first
        > > 2. second

        - [x] done
        - [ ] pending
          - nested bullet

        ```swift
        let x = 1
        ```

        ---

        | A | B |
        |---|---|
        | 1 | 2 |

        ![missing](nope.png)
        """
        let rendered = MarkdownAttributed.render(markdown)
        XCTAssertGreaterThan(rendered.length, 0)
        XCTAssertNotNil(firstTableAttachment(in: rendered))
    }

    // MARK: - Breaks

    func testSoftBreakRendersAsSpace() {
        let rendered = MarkdownAttributed.render("line one\nline two")
        XCTAssertEqual(rendered.string, "line one line two")
    }

    func testHardLineBreakRendersAsLineSeparator() {
        // A backslash before the newline is a CommonMark hard break.
        let rendered = MarkdownAttributed.render("alpha\\\nbravo")
        XCTAssertEqual(rendered.string, "alpha\u{2028}bravo")
    }

    // MARK: - Raw HTML

    func testInlineHTMLRendersLiterallyInCodeVoice() {
        let rendered = MarkdownAttributed.render("Some <b>bold-ish</b> text.")
        let attrs = attributes(of: "<b>", in: rendered)
        XCTAssertTrue((attrs[.font] as? NSFont)?.isFixedPitch ?? false)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, style.bodyFont.pointSize)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
        // The text between the tags stays plain prose.
        XCTAssertEqual(attributes(of: "bold-ish", in: rendered)[.font] as? NSFont, style.bodyFont)
        XCTAssertNil(attributes(of: "bold-ish", in: rendered)[.backgroundColor])
    }

    func testHTMLBlockRendersVerbatimStyledLikeACodeBlock() {
        let rendered = MarkdownAttributed.render("<div>\n  <p>hi</p>\n</div>")
        XCTAssertTrue(rendered.string.contains("<div>"))
        XCTAssertTrue(rendered.string.contains("<p>hi</p>"))
        let attrs = attributes(of: "<div>", in: rendered)
        XCTAssertEqual(attrs[.font] as? NSFont, style.monospacedFont)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, style.textColor)
    }

    func testHTMLBlockIsNotSentToTheCodeFormatter() {
        var called = false
        var custom = MarkdownStyle.default
        custom.codeFormatter = { code, _ in
            called = true
            return NSAttributedString(string: code)
        }
        let rendered = MarkdownAttributed.render("<div>\n  raw\n</div>", style: custom)
        XCTAssertFalse(called)
        XCTAssertTrue(rendered.string.contains("<div>"))
    }

    // MARK: - Symbol links, autolinks, childless links

    func testSymbolLinkRendersDestinationInCodeVoice() {
        let rendered = renderWithOptions("Use ``MyType/method(_:)`` now.", options: [.parseSymbolLinks])
        let attrs = attributes(of: "MyType/method(_:)", in: rendered)
        XCTAssertTrue((attrs[.font] as? NSFont)?.isFixedPitch ?? false)
        XCTAssertEqual(attrs[.backgroundColor] as? NSColor, style.codeBackgroundColor)
    }

    func testAutolinkRendersAsLink() {
        let rendered = MarkdownAttributed.render("Visit <https://swift.org> today.")
        let attrs = attributes(of: "https://swift.org", in: rendered)
        XCTAssertEqual(attrs[.link] as? URL, URL(string: "https://swift.org"))
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, style.linkColor)
    }

    func testChildlessLinkFallsBackToItsDestination() {
        // Only programmatic trees can produce a Link with no children.
        let document = Markdown.Document([Paragraph(Markdown.Link(destination: "https://example.com"))] as [BlockMarkup])
        var renderer = AttributedRenderer(style: .default)
        let rendered = renderer.visit(document)
        XCTAssertTrue(rendered.string.contains("https://example.com"))
        XCTAssertNotNil(attributes(of: "https://example.com", in: rendered)[.link])
    }

    // MARK: - Custom nodes (programmatic trees only)

    func testCustomInlineRendersItsText() {
        let document = Markdown.Document(
            [Paragraph(Markdown.Text("before "), CustomInline("custom inline"))] as [BlockMarkup]
        )
        var renderer = AttributedRenderer(style: .default)
        let rendered = renderer.visit(document)
        XCTAssertTrue(rendered.string.contains("custom inline"))
        XCTAssertEqual(attributes(of: "custom inline", in: rendered)[.font] as? NSFont, style.bodyFont)
    }

    func testCustomBlockRendersItsChildren() {
        let document = Markdown.Document(
            [CustomBlock([Paragraph(Markdown.Text("custom block body"))] as [BlockMarkup])] as [BlockMarkup]
        )
        var renderer = AttributedRenderer(style: .default)
        let rendered = renderer.visit(document)
        XCTAssertTrue(rendered.string.contains("custom block body"))
    }

    // MARK: - Block directives & inline attributes

    func testBlockDirectiveRendersChildrenAndSkipsItsName() {
        let source = """
        @Metadata {
          Directive body paragraph.
        }
        """
        let rendered = renderWithOptions(source, options: [.parseBlockDirectives])
        XCTAssertTrue(rendered.string.contains("Directive body paragraph."))
        XCTAssertFalse(rendered.string.contains("Metadata"))
        XCTAssertFalse(rendered.string.contains("@"))
    }

    func testInlineAttributesRendersChildrenAndSkipsTheAttributes() {
        let rendered = MarkdownAttributed.render("Look ^[styled text](rainbow: extreme) here.")
        XCTAssertTrue(rendered.string.contains("styled text"))
        XCTAssertFalse(rendered.string.contains("rainbow"))
        XCTAssertEqual(attributes(of: "styled text", in: rendered)[.font] as? NSFont, style.bodyFont)
    }

    // MARK: - Doxygen commands

    func testDoxygenCommandsRenderWithBoldLabels() {
        let source = #"""
        \param coordinate The place to go.

        \returns A boolean.

        \note Stay hydrated.
        """#
        let rendered = renderWithOptions(source, options: [.parseBlockDirectives, .parseMinimalDoxygen])
        XCTAssertTrue(rendered.string.contains("Parameter coordinate: The place to go."))
        XCTAssertTrue(rendered.string.contains("Returns: A boolean."))
        XCTAssertTrue(rendered.string.contains("Note: Stay hydrated."))
        XCTAssertTrue(font(of: "Parameter coordinate:", in: rendered)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "the Doxygen label should be bold")
        XCTAssertFalse(font(of: "The place to go.", in: rendered)?.fontDescriptor.symbolicTraits.contains(.bold) ?? true,
                       "the description should stay regular weight")
    }

    // MARK: - Table alignment & spans

    func testTableColumnAlignmentsExposedAndAppliedToGrid() throws {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a    | b      | c     |
        """
        let table = try XCTUnwrap(firstTableAttachment(in: MarkdownAttributed.render(markdown)))
        XCTAssertEqual(table.columnAlignments, [.left, .center, .right])

        let grid = table.makeGridView()
        XCTAssertEqual(grid.column(at: 0).xPlacement, .leading)
        XCTAssertEqual(grid.column(at: 1).xPlacement, .center)
        XCTAssertEqual(grid.column(at: 2).xPlacement, .trailing)
        let centerLabel = grid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSTextField
        XCTAssertEqual(centerLabel?.alignment, .center)
    }

    func testTableCellSpansExposedAndMergedInGrid() throws {
        let markdown = """
        | one | two | three |
        | --- | --- | ----- |
        | big      || small |
        | ^        || small |
        """
        let table = try XCTUnwrap(firstTableAttachment(in: MarkdownAttributed.render(markdown)))
        // The spanning cell holds the content; covered cells are empty placeholders.
        XCTAssertEqual(table.rows[0].map(\.string), ["big", "", "small"])
        XCTAssertEqual(table.rows[1].map(\.string), ["", "", "small"])
        XCTAssertEqual(table.rowSpans[0][0], MarkdownTableAttachment.CellSpan(colspan: 2, rowspan: 2))
        XCTAssertEqual(table.rowSpans[0][1], MarkdownTableAttachment.CellSpan(colspan: 0, rowspan: 1))

        let grid = table.makeGridView()
        XCTAssertEqual(grid.numberOfColumns, 3)
        XCTAssertEqual(grid.numberOfRows, 3)
        let head = grid.cell(atColumnIndex: 0, rowIndex: 1).contentView as? NSTextField
        XCTAssertEqual(head?.attributedStringValue.string, "big")
        XCTAssertGreaterThan(grid.fittingSize.width, 0)
    }

    // MARK: - Nested-block indent composition

    /// The paragraph style at the first attachment character in `rendered`.
    private func attachmentParagraphStyle(in rendered: NSAttributedString,
                                          file: StaticString = #filePath, line: UInt = #line) -> NSParagraphStyle? {
        let range = (rendered.string as NSString).range(of: "\u{FFFC}")
        guard range.location != NSNotFound else {
            XCTFail("no attachment found in \(rendered.string)", file: file, line: line)
            return nil
        }
        return rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    func testTableInsideListItemIndentsWithTheList() {
        let markdown = """
        - item text

          | A |
          |---|
          | 1 |
        """
        let rendered = MarkdownAttributed.render(markdown)
        let ps = attachmentParagraphStyle(in: rendered)
        XCTAssertEqual(ps?.headIndent, style.listIndent)
        XCTAssertEqual(ps?.firstLineHeadIndent, style.listIndent)
    }

    func testTableInsideBlockQuoteIndentsWithTheQuote() {
        let markdown = """
        > | A |
        > |---|
        > | 1 |
        """
        let rendered = MarkdownAttributed.render(markdown)
        let ps = attachmentParagraphStyle(in: rendered)
        XCTAssertEqual(ps?.headIndent, style.quoteIndent)
        XCTAssertEqual(ps?.firstLineHeadIndent, style.quoteIndent)
    }

    func testQuoteInsideListComposesIndents() {
        let markdown = """
        - item
          > quoted in list
        """
        let ps = paragraphStyle(of: "quoted in list", in: MarkdownAttributed.render(markdown))
        XCTAssertEqual(ps?.headIndent, style.quoteIndent + style.listIndent)
    }

    func testHTMLBlockInsideBlockQuoteIndents() {
        let rendered = MarkdownAttributed.render("> <div>raw</div>")
        let ps = paragraphStyle(of: "<div>raw</div>", in: rendered)
        XCTAssertEqual(ps?.headIndent, style.quoteIndent)
        XCTAssertEqual(attributes(of: "<div>raw</div>", in: rendered)[.foregroundColor] as? NSColor,
                       style.secondaryTextColor)
    }

    // MARK: - Full-coverage kitchen sink

    /// One document exercising every construct swift-markdown can parse
    /// (symbol links, block directives, and Doxygen commands included when
    /// parsed with the matching options).
    private static let fullKitchenSink = #"""
    # Kitchen Sink

    Body with **bold**, *italic*, ~~strike~~, `code`, a [link](https://apple.com),
    an autolink <https://swift.org>, inline <b>HTML</b>, an image ![image alt](nope.png),
    a symbol link ``MyType/method(_:)``, and ^[attributed text](rainbow: extreme).
    Hard break line one.\
    Line two.

    > Quoted paragraph.
    > > Deeper quote.

    - bullet one with a nested table:

      | N |
      |---|
      | 1 |

    - [x] done task
    - [ ] pending task
      - nested bullet

    1. ordered one
    2. ordered two

    ```swift
    let x = 1
    ```

    <div>
      <p>html block</p>
    </div>

    ---

    | Left | Center | Right |
    |:-----|:------:|------:|
    | a    | b      | c     |
    | big         || small |
    | ^           || small |

    @Metadata {
      Directive body paragraph.
    }

    \param coordinate The coordinate to travel to.

    \returns A number.

    \note Be careful.

    \discussion Longer discussion text.

    \abstract A short abstract.
    """#

    private static let allParseOptions: ParseOptions = [
        .parseBlockDirectives, .parseSymbolLinks, .parseMinimalDoxygen,
    ]

    func testFullKitchenSinkSpotChecks() throws {
        let rendered = renderWithOptions(Self.fullKitchenSink, options: Self.allParseOptions)
        let text = rendered.string

        // Headings and inline styles.
        XCTAssertEqual(font(of: "Kitchen Sink", in: rendered)?.pointSize,
                       style.headingFont(forLevel: 1).pointSize)
        XCTAssertTrue(font(of: "bold", in: rendered)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        XCTAssertTrue(font(of: "italic", in: rendered)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
        XCTAssertNotNil(attributes(of: "strike", in: rendered)[.strikethroughStyle])
        XCTAssertTrue(font(of: "code", in: rendered)?.isFixedPitch ?? false)

        // Links, autolinks, symbol links, inline HTML, inline attributes, images.
        XCTAssertEqual(attributes(of: "link", in: rendered)[.link] as? URL, URL(string: "https://apple.com"))
        XCTAssertNotNil(attributes(of: "https://swift.org", in: rendered)[.link])
        XCTAssertTrue(font(of: "MyType/method(_:)", in: rendered)?.isFixedPitch ?? false)
        XCTAssertTrue(font(of: "<b>", in: rendered)?.isFixedPitch ?? false)
        XCTAssertTrue(text.contains("attributed text"))
        XCTAssertFalse(text.contains("rainbow"))
        XCTAssertTrue(text.contains("image alt"), "unresolvable image should fall back to alt text")

        // Breaks.
        XCTAssertTrue(text.contains("Hard break line one.\u{2028}Line two."))

        // Quotes, lists, tasks.
        XCTAssertEqual(attributes(of: "Quoted paragraph.", in: rendered)[.markdownQuoteDepth] as? Int, 1)
        XCTAssertEqual(attributes(of: "Deeper quote.", in: rendered)[.markdownQuoteDepth] as? Int, 2)
        XCTAssertTrue(text.contains("\u{2611}\tdone task"))
        XCTAssertTrue(text.contains("\u{2610}\tpending task"))
        XCTAssertTrue(text.contains("\u{2022}\tnested bullet"))
        XCTAssertTrue(text.contains("1.\tordered one"))

        // Code, HTML block, thematic break.
        XCTAssertEqual(font(of: "let x = 1", in: rendered), style.monospacedFont)
        XCTAssertTrue(text.contains("<p>html block</p>"))
        XCTAssertEqual(attributes(of: "<p>html block</p>", in: rendered)[.backgroundColor] as? NSColor,
                       style.codeBackgroundColor)
        XCTAssertTrue(hasThematicBreak(rendered))

        // Tables: the one nested in the list plus the aligned/spanned one.
        let tables = allTableAttachments(in: rendered)
        XCTAssertEqual(tables.count, 2)
        let aligned = try XCTUnwrap(tables.last)
        XCTAssertEqual(aligned.columnAlignments, [.left, .center, .right])
        XCTAssertEqual(aligned.rowSpans[1][0], MarkdownTableAttachment.CellSpan(colspan: 2, rowspan: 2))

        // Directives and Doxygen.
        XCTAssertTrue(text.contains("Directive body paragraph."))
        XCTAssertFalse(text.contains("Metadata"))
        XCTAssertTrue(text.contains("Parameter coordinate: The coordinate to travel to."))
        XCTAssertTrue(text.contains("Returns: A number."))
        XCTAssertTrue(text.contains("Note: Be careful."))
        XCTAssertTrue(text.contains("Longer discussion text."))
        XCTAssertTrue(text.contains("A short abstract."))
    }

    /// Guard rail against silent fallthroughs: every node type present in the
    /// kitchen-sink tree (plus the programmatic-only custom nodes) must render
    /// SOME output when visited on its own — a node type whose standalone
    /// render is empty has fallen through the visitor unhandled.
    func testGuardRailEveryNodeTypePresentProducesOutput() {
        let parsed = Markdown.Document(parsing: Self.fullKitchenSink, options: Self.allParseOptions)
        // CustomBlock/CustomInline exist only in programmatic trees — graft one of each in.
        var blocks: [BlockMarkup] = Array(parsed.blockChildren)
        blocks.append(CustomBlock(
            [Paragraph(Markdown.Text("custom block, "), CustomInline("custom inline"))] as [BlockMarkup]
        ))
        let document = Markdown.Document(blocks)

        var seenTypes: Set<String> = []
        var emptyTypes: Set<String> = []
        walk(document) { node in
            let typeName = String(describing: type(of: node))
            seenTypes.insert(typeName)
            // Cells covered by a spanning neighbor are legitimately empty.
            if let cell = node as? Markdown.Table.Cell, cell.colspan == 0 || cell.rowspan == 0 {
                return
            }
            var renderer = AttributedRenderer(style: .default)
            if renderer.visit(node).length == 0 {
                emptyTypes.insert(typeName)
            }
        }
        XCTAssertTrue(emptyTypes.isEmpty, "node types rendering no output: \(emptyTypes.sorted())")

        // The kitchen sink itself must keep exercising the full node set —
        // if parsing changes and a type drops out, this list flags it.
        let expected: Set<String> = [
            "Document", "Heading", "Paragraph", "BlockQuote", "CodeBlock", "HTMLBlock",
            "ThematicBreak", "OrderedList", "UnorderedList", "ListItem", "BlockDirective",
            "CustomBlock", "Table", "Head", "Body", "Row", "Cell",
            "Text", "Emphasis", "Strong", "Strikethrough", "InlineCode", "InlineHTML",
            "Image", "Link", "SymbolLink", "SoftBreak", "LineBreak", "InlineAttributes",
            "CustomInline", "DoxygenParameter", "DoxygenReturns", "DoxygenNote",
            "DoxygenDiscussion", "DoxygenAbstract",
        ]
        XCTAssertTrue(expected.isSubset(of: seenTypes),
                      "kitchen sink no longer produces: \(expected.subtracting(seenTypes).sorted())")
    }
}

extension MarkdownAttributedTests {
    /// Tables render inside a chrome-drawing container that carries the style's
    /// border color and hosts the grid — the fix for "structured but borderless".
    func testTableRendersInsideBorderedContainer() throws {
        var style = MarkdownStyle.default
        style.tableBorderColor = .systemRed
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let rendered = MarkdownAttributed.render(md, style: style)
        var attachment: MarkdownTableAttachment?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { v, _, stop in
            if let t = v as? MarkdownTableAttachment { attachment = t; stop.pointee = true }
        }
        let table = try XCTUnwrap(attachment)
        XCTAssertEqual(table.borderColor, .systemRed)
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(rendered)
        let provider = try XCTUnwrap(table.viewProvider(for: nil, location: layoutManager.documentRange.location, textContainer: nil) as? MarkdownTableViewProvider)
        provider.loadView()
        let container = try XCTUnwrap(provider.view as? MarkdownTableContainerView)
        XCTAssertTrue(container.subviews.contains(container.grid))
        // Refit to two widths: the grid must stay hosted and sized within budget.
        table.fit(grid: container.grid, to: 300 - MarkdownTableContainerView.padding.width * 2)
        table.fit(grid: container.grid, to: 600 - MarkdownTableContainerView.padding.width * 2)
        XCTAssertTrue(container.subviews.contains(container.grid))
    }
}

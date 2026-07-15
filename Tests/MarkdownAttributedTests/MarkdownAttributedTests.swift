//
//  MarkdownAttributedTests.swift
//  Tests for SwiftMarkdownAttributed
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit
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
        var found: MarkdownTableAttachment?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, stop in
            if let table = value as? MarkdownTableAttachment {
                found = table
                stop.pointee = true
            }
        }
        return found
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
        XCTAssertTrue(rendered.string.contains("\u{2500}\u{2500}\u{2500}"))
        XCTAssertEqual(attributes(of: "\u{2500}", in: rendered)[.foregroundColor] as? NSColor,
                       style.secondaryTextColor)
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
        let grid = try XCTUnwrap(provider.view as? NSGridView)
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
}

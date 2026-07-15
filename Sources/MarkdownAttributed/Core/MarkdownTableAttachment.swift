//
//  MarkdownTableAttachment.swift
//  SwiftMarkdownAttributed
//
//  A GFM table rendered as an NSTextAttachment whose TextKit 2 view provider
//  hosts an NSGridView built from the (already inline-rendered) cell strings.
//  The cell data lives on the attachment itself so hosts and tests can reach
//  it without instantiating any view.
//
//  Created by David Sherlock on 7/16/26.
//

import AppKit

/// A Markdown (GFM) table embedded in the rendered attributed string.
///
/// Under TextKit 2 the attachment vends a ``NSTextAttachmentViewProvider``
/// hosting an `NSGridView`, so the table lays out and draws as a live view
/// inside the text. The header and body cell content — each cell an
/// `NSAttributedString` produced by the same inline renderer as the rest of
/// the document — is exposed as data on the attachment.
public final class MarkdownTableAttachment: NSTextAttachment {

    /// The header-row cells, in column order (bold by construction).
    public let headerCells: [NSAttributedString]

    /// The body rows, outer array top-to-bottom, inner arrays in column order.
    public let rows: [[NSAttributedString]]

    /// Creates the attachment from already inline-rendered cell strings.
    init(headerCells: [NSAttributedString], rows: [[NSAttributedString]]) {
        self.headerCells = headerCells
        self.rows = rows
        super.init(data: nil, ofType: nil)
    }

    /// Required by `NSTextAttachment`; decodes as an empty table (the cell
    /// data is not archived — the attachment is meant to be built in-process
    /// by the renderer, not round-tripped through a coder).
    public required init?(coder: NSCoder) {
        self.headerCells = []
        self.rows = []
        super.init(coder: coder)
    }

    /// Vends the TextKit 2 view provider that hosts the table's `NSGridView`.
    ///
    /// - Note: Only called by TextKit 2 layout (`NSTextView(usingTextLayoutManager: true)`);
    ///   under TextKit 1 the table renders as a blank attachment glyph.
    public override func viewProvider(
        for parentView: NSView?,
        location: NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = MarkdownTableViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    /// Builds the `NSGridView` shown for this table: one label per cell,
    /// ragged rows padded to the widest row's column count.
    func makeGridView() -> NSGridView {
        let columnCount = max(headerCells.count, rows.map(\.count).max() ?? 0)

        func labelRow(_ cells: [NSAttributedString]) -> [NSView] {
            (0..<max(columnCount, 1)).map { index in
                let text = index < cells.count ? cells[index] : NSAttributedString()
                let label = NSTextField(labelWithAttributedString: text)
                label.translatesAutoresizingMaskIntoConstraints = false
                return label
            }
        }

        var rowViews: [[NSView]] = []
        if !headerCells.isEmpty { rowViews.append(labelRow(headerCells)) }
        for row in rows { rowViews.append(labelRow(row)) }
        if rowViews.isEmpty { rowViews.append(labelRow([])) }

        let grid = NSGridView(views: rowViews)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4
        grid.columnSpacing = 16
        if !headerCells.isEmpty, grid.numberOfRows > 0 {
            grid.row(at: 0).bottomPadding = 4
        }
        return grid
    }
}

/// The TextKit 2 view provider for ``MarkdownTableAttachment``: hosts the
/// table's `NSGridView` and reports its fitting size as the attachment bounds.
final class MarkdownTableViewProvider: NSTextAttachmentViewProvider {

    /// Builds the hosted grid view (an empty `NSView` for a foreign attachment).
    override func loadView() {
        if let attachment = textAttachment as? MarkdownTableAttachment {
            view = attachment.makeGridView()
        } else {
            view = NSView()
        }
    }

    /// Reports the grid's fitting size so the line fragment reserves room for it.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        if view == nil { loadView() }
        let size = view?.fittingSize ?? .zero
        return CGRect(origin: .zero, size: size)
    }
}

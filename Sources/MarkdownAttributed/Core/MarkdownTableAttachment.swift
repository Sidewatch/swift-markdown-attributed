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

    /// The column/row span of one table cell.
    ///
    /// `1`/`1` describes a normal cell. A value greater than one means the
    /// cell spreads over that many columns/rows (GFM `||` / `^` span syntax);
    /// `0` means the cell is covered by a spanning neighbor — it has no
    /// content and its grid position is merged away.
    public struct CellSpan: Equatable, Sendable {
        /// Columns the cell spreads over (0 = covered by a cell to its left).
        public let colspan: Int
        /// Rows the cell spreads over (0 = covered by a cell above it).
        public let rowspan: Int

        /// Creates a span; the defaults describe a normal non-spanning cell.
        public init(colspan: Int = 1, rowspan: Int = 1) {
            self.colspan = colspan
            self.rowspan = rowspan
        }
    }

    /// The header-row cells, in column order (bold by construction).
    public let headerCells: [NSAttributedString]

    /// The body rows, outer array top-to-bottom, inner arrays in column order.
    /// Cells covered by a spanning neighbor are present but empty, keeping
    /// every row aligned to the table's column grid.
    public let rows: [[NSAttributedString]]

    /// Per-column text alignment from the table's delimiter row (`:--`, `:-:`,
    /// `--:`); `.natural` for unspecified columns. May be empty (legacy data).
    public let columnAlignments: [NSTextAlignment]

    /// Spans for the header cells, parallel to ``headerCells``.
    public let headerSpans: [CellSpan]

    /// Spans for the body cells, parallel to ``rows``.
    public let rowSpans: [[CellSpan]]

    /// Creates the attachment from already inline-rendered cell strings plus
    /// the table's column alignments and cell spans (both optional — the
    /// defaults describe a plain non-spanning, naturally-aligned table).
    init(
        headerCells: [NSAttributedString],
        rows: [[NSAttributedString]],
        columnAlignments: [NSTextAlignment] = [],
        headerSpans: [CellSpan] = [],
        rowSpans: [[CellSpan]] = []
    ) {
        self.headerCells = headerCells
        self.rows = rows
        self.columnAlignments = columnAlignments
        self.headerSpans = headerSpans
        self.rowSpans = rowSpans
        super.init(data: nil, ofType: nil)
    }

    /// Required by `NSTextAttachment`; decodes as an empty table (the cell
    /// data is not archived — the attachment is meant to be built in-process
    /// by the renderer, not round-tripped through a coder).
    public required init?(coder: NSCoder) {
        self.headerCells = []
        self.rows = []
        self.columnAlignments = []
        self.headerSpans = []
        self.rowSpans = []
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
    /// ragged rows padded to the widest row's column count, columns aligned
    /// per the delimiter row, and spanning cells merged into their neighbors.
    func makeGridView() -> NSGridView {
        let columnCount = max(headerCells.count, rows.map(\.count).max() ?? 0)

        func labelRow(_ cells: [NSAttributedString]) -> [NSView] {
            (0..<max(columnCount, 1)).map { index in
                let text = index < cells.count ? cells[index] : NSAttributedString()
                let label = NSTextField(labelWithAttributedString: text)
                label.translatesAutoresizingMaskIntoConstraints = false
                if index < columnAlignments.count { label.alignment = columnAlignments[index] }
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
        for column in 0..<grid.numberOfColumns where column < columnAlignments.count {
            switch columnAlignments[column] {
            case .center: grid.column(at: column).xPlacement = .center
            case .right: grid.column(at: column).xPlacement = .trailing
            default: grid.column(at: column).xPlacement = .leading
            }
        }
        mergeSpans(in: grid)
        return grid
    }

    /// Merges the grid regions occupied by spanning cells (colspan/rowspan
    /// greater than one). Covered cells (span 0) are skipped — they are the
    /// empty placeholders the merge swallows — and every range is clamped to
    /// the grid bounds so malformed span data can never crash the view.
    private func mergeSpans(in grid: NSGridView) {
        var spansByGridRow: [[CellSpan]] = []
        if !headerCells.isEmpty { spansByGridRow.append(headerSpans) }
        spansByGridRow.append(contentsOf: rowSpans)

        for (rowIndex, spans) in spansByGridRow.enumerated() where rowIndex < grid.numberOfRows {
            for (columnIndex, span) in spans.enumerated() where columnIndex < grid.numberOfColumns {
                guard span.colspan > 0, span.rowspan > 0 else { continue }        // covered cell
                guard span.colspan > 1 || span.rowspan > 1 else { continue }      // normal cell
                let width = min(span.colspan, grid.numberOfColumns - columnIndex)
                let height = min(span.rowspan, grid.numberOfRows - rowIndex)
                guard width >= 1, height >= 1, width > 1 || height > 1 else { continue }
                grid.mergeCells(
                    inHorizontalRange: NSRange(location: columnIndex, length: width),
                    verticalRange: NSRange(location: rowIndex, length: height)
                )
            }
        }
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

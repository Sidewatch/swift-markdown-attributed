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

    /// Stroke color for the table's chrome (outer border + row/column rules).
    public let borderColor: NSColor

    /// Optional fill behind the header row; `nil` draws none.
    public let headerBackground: NSColor?

    /// Creates the attachment from already inline-rendered cell strings plus
    /// the table's column alignments and cell spans (both optional — the
    /// defaults describe a plain non-spanning, naturally-aligned table).
    init(
        headerCells: [NSAttributedString],
        rows: [[NSAttributedString]],
        columnAlignments: [NSTextAlignment] = [],
        headerSpans: [CellSpan] = [],
        rowSpans: [[CellSpan]] = [],
        borderColor: NSColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25),
        headerBackground: NSColor? = nil
    ) {
        self.headerCells = headerCells
        self.rows = rows
        self.columnAlignments = columnAlignments
        self.headerSpans = headerSpans
        self.rowSpans = rowSpans
        self.borderColor = borderColor
        self.headerBackground = headerBackground
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
        self.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25)
        self.headerBackground = nil
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
    /// `@MainActor`: constructs and measures `NSTextField`/`NSGridView` instances, which are
    /// main-thread-only by nature. Every caller is TextKit layout or a host preparing to
    /// display, both already on main.
    @MainActor
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
        // Rules are drawn at the midpoint of the gap, so cell padding ≈ spacing/2.
        // GitHub uses ~6px vertical / ~13px horizontal — so ~12 / ~26 here.
        grid.rowSpacing = 12
        grid.columnSpacing = 26
        if !headerCells.isEmpty, grid.numberOfRows > 0 {
            grid.row(at: 0).bottomPadding = 6
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

    /// Rasterizes the table (grid + border chrome) to an image at `maxWidth`, for
    /// hosts that can't show the view-based attachment: **TextKit 1** renders
    /// `viewProvider` as a blank glyph, so a TK1 text view sets this image as the
    /// attachment's `image`. Call once the surface width is known; re-call on a width
    /// or theme change. Returns nil if there's no room to lay the table out.
    /// `@MainActor`: constructs and measures `NSTextField`/`NSGridView` instances, which are
    /// main-thread-only by nature. Every caller is TextKit layout or a host preparing to
    /// display, both already on main.
    @MainActor
    public func renderImage(maxWidth: CGFloat) -> NSImage? {
        let inner = maxWidth - MarkdownTableContainerView.padding.width * 2
        guard inner > 20 else { return nil }
        let grid = makeGridView()
        fit(grid: grid, to: inner)
        let container = MarkdownTableContainerView(grid: grid, borderColor: borderColor,
                                                   headerBackground: headerBackground,
                                                   hasHeader: !headerCells.isEmpty)
        let size = container.fittingSize
        guard size.width > 1, size.height > 1 else { return nil }
        container.frame = NSRect(origin: .zero, size: size)
        container.layoutSubtreeIfNeeded()   // border pass reads live cell geometry
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return nil }
        container.cacheDisplay(in: container.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Fits `grid` (built by ``makeGridView()``) into `maxWidth` points.
    ///
    /// The hosting text surface has no horizontal scroller, so a table wider
    /// than the line fragment would simply be clipped — real-world tables
    /// carry whole sentences per cell and can measure thousands of points
    /// wide as single-line labels. When the grid's natural width overflows,
    /// the overflowing columns are shrunk (columns already narrower than
    /// their fair share keep their natural width; the wide ones split what
    /// remains) and their labels switched to word-wrapping at the allotted
    /// width, trading width for height. Within budget, the grid is left at
    /// its natural single-line size. Idempotent per width — layout calls
    /// ``MarkdownTableViewProvider/attachmentBounds(for:location:textContainer:proposedLineFragment:position:)``
    /// repeatedly.
    @MainActor
    func fit(grid: NSGridView, to maxWidth: CGFloat) {
        let columnCount = grid.numberOfColumns
        guard maxWidth > 0, columnCount > 0, grid.numberOfRows > 0 else { return }
        let cells = TableCell.collect(from: grid)
        // Reset to single-line first — wrapping labels from a previous fit measure at their
        // allotted width, so this keeps the pass idempotent and lets columns grow back.
        for cell in cells { cell.label.setSingleLine() }
        let natural = Self.naturalWidths(cells, columnCount: columnCount, spacing: grid.columnSpacing)
        let available = maxWidth - grid.columnSpacing * CGFloat(max(0, columnCount - 1))
        guard natural.reduce(0, +) > available, available > 0 else { return }
        let allotted = Self.allot(natural, within: available)
        for cell in cells {
            let cols = cell.columns(clampedTo: columnCount)
            let bridged = grid.columnSpacing * CGFloat(cols.count - 1)
            let allottedWidth = cols.reduce(0) { $0 + allotted[$1] } + bridged
            let naturalWidth = cols.reduce(0) { $0 + natural[$1] } + bridged
            if allottedWidth < naturalWidth { cell.label.wrap(at: floor(allottedWidth)) }
        }
    }

    /// One label in the grid with the column span it covers. `NSGridView` returns a merged
    /// cell's HEAD label for every covered position, so a naive per-position sweep counts a
    /// colspan-N label N times; this dedupes by label identity and extends the span instead.
    private struct TableCell {
        let label: NSTextField
        let column: Int
        var span: Int

        @MainActor static func collect(from grid: NSGridView) -> [TableCell] {
            var cells: [TableCell] = []
            var index: [ObjectIdentifier: Int] = [:]
            for row in 0..<grid.numberOfRows {
                for column in 0..<grid.numberOfColumns {
                    guard let label = grid.cell(atColumnIndex: column, rowIndex: row).contentView as? NSTextField else { continue }
                    if let i = index[ObjectIdentifier(label)] {
                        cells[i].span = max(cells[i].span, column - cells[i].column + 1)   // rowspan repeats keep the span
                        continue
                    }
                    index[ObjectIdentifier(label)] = cells.count
                    cells.append(TableCell(label: label, column: column, span: 1))
                }
            }
            return cells
        }

        func columns(clampedTo count: Int) -> Range<Int> { column..<min(column + span, count) }
    }

    /// Natural single-line width per column: the widest single-column label wins; a spanning
    /// label then widens its columns only by the deficit its combined columns (plus the spacing
    /// it bridges) can't already hold, split evenly — never its full width per column.
    @MainActor private static func naturalWidths(_ cells: [TableCell], columnCount: Int, spacing: CGFloat) -> [CGFloat] {
        var natural = [CGFloat](repeating: 0, count: columnCount)
        for cell in cells where cell.span == 1 {
            natural[cell.column] = max(natural[cell.column], ceil(cell.label.fittingSize.width))
        }
        for cell in cells where cell.span > 1 {
            let cols = cell.columns(clampedTo: columnCount)
            let have = cols.reduce(0) { $0 + natural[$1] } + spacing * CGFloat(cols.count - 1)
            let need = ceil(cell.label.fittingSize.width)
            if need > have { for c in cols { natural[c] += (need - have) / CGFloat(cols.count) } }
        }
        return natural
    }

    /// Distributes `available` across columns: columns whose natural width fits under the
    /// current fair share keep it; what's left is split among the wider ones, floored at
    /// `minColumnWidth` so a column never becomes unreadably narrow (even if that overflows).
    static func allot(_ natural: [CGFloat], within available: CGFloat, minColumnWidth: CGFloat = 40) -> [CGFloat] {
        var allotted = natural
        var flexible = Set(natural.indices)
        var remaining = available
        while !flexible.isEmpty {
            let fair = remaining / CGFloat(flexible.count)
            let fitting = flexible.filter { natural[$0] <= fair }
            if fitting.isEmpty {
                for column in flexible { allotted[column] = max(fair, minColumnWidth) }
                break
            }
            for column in fitting {
                allotted[column] = natural[column]
                remaining -= natural[column]
                flexible.remove(column)
            }
        }
        return allotted
    }

    /// Merges the grid regions occupied by spanning cells (colspan/rowspan
    /// greater than one). Covered cells (span 0) are skipped — they are the
    /// empty placeholders the merge swallows — and every range is clamped to
    /// the grid bounds so malformed span data can never crash the view.
    @MainActor
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

private extension NSTextField {
    /// Measure as one unwrapped line.
    func setSingleLine() {
        lineBreakMode = .byClipping
        usesSingleLineMode = false
        cell?.wraps = false
        maximumNumberOfLines = 1
        preferredMaxLayoutWidth = 0
    }

    /// Wrap by words at `width`.
    func wrap(at width: CGFloat) {
        lineBreakMode = .byWordWrapping
        usesSingleLineMode = false
        cell?.wraps = true
        maximumNumberOfLines = 0
        preferredMaxLayoutWidth = width
    }
}

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
    func fit(grid: NSGridView, to maxWidth: CGFloat) {
        let columnCount = grid.numberOfColumns
        guard maxWidth > 0, columnCount > 0, grid.numberOfRows > 0 else { return }

        // Enumerate every label ONCE, with the column span it covers.
        // `NSGridView` returns a merged cell's HEAD label for every covered
        // position, so a naive per-position sweep counts a colspan-N label N
        // times: its full width max'd into EVERY spanned column (spuriously
        // triggering the overflow path and starving the other columns), then
        // the wrap pass clamping it to a single column's allotment.
        struct Entry { let label: NSTextField; let column: Int; var span: Int }
        var entries: [Entry] = []
        var entryIndex: [ObjectIdentifier: Int] = [:]
        for row in 0..<grid.numberOfRows {
            for column in 0..<columnCount {
                guard let label = grid.cell(atColumnIndex: column, rowIndex: row).contentView as? NSTextField else { continue }
                let id = ObjectIdentifier(label)
                if let i = entryIndex[id] {
                    // Seen again: a covered position. Extend the colspan when it
                    // reaches further right (rowspan repeats keep the span as-is).
                    entries[i].span = max(entries[i].span, column - entries[i].column + 1)
                    continue
                }
                entryIndex[id] = entries.count
                entries.append(Entry(label: label, column: column, span: 1))
            }
        }
        /// The columns `entry` covers, clamped to the grid.
        func columns(of entry: Entry) -> Range<Int> {
            entry.column..<min(entry.column + entry.span, columnCount)
        }

        // Reset to single-line first — wrapping labels from a previous fit
        // measure at their allotted width, so this keeps the pass idempotent
        // and lets columns grow back when the pane widens.
        for entry in entries {
            entry.label.lineBreakMode = .byClipping
            entry.label.usesSingleLineMode = false
            entry.label.cell?.wraps = false
            entry.label.maximumNumberOfLines = 1
            entry.label.preferredMaxLayoutWidth = 0
        }

        // Natural (single-line) width of every column: widest single-column
        // label wins. A spanning label then widens its columns only by the
        // deficit its combined columns (plus the spacing it bridges) can't
        // already hold, split evenly — never its full width per column.
        var natural = [CGFloat](repeating: 0, count: columnCount)
        for entry in entries where entry.span == 1 {
            natural[entry.column] = max(natural[entry.column], ceil(entry.label.fittingSize.width))
        }
        for entry in entries where entry.span > 1 {
            let cols = columns(of: entry)
            let bridged = grid.columnSpacing * CGFloat(cols.count - 1)
            let have = cols.reduce(0) { $0 + natural[$1] } + bridged
            let need = ceil(entry.label.fittingSize.width)
            if need > have {
                let extra = (need - have) / CGFloat(cols.count)
                for c in cols { natural[c] += extra }
            }
        }

        let spacing = grid.columnSpacing * CGFloat(max(0, columnCount - 1))
        let available = maxWidth - spacing
        guard natural.reduce(0, +) > available, available > 0 else { return }

        // Distribute `available` across columns: repeatedly grant columns
        // whose natural width fits under the current fair share, then split
        // what's left among the wider ones (floored so a column never
        // becomes unreadably narrow, even if that overflows a hair).
        let minColumnWidth: CGFloat = 40
        var allotted = natural
        var flexible = Set(0..<columnCount)
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

        // Wrap the shrunk labels at their allotted width — a spanning label at
        // the SUM of its columns' allotments plus the spacing it bridges.
        for entry in entries {
            let cols = columns(of: entry)
            let bridged = grid.columnSpacing * CGFloat(cols.count - 1)
            let allottedWidth = cols.reduce(0) { $0 + allotted[$1] } + bridged
            let naturalWidth = cols.reduce(0) { $0 + natural[$1] } + bridged
            guard allottedWidth < naturalWidth else { continue }
            entry.label.lineBreakMode = .byWordWrapping
            entry.label.usesSingleLineMode = false
            entry.label.cell?.wraps = true
            entry.label.maximumNumberOfLines = 0
            entry.label.preferredMaxLayoutWidth = floor(allottedWidth)
        }
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

    /// Builds the hosted table view — the grid wrapped in a chrome-drawing
    /// container (an empty `NSView` for a foreign attachment).
    override func loadView() {
        if let attachment = textAttachment as? MarkdownTableAttachment {
            view = MarkdownTableContainerView(
                grid: attachment.makeGridView(),
                borderColor: attachment.borderColor,
                headerBackground: attachment.headerBackground,
                hasHeader: !attachment.headerCells.isEmpty
            )
        } else {
            view = NSView()
        }
    }

    /// Reports the grid's fitting size so the line fragment reserves room for
    /// it — after fitting the grid into the proposed line fragment's width
    /// (overflowing columns wrap rather than clip; see
    /// ``MarkdownTableAttachment/fit(grid:to:)``).
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        if view == nil { loadView() }
        if let container = view as? MarkdownTableContainerView,
           let attachment = textAttachment as? MarkdownTableAttachment {
            // The container adds padding around the grid so the cells breathe
            // against the border strokes — fit the grid to what remains.
            attachment.fit(grid: container.grid,
                           to: proposedLineFragment.width - MarkdownTableContainerView.padding.width * 2)
        }
        let size = view?.fittingSize ?? .zero
        return CGRect(origin: .zero, size: size)
    }
}


/// Hosts a table's `NSGridView` and draws its GitHub-style chrome: a rounded
/// 1px outer border, hairline rules between rows and columns, an emphasized
/// separator under the header row, and an optional header fill. `NSGridView`
/// is layout-only — it never draws lines — so all strokes live here, computed
/// from the grid's live cell geometry each draw so they stay correct across
/// ``MarkdownTableAttachment/fit(grid:to:)`` re-fits and wrapped-cell heights.
///
/// - Note: Column rules are drawn full-height, so a rare colspan-merged cell
///   is visually crossed by the rule of the column boundary it spans.
final class MarkdownTableContainerView: NSView {
    /// The hosted grid (reachable for tests and the provider's fit pass).
    let grid: NSGridView
    private let borderColor: NSColor
    private let headerBackground: NSColor?
    private let hasHeader: Bool

    /// Breathing room between the border strokes and the grid's cells.
    static let padding = NSSize(width: 10, height: 6)

    /// Top-left origin coordinates keep the header math orientation-stable.
    override var isFlipped: Bool { true }

    init(grid: NSGridView, borderColor: NSColor, headerBackground: NSColor?, hasHeader: Bool) {
        self.grid = grid
        self.borderColor = borderColor
        self.headerBackground = headerBackground
        self.hasHeader = hasHeader
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding.width),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding.width),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding.height),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding.height),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        needsDisplay = true   // rules follow the grid's settled geometry
    }

    /// Per-row vertical extents and per-column horizontal extents of the
    /// grid's visible cells, in this view's (flipped) coordinates.
    ///
    /// `NSGridView` returns a merged (span) cell's HEAD `contentView` for every
    /// grid position the merge covers, so each view's frame is attributed only
    /// to its head row/column — folding a rowspan cell's frame into every row
    /// it spans would drag that row's extents across the span and the midpoint
    /// rules in `draw(_:)` would slice through neighboring cells' text. A row
    /// or column consisting entirely of covered cells contributes no extents
    /// entry, which is exactly right: no rule should cross the merged cell.
    private func cellExtents() -> (rows: [(minY: CGFloat, maxY: CGFloat)], cols: [(minX: CGFloat, maxX: CGFloat)]) {
        var headRow = [ObjectIdentifier: Int]()
        var headCol = [ObjectIdentifier: Int]()
        for r in 0..<grid.numberOfRows {
            for c in 0..<grid.numberOfColumns {
                guard let v = grid.cell(atColumnIndex: c, rowIndex: r).contentView else { continue }
                let id = ObjectIdentifier(v)
                if headRow[id] == nil { headRow[id] = r }
                if headCol[id] == nil { headCol[id] = c }
            }
        }
        var rows = [(minY: CGFloat, maxY: CGFloat)]()
        var cols = [(minX: CGFloat, maxX: CGFloat)]()
        for r in 0..<grid.numberOfRows {
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            for c in 0..<grid.numberOfColumns {
                guard let v = grid.cell(atColumnIndex: c, rowIndex: r).contentView,
                      v.frame.height > 0.5, headRow[ObjectIdentifier(v)] == r else { continue }
                let f = v.superview?.convert(v.frame, to: self) ?? .zero
                lo = min(lo, f.minY); hi = max(hi, f.maxY)
            }
            if hi > lo { rows.append((lo, hi)) }
        }
        for c in 0..<grid.numberOfColumns {
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            for r in 0..<grid.numberOfRows {
                guard let v = grid.cell(atColumnIndex: c, rowIndex: r).contentView,
                      v.frame.width > 0.5, headCol[ObjectIdentifier(v)] == c else { continue }
                let f = v.superview?.convert(v.frame, to: self) ?? .zero
                lo = min(lo, f.minX); hi = max(hi, f.maxX)
            }
            if hi > lo { cols.append((lo, hi)) }
        }
        return (rows, cols)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 2, bounds.height > 2 else { return }
        let (rows, cols) = cellExtents()

        // Header fill first — everything else strokes on top of it.
        if hasHeader, let fill = headerBackground, let header = rows.first {
            fill.setFill()
            let bandBottom = rows.count > 1 ? (header.maxY + rows[1].minY) / 2 : header.maxY + Self.padding.height
            NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: bandBottom - 0.5),
                         xRadius: 4, yRadius: 4).fill()
        }

        borderColor.setStroke()

        // Outer rounded border.
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        outer.lineWidth = 1
        outer.stroke()

        // Horizontal rules at the midpoints between adjacent rows; the rule
        // under the header is drawn twice as strong (GitHub-style emphasis).
        for i in 0..<max(0, rows.count - 1) {
            let y = ((rows[i].maxY + rows[i + 1].minY) / 2).rounded() + 0.5
            let rule = NSBezierPath()
            rule.move(to: NSPoint(x: 1, y: y))
            rule.line(to: NSPoint(x: bounds.width - 1, y: y))
            rule.lineWidth = (hasHeader && i == 0) ? 2 : 1
            rule.stroke()
        }

        // Vertical rules at the midpoints between adjacent columns.
        for i in 0..<max(0, cols.count - 1) {
            let x = ((cols[i].maxX + cols[i + 1].minX) / 2).rounded() + 0.5
            let rule = NSBezierPath()
            rule.move(to: NSPoint(x: x, y: 1))
            rule.line(to: NSPoint(x: x, y: bounds.height - 1))
            rule.lineWidth = 1
            rule.stroke()
        }
    }
}

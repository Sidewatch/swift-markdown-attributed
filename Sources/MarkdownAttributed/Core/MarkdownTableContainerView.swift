//
//  MarkdownTableContainerView.swift
//  MarkdownAttributed
//

import AppKit

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
    static let padding = NSSize(width: 13, height: 8)

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

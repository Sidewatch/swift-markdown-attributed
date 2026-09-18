# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Nothing to fix. Checked: `AttributedRenderer`'s inline state save/restore (traits, strikethrough,
link) around every container, the pending list marker (consumed by the item's first block, flushed
as its own row for an empty item or one that opens with a nested list, never leaked into a
sibling), the hanging-indent maths at every quote/list depth, the attachment line-height reset,
`resolveImageURL` refusing everything but file URLs; `MarkdownTableAttachment.fit`'s idempotence
(labels reset to single-line before measuring), `allot` terminating (each pass fixes at least one
column or breaks), `mergeSpans` clamped to the grid, `TableCell.collect` deduping a merged cell's
head label, and `MarkdownTableContainerView.cellExtents` attributing a span only to its head
row/column.

## Known non-issues (do not "fix" these again)

- `MarkdownTableViewProvider`: the two `nonisolated(unsafe) let me = self` are LOAD-BEARING. The compiler warns they are unnecessary; removing them is a build ERROR (`sending 'me' risks causing data races`). Re-checked in this audit — leave them, the comment on them now says so.
- `visitSymbolLink`, `visitCustomInline`, `visitInlineAttributes`, `visitBlockDirective`, `visitCustomBlock`, `visitDoxygen*` show as unreferenced — they are `MarkupVisitor` requirements dispatched by swift-markdown, not dead.

## Status

- **Not used by Sidewatch since 18 Sep 2026.** The app's markdown PDF export now prints its WebKit preview
  (`MarkdownPDFExporter`), which retired `MarkdownRenderView`. The package stays published and tested for other
  hosts; archive it if nothing else adopts it.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 18 Sep 2026 — archived: unused by Sidewatch since the PDF export moved to the web renderer. Read-only from here.

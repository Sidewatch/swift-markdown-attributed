//
//  MarkdownTableViewProvider.swift
//  MarkdownAttributed
//
//  The TextKit 2 view provider for ``MarkdownTableAttachment``: hosts the table's `NSGridView`
//  and reports its fitting size as the attachment bounds.
//
//  Created by David Sherlock on 9/5/26.
//

import AppKit

/// The TextKit 2 view provider for ``MarkdownTableAttachment``: hosts the
/// table's `NSGridView` and reports its fitting size as the attachment bounds.
/// `@unchecked Sendable` is what lets the `assumeIsolated` blocks below capture `self`.
/// The claim is narrow and true: TextKit creates and drives a view provider only from the
/// main-thread layout pass, nothing here hands one to another thread, and each override
/// asserts that isolation at runtime rather than assuming it silently.
final class MarkdownTableViewProvider: NSTextAttachmentViewProvider, @unchecked Sendable {

    /// Builds the hosted table view — the grid wrapped in a chrome-drawing
    /// container (an empty `NSView` for a foreign attachment).
    ///
    /// `MainActor.assumeIsolated` because `NSTextAttachmentViewProvider` is not annotated
    /// `@MainActor` in the SDK, yet TextKit only ever drives it from the layout pass on the
    /// main thread — and the body builds `NSView`s, which admit no other thread. Overriding
    /// with a `@MainActor` signature is not allowed against a nonisolated superclass method,
    /// so asserting the isolation is the available option. Unlike a silencer, this traps if
    /// the assumption is ever violated.
    override func loadView() {
        // `nonisolated(unsafe) let me`: the region checker cannot see that TextKit only calls
        // this on the main thread; `assumeIsolated` asserts it at runtime, and the local
        // sidesteps the "sending 'self'" diagnostic without weakening that assertion.
        nonisolated(unsafe) let me = self
        MainActor.assumeIsolated {
            if let attachment = me.textAttachment as? MarkdownTableAttachment {
                me.view = MarkdownTableContainerView(
                    grid: attachment.makeGridView(),
                    borderColor: attachment.borderColor,
                    headerBackground: attachment.headerBackground,
                    hasHeader: !attachment.headerCells.isEmpty
                )
            } else {
                me.view = NSView()
            }
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
        // Main-thread-only for the same reason as `loadView` above.
        nonisolated(unsafe) let me = self
        return MainActor.assumeIsolated {
            if me.view == nil { me.loadView() }
            if let container = me.view as? MarkdownTableContainerView,
               let attachment = me.textAttachment as? MarkdownTableAttachment {
                // The container adds padding around the grid so the cells breathe
                // against the border strokes — fit the grid to what remains.
                attachment.fit(grid: container.grid,
                               to: proposedLineFragment.width - MarkdownTableContainerView.padding.width * 2)
            }
            let size = me.view?.fittingSize ?? .zero
            return CGRect(origin: .zero, size: size)
        }
    }
}

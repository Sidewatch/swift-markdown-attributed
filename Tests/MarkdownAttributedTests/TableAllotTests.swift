//
//  TableAllotTests.swift
//  MarkdownAttributedTests
//
//  Tests for Table Allot.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import MarkdownAttributed

final class TableAllotTests: XCTestCase {
    func testColumnsThatFitTheirFairShareKeepItAndTheRestSplitTheRemainder() {
        // 20 + 20 fit under the fair share; the wide column gets what is left (60).
        XCTAssertEqual(MarkdownTableAttachment.allot([300, 20, 20], within: 100), [60, 20, 20])
    }

    func testNoColumnGoesBelowTheMinimumEvenWhenThatOverflows() {
        // Two 500-wide columns in 30 points: fair share 15, floored at the 40-point minimum.
        XCTAssertEqual(MarkdownTableAttachment.allot([500, 500], within: 30), [40, 40])
        XCTAssertEqual(MarkdownTableAttachment.allot([500, 500], within: 30, minColumnWidth: 10), [15, 15])
    }
}

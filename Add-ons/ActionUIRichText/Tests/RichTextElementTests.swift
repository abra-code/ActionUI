// Add-ons/ActionUIRichText/Tests/RichTextElementTests.swift
//
// Element-level tests of the ActionUIRichText add-on: how the "remoteImages" property turns into the
// view's remote-image policy. Reaches internals via @testable import.

import XCTest
@testable import ActionUIRichText
import RichText

@MainActor
final class RichTextRemoteImagesTests: XCTestCase {

    func testTheThreeNamesGiveTheirPolicy() {
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("automatic"), .automatic)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("on-click"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("never"), .never)
    }

    func testAbsentIsAutomatic() {
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(nil), .automatic)
    }

    func testAnyOtherValueFailsClosedToOnClick() {
        // A misspelling, another case, or another type: whoever set the key meant to restrict fetching.
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("onclick"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("Never"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(""), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(false), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(0), .onClick)
    }
}

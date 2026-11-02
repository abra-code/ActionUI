// Tests/Runtime/DesktopNotificationsTests.swift
/*
 Tests for a desktop notification's body: bold and italic become the specification's <b> and <i>;
 code, strikethrough and links show as their text; markup characters in the text and the heading
 are escaped; the heading is a bold line of its own; without body markup the body is plain text.
*/

import XCTest
@testable import ActionUI

@MainActor
final class DesktopNotificationsTests: XCTestCase {
    func testBoldAndItalicBecomeMarkup() {
        XCTAssertEqual(DesktopNotifications.body(heading: nil, markdown: "Job **42** finished in *3 s*.", markup: true),
                       "Job <b>42</b> finished in <i>3 s</i>.")
        XCTAssertEqual(DesktopNotifications.body(heading: nil, markdown: "***both***", markup: true), "<b><i>both</i></b>")
    }

    func testCodeStrikethroughAndLinksShowTheirText() {
        XCTAssertEqual(DesktopNotifications.body(heading: nil, markdown: "Run `make` ~~now~~ [docs](https://example.com)", markup: true),
                       "Run make now docs")
    }

    func testMarkupCharactersAreEscaped() {
        XCTAssertEqual(DesktopNotifications.body(heading: "Build <x> & y", markdown: "a <b>x</b> & \"y\"", markup: true),
                       "<b>Build &lt;x&gt; &amp; y</b>\na &lt;b&gt;x&lt;/b&gt; &amp; &quot;y&quot;")
    }

    // GNOME Shell keeps only the named entities amp, lt, gt, quot and apos: "&#39;" would show as
    // typed. A raw control character fails Pango's parse, so it is left out.
    func testOnlyEntitiesGnomeKeepsAndNoControlCharacters() {
        XCTAssertEqual(DesktopNotifications.body(heading: "It's", markdown: "it's done\u{1}\u{7F}\u{90}.", markup: true),
                       "<b>It&apos;s</b>\nit&apos;s done.")
    }

    func testTheHeadingIsALineOfItsOwn() {
        XCTAssertEqual(DesktopNotifications.body(heading: "Build finished", markdown: "Done.", markup: true),
                       "<b>Build finished</b>\nDone.")
        XCTAssertEqual(DesktopNotifications.body(heading: "", markdown: "Done.", markup: true), "Done.")
    }

    func testWithoutBodyMarkupTheBodyIsPlainText() {
        XCTAssertEqual(DesktopNotifications.body(heading: "Build *1*", markdown: "Job **42** <done> & `x`", markup: false),
                       "Build *1*\nJob 42 <done> & x")
    }
}

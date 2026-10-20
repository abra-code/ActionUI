// Core/Elements/WebViewPropsTests.swift
/*
 Tests for WebView.Props, which both backings (the SwiftUI WebPage one and the WKWebView one) read:
 the content to load, the gesture flags (default on), the configuration flags (left to the web view
 when absent), the user scripts (those with a source, a file path or a resource name; the
 injection time falls back to documentEnd) and the two actions.
*/

import XCTest
@testable import ActionUI

final class WebViewPropsTests: XCTestCase {
    func testDefaults() {
        let props = WebView.Props([:])
        XCTAssertNil(props.url)
        XCTAssertNil(props.html)
        XCTAssertNil(props.baseURL)
        XCTAssertNil(props.customUserAgent)
        XCTAssertTrue(props.backForwardNavigationGestures)
        XCTAssertTrue(props.magnificationGestures)
        XCTAssertTrue(props.linkPreviews)
        XCTAssertNil(props.limitsNavigationsToAppBoundDomains)
        XCTAssertNil(props.upgradeKnownHostsToHTTPS)
        XCTAssertEqual(props.userScripts.count, 0)
        XCTAssertNil(props.valueChangeActionID)
        XCTAssertNil(props.navigationActionID)
    }

    func testValidValues() {
        let props = WebView.Props([
            "url": "https://www.swift.org", "html": "<h1>Hi</h1>", "baseURL": "https://example.com", "customUserAgent": "MyApp/1.0",
            "backForwardNavigationGestures": false, "magnificationGestures": false, "linkPreviews": false,
            "limitsNavigationsToAppBoundDomains": true, "upgradeKnownHostsToHTTPS": false,
            "valueChangeActionID": "url.changed", "navigationActionID": "nav",
        ])
        XCTAssertEqual(props.url, "https://www.swift.org")
        XCTAssertEqual(props.html, "<h1>Hi</h1>")
        XCTAssertEqual(props.baseURL, "https://example.com")
        XCTAssertEqual(props.customUserAgent, "MyApp/1.0")
        XCTAssertFalse(props.backForwardNavigationGestures)
        XCTAssertFalse(props.magnificationGestures)
        XCTAssertFalse(props.linkPreviews)
        XCTAssertEqual(props.limitsNavigationsToAppBoundDomains, true)
        XCTAssertEqual(props.upgradeKnownHostsToHTTPS, false)
        XCTAssertEqual(props.valueChangeActionID, "url.changed")
        XCTAssertEqual(props.navigationActionID, "nav")
    }

    func testWrongTypesFallBack() {
        let props = WebView.Props([
            "url": 1, "html": 2, "baseURL": 3, "customUserAgent": 4, "backForwardNavigationGestures": "no",
            "magnificationGestures": 0, "linkPreviews": "no", "limitsNavigationsToAppBoundDomains": 1,
            "upgradeKnownHostsToHTTPS": "yes", "valueChangeActionID": 5, "navigationActionID": 6,
        ])
        XCTAssertNil(props.url)
        XCTAssertNil(props.html)
        XCTAssertNil(props.baseURL)
        XCTAssertNil(props.customUserAgent)
        XCTAssertTrue(props.backForwardNavigationGestures)
        XCTAssertTrue(props.magnificationGestures)
        XCTAssertTrue(props.linkPreviews)
        XCTAssertNil(props.limitsNavigationsToAppBoundDomains)
        XCTAssertNil(props.upgradeKnownHostsToHTTPS)
        XCTAssertNil(props.valueChangeActionID)
        XCTAssertNil(props.navigationActionID)
    }

    func testUserScripts() {
        let props = WebView.Props(["userScripts": [
            ["injectionTime": "documentStart", "source": "var a = 1;", "forMainFrameOnly": true],
            ["filePath": "/tmp/a.js"],
            ["resourceName": "B.js", "injectionTime": "documentEnd"],
        ] as [Any]])
        XCTAssertEqual(props.userScripts.count, 3)
        XCTAssertEqual(props.userScripts[0].source, "var a = 1;")
        XCTAssertEqual(props.userScripts[0].injectionTime, .documentStart)
        XCTAssertTrue(props.userScripts[0].forMainFrameOnly)
        XCTAssertEqual(props.userScripts[1].filePath, "/tmp/a.js")
        XCTAssertEqual(props.userScripts[1].injectionTime, .documentEnd)
        XCTAssertFalse(props.userScripts[1].forMainFrameOnly)
        XCTAssertEqual(props.userScripts[2].resourceName, "B.js")
    }

    func testScriptsWithoutAnySourceAreSkipped() {
        let props = WebView.Props(["userScripts": [
            ["injectionTime": "documentStart"], ["source": 5], ["source": "ok;"], ["source": 5, "filePath": "/tmp/a.js"],
        ] as [Any]])
        XCTAssertEqual(props.userScripts.map(\.source), ["ok;", nil])
        XCTAssertEqual(props.userScripts[1].filePath, "/tmp/a.js")
    }

    func testInjectionTimeFallsBackToDocumentEnd() {
        let props = WebView.Props(["userScripts": [
            ["source": "1;", "injectionTime": "later"], ["source": "2;", "injectionTime": 5], ["source": "3;", "forMainFrameOnly": "yes"],
        ] as [Any]])
        XCTAssertEqual(props.userScripts.map(\.injectionTime), [.documentEnd, .documentEnd, .documentEnd])
        XCTAssertEqual(props.userScripts.map(\.forMainFrameOnly), [false, false, false])
    }

    func testUserScriptsOfAnotherShapeAreNone() {
        for scripts: Any in ["script", 5, [1, 2] as [Any], [["source": "1;"], 5] as [Any]] {
            XCTAssertEqual(WebView.Props(["userScripts": scripts]).userScripts.count, 0, "\(scripts)")
        }
    }
}

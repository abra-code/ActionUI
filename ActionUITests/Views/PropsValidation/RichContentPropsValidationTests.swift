// Views/PropsValidation/RichContentPropsValidationTests.swift
/*
 Props against validation (see PropsValidationSupport.swift) for Canvas, Chart, Map, WebView,
 VideoPlayer, ShareLink, KeyframeAnimator and PhaseAnimator. Chart's Props leaves out the chart
 description, which validation stores parsed and cleaned and the renderer caches; Map's value (the
 center coordinate) is not a property.
*/

import XCTest
@testable import ActionUI

/// Props holds the operations as raw dictionaries, whose printed order varies between equal
/// dictionaries; NSDictionary compares them by content.
private struct CanvasChoice {
    var operations: [NSDictionary]
    var backgroundColor: String?
    var coordinateMode: Canvas.Props.CoordinateMode
    var actionID: String?

    init(_ properties: [String: Any]) {
        let props = Canvas.Props(properties)
        operations = props.operations.map { $0 as NSDictionary }
        backgroundColor = props.backgroundColor
        coordinateMode = props.coordinateMode
        actionID = props.actionID
    }
}

@MainActor
final class CanvasPropsValidationTests: PropsValidationTestCase {
    private let circle: [String: Any] = ["type": "circle", "center": [0.5, 0.5] as [Any], "radius": 0.4]
    private let frame: [Any] = [0.1, 0.1, 0.8, 0.8]

    func testMatchesValidation() {
        let path: [String: Any] = circle
        let operations: [Any] = [
            [Any](),
            [["type": "fill", "path": path, "color": "#FF0000"]] as [Any],
            [["type": "FILL", "path": path]] as [Any],
            [["type": "stroke", "path": path, "color": "#0000FF", "lineWidth": 0.02]] as [Any],
            [["type": "clip", "path": path]] as [Any],
            [["type": "fill"]] as [Any],
            [["type": "stroke", "path": "circle"]] as [Any],
            [["type": "clip", "path": 5]] as [Any],
            [["path": path]] as [Any],
            [["type": 5, "path": path]] as [Any],
            [["type": "text", "text": "Hi", "frame": frame]] as [Any],
            [["type": "text", "text": "Hi", "frame": [0.1, 0.2] as [Any]]] as [Any],
            [["type": "text", "text": 5, "frame": frame]] as [Any],
            [["type": "text", "frame": frame]] as [Any],
            [["type": "image", "systemName": "star", "frame": frame]] as [Any],
            [["type": "image", "assetName": "a", "frame": frame]] as [Any],
            [["type": "image", "resourceName": "r.png", "frame": frame]] as [Any],
            [["type": "image", "filePath": "/tmp/a.png", "frame": frame]] as [Any],
            [["type": "image", "systemName": "star", "assetName": "a", "frame": frame]] as [Any],
            [["type": "image", "frame": frame]] as [Any],
            [["type": "image", "systemName": "star"]] as [Any],
            [["type": "image", "systemName": "star", "frame": [1, 2, 3] as [Any]]] as [Any],
            [["type": "shadow"]] as [Any],
            [["type": "shadow", "radius": 0.01, "drawAbove": true]] as [Any],
            [["type": "blur", "radius": 0.015]] as [Any],
            [["type": "blur", "radius": 3]] as [Any],
            [["type": "blur", "radius": 0]] as [Any],
            [["type": "blur", "radius": -1]] as [Any],
            [["type": "blur", "radius": "big"]] as [Any],
            [["type": "blur", "radius": "inf"]] as [Any],
            [["type": "blur"]] as [Any],
            [["type": "translate", "x": 0.1]] as [Any],
            [["type": "scale", "x": 2]] as [Any],
            [["type": "rotate", "angle": 45]] as [Any],
            [["type": "ROTATE", "angle": 45]] as [Any],
            [["type": "spin"]] as [Any],
            [["type": "layer", "frame": frame]] as [Any],
            [["type": "layer", "frame": frame, "operations": [["type": "fill", "path": path], ["type": "bogus"], ["type": "blur"]] as [Any]]] as [Any],
            [["type": "layer", "frame": frame, "operations": [["type": "layer", "frame": frame, "operations": [["type": "rotate"], ["type": "fill"]] as [Any]]] as [Any]]] as [Any],
            [["type": "layer", "frame": frame, "operations": "none"]] as [Any],
            [["type": "layer", "frame": frame, "operations": [Any]()]] as [Any],
            [["type": "layer"]] as [Any],
            [["type": "fill", "path": path], ["type": "nope"], ["type": "scale"]] as [Any],
            "operations", 5, true,
            [1, 2] as [Any],
            [["type": "fill", "path": path], "x"] as [Any],
        ]
        assertPropsMatchValidation(
            elementType: "Canvas", CanvasChoice.init,
            casesByKey: [
                "operations": operations,
                "backgroundColor": ["#F5F5F5", "red", "", 5, true],
                "coordinateMode": ["normalized", "points", "Points", "pixels", "", 5],
                "actionID": ["tap", 5],
            ],
            combinations: [
                ["operations": [["type": "rotate", "angle": 10]] as [Any], "backgroundColor": "#000", "coordinateMode": "points", "actionID": "tap"],
                ["operations": 5, "backgroundColor": 5, "coordinateMode": 5, "actionID": 5],
            ]
        )
    }
}

@MainActor
final class ChartPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Chart", Chart.Props.init,
            casesByKey: [
                "valueChangeActionID": ["chart.selected", "", 5, true],
                "selectionActionTiming": ["settled", "continuous", "Continuous", "instant", "", 5],
            ],
            combinations: [
                ["valueChangeActionID": "picked", "selectionActionTiming": "continuous"],
                ["valueChangeActionID": 1, "selectionActionTiming": 2],
                ["selectionActionTiming": "continuous", "chart": ["content": [Any]()] as [String: Any]],
                ["valueChangeActionID": "picked", "chart": "not an object"],
            ]
        )
    }
}

@MainActor
final class MapPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        let apple: [String: Any] = ["latitude": 37.33, "longitude": -122.03]
        assertPropsMatchValidation(
            elementType: "Map", Map.Props.init,
            casesByKey: [
                "coordinate": [
                    apple,
                    ["latitude": 1, "longitude": 2] as [String: Any],
                    ["latitude": 1] as [String: Any],
                    ["latitude": "1", "longitude": 2] as [String: Any],
                    ["latitude": "inf", "longitude": 2] as [String: Any],
                    [String: Any](),
                    "37,-122", 5, [37.33, -122.03] as [Any],
                ],
                "showsUserLocation": [true, false, "true", 1, 0],
                "interactionModes": [
                    ["pan", "zoom", "rotate"] as [Any],
                    ["pan"] as [Any],
                    ["rotate", "pan"] as [Any],
                    ["pan", "pan"] as [Any],
                    [Any](),
                    ["pan", "tilt"] as [Any],
                    ["Pan"] as [Any],
                    ["pan", 5] as [Any],
                    [1, 2] as [Any],
                    "pan", 5, true,
                ],
                "annotations": [
                    [Any](),
                    [["coordinate": apple, "title": "Apple", "subtitle": "Cupertino"]] as [Any],
                    [["coordinate": apple]] as [Any],
                    [["coordinate": apple, "title": 5, "subtitle": true]] as [Any],
                    [["coordinate": apple, "title": NSNull()]] as [Any],
                    [["title": "No coordinate"]] as [Any],
                    [["coordinate": ["latitude": 1] as [String: Any], "title": "Half"]] as [Any],
                    [["coordinate": apple, "title": "A"], ["coordinate": "x", "title": "B"], ["coordinate": apple, "title": "C"]] as [Any],
                    [["coordinate": apple], 5] as [Any],
                    "annotations", 5, [1, 2] as [Any],
                ],
                "valueChangeActionID": ["moved", 5],
                "actionID": ["camera", 5],
            ],
            combinations: [
                ["coordinate": apple, "showsUserLocation": true, "interactionModes": ["pan", "zoom"] as [Any],
                 "annotations": [["coordinate": apple, "title": "T"]] as [Any], "valueChangeActionID": "v", "actionID": "a"],
                ["coordinate": 5, "showsUserLocation": 5, "interactionModes": 5, "annotations": 5, "valueChangeActionID": 5, "actionID": 5],
            ]
        )
    }
}

@MainActor
final class WebViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        let script: [String: Any] = ["injectionTime": "documentStart", "source": "var a = 1;", "forMainFrameOnly": true]
        assertPropsMatchValidation(
            elementType: "WebView", WebView.Props.init,
            casesByKey: [
                "url": ["https://www.swift.org", "", 5, true],
                "html": ["<h1>Hello</h1>", "", 5],
                "baseURL": ["https://example.com", "", 5],
                "customUserAgent": ["MyApp/1.0", "", 5],
                "backForwardNavigationGestures": [true, false, "false", 0, 1],
                "magnificationGestures": [true, false, "false", 0, 1],
                "linkPreviews": [true, false, "false", 0, 1],
                "limitsNavigationsToAppBoundDomains": [true, false, "true", 1],
                "upgradeKnownHostsToHTTPS": [true, false, "true", 1],
                "valueChangeActionID": ["url.changed", 5],
                "navigationActionID": ["nav", 5],
                "userScripts": [
                    [script] as [Any],
                    [["source": "1;"]] as [Any],
                    [["filePath": "/tmp/a.js"]] as [Any],
                    [["resourceName": "A.js", "injectionTime": "documentEnd"]] as [Any],
                    [["source": "1;", "injectionTime": "later"]] as [Any],
                    [["source": "1;", "injectionTime": 5]] as [Any],
                    [["source": "1;", "forMainFrameOnly": "yes"]] as [Any],
                    [["source": 5]] as [Any],
                    [["source": 5, "filePath": "/tmp/a.js"]] as [Any],
                    [["injectionTime": "documentStart"]] as [Any],
                    [script, ["injectionTime": "documentEnd"], ["source": "2;"]] as [Any],
                    [Any](),
                    [script, 5] as [Any],
                    "script", 5, [1, 2] as [Any],
                ],
            ],
            combinations: [
                ["url": "https://a.b", "html": "<p/>", "baseURL": "https://c.d", "customUserAgent": "UA",
                 "backForwardNavigationGestures": false, "magnificationGestures": false, "linkPreviews": false,
                 "limitsNavigationsToAppBoundDomains": true, "upgradeKnownHostsToHTTPS": true,
                 "userScripts": [script] as [Any], "valueChangeActionID": "v", "navigationActionID": "n"],
                ["url": 1, "html": 2, "baseURL": 3, "customUserAgent": 4, "backForwardNavigationGestures": 5,
                 "magnificationGestures": 6, "linkPreviews": 7, "limitsNavigationsToAppBoundDomains": 8,
                 "upgradeKnownHostsToHTTPS": 9, "userScripts": 10, "valueChangeActionID": 11, "navigationActionID": 12],
            ]
        )
    }
}

@MainActor
final class VideoPlayerPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        // Validation logs an error (which the test logger fails on) for a url that is not a String,
        // so that case is in the explicit tests only.
        assertPropsMatchValidation(
            elementType: "VideoPlayer", VideoPlayer.Props.init,
            casesByKey: [
                "url": ["https://example.com/video.mp4", "", "not a url"],
                "autoplay": [true, false, "true", 1, 0],
            ],
            combinations: [
                ["url": "https://example.com/video.mp4", "autoplay": true],
                ["url": "", "autoplay": "yes"],
            ]
        )
    }
}

@MainActor
final class ShareLinkPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ShareLink", ShareLink.Props.init,
            casesByKey: [
                "item": ["https://example.com", "", "mailto:a@b.c", "not a url", "http://[bad", "https://exa mple.com", 5, true],
                "subject": ["Check this out", "", 5],
                "message": ["Look!", "", 5],
            ],
            combinations: [
                ["item": "https://example.com", "subject": "S", "message": "M"],
                ["item": 1, "subject": 2, "message": 3],
                ["item": "", "subject": "S"],
            ]
        )
    }
}

/// Props holds the keyframes as raw dictionaries; see CanvasChoice.
private struct KeyframeChoice {
    var initialValue: AnimationValues
    var trigger: String
    var timerInterval: Double
    var stateKey: String
    var repeatCount: Int
    var autoreverses: Bool
    var delay: Double
    var keyframes: NSDictionary

    init(_ properties: [String: Any]) {
        let props = KeyframeAnimator.Props(properties)
        initialValue = props.initialValue
        trigger = props.trigger
        timerInterval = props.timerInterval
        stateKey = props.stateKey
        repeatCount = props.repeatCount
        autoreverses = props.autoreverses
        delay = props.delay
        keyframes = props.keyframes as NSDictionary
    }
}

@MainActor
final class KeyframeAnimatorPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        // The validator keeps every property as it is.
        assertPropsMatchValidation(
            elementType: "KeyframeAnimator", KeyframeChoice.init,
            casesByKey: [
                "initialValue": [
                    ["opacity": 0.0, "scale": 1, "rotation": 45] as [String: Any],
                    ["opacity": "half"] as [String: Any],
                    [String: Any](),
                    "x", 5,
                ],
                "trigger": ["onAppear", "onTap", "onTimer", "onStateChange", "", 5],
                "timerInterval": [2.0, 3, 0, -1, "2", "inf", true],
                "stateKey": ["clicks", "", 5],
                "repeat": [
                    ["count": 3, "autoreverses": true] as [String: Any],
                    ["count": 3.0, "autoreverses": "yes"] as [String: Any],
                    ["count": "3"] as [String: Any],
                    [String: Any](), "x", 5,
                ],
                "delay": [1.5, 2, 0, -1, "1", true],
                "keyframes": [
                    ["0%": ["type": "linear", "value": ["opacity": 0.0] as [String: Any], "duration": 0.8] as [String: Any],
                     "50%": ["type": "spring", "response": 0.4] as [String: Any]] as [String: Any],
                    ["0%": 5] as [String: Any],
                    ["0%": ["type": "cubic"] as [String: Any], "100%": "x"] as [String: Any],
                    [String: Any](), "x", 5, [Any](),
                ],
            ],
            combinations: [
                ["trigger": "onTimer", "timerInterval": 2, "stateKey": "k", "delay": 1,
                 "repeat": ["count": 2, "autoreverses": true] as [String: Any],
                 "initialValue": ["scale": 2] as [String: Any],
                 "keyframes": ["0%": ["value": ["scale": 1] as [String: Any]] as [String: Any]] as [String: Any]],
                ["trigger": 1, "timerInterval": "x", "stateKey": 2, "delay": "y", "repeat": 3, "initialValue": 4, "keyframes": 5],
            ]
        )
    }
}

@MainActor
final class PhaseAnimatorPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "PhaseAnimator", PhaseAnimator.Props.init,
            casesByKey: [
                "values": [
                    [0.0, 1.0, 2.0] as [Any],
                    [0, 1, 2] as [Any],
                    [0.5, "x", true, false, NSNull()] as [Any],
                    [Any](),
                    "x", 5, [String: Any]() as Any,
                ],
                "trigger": ["onAppear", "onTap", "onTimer", "onStateChange", "", 5],
                "timerInterval": [2.0, 3, 0, -1, "2", true],
                "stateKey": ["clicks", "", 5],
                // The base validation rewrites this key; Props must read the rewritten form.
                "animation": [
                    "spring", "linear", "default", "bogus", "", 5,
                    ["curve": "easeIn", "duration": 0.5] as [String: Any],
                    ["curve": "spring", "duration": 0, "delay": -1, "speed": 0] as [String: Any],
                    ["curve": "linear", "duration": -2, "delay": 0.5, "speed": 2, "value": "state"] as [String: Any],
                    ["curve": "linear", "duration": "2", "value": 5] as [String: Any],
                    ["type": "spring", "duration": 0.5] as [String: Any],
                    ["type": "linear", "curve": "bouncy", "response": 0.2, "controlPoints": [0.2, 0.8, 0.4, 1.0] as [Any]] as [String: Any],
                    ["curve": "nope", "duration": 1] as [String: Any],
                    ["curve": 5] as [String: Any],
                    [String: Any](), [Any](), true,
                ],
            ],
            combinations: [
                ["values": [1, 2] as [Any], "trigger": "onTimer", "timerInterval": 4, "stateKey": "k",
                 "animation": ["curve": "smooth", "duration": 3] as [String: Any]],
                ["values": 1, "trigger": 2, "timerInterval": "x", "stateKey": 3, "animation": 4],
            ]
        )
    }
}

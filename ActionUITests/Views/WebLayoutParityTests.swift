// Views/WebLayoutParityTests.swift
/*
 The web side of the layout parity battery (the LayoutParity folder at the repository root): every
 fixture is rendered by ActionUIWeb in a WKWebView, as a browser renders it, and each Color's frame
 is read from the pixels of a snapshot and checked against LayoutParity/expected/<fixture>.json,
 which the Apple side recorded from SwiftUI's own layout (LayoutParityTests.swift).

 - The page loads ActionUIWeb's own files (src/, theme.css) through a URL scheme handler, so no
   server runs; the harness page renders one fixture at a time with Window.fromJSON(...).present.
 - Reading paint, not DOM boxes, catches what CSS paints differently (a background under padding).
 - WebKit is the engine of Safari; Chrome and Firefox lay out the same CSS the same way for these
   fixtures (flexbox and grid, no text).
*/

#if os(macOS)
import XCTest
import AppKit
import WebKit

/// Serves ActionUIWeb's files, and the harness page, to the test's web view.
@MainActor
private final class WebFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "actionui-web"

    /// ActionUIWeb: this file is ActionUITests/Views/WebLayoutParityTests.swift.
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ActionUIWeb")

    /// Renders a fixture at the top leading corner of the page, on white.
    static let harness = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <link rel="stylesheet" href="/theme.css">
        <style>html, body { margin: 0; padding: 0; background: #ffffff; } #stage { display: flex; align-items: flex-start; }</style>
        </head><body><div id="stage"></div>
        <script>
        // A module that fails to load or to run is reported here, not as a page that never gets ready.
        window.addEventListener("error", (event) => {
            window.harnessError ??= event.message || `could not load ${event.target?.src || "a module"}`;
        }, true);
        </script>
        <script type="module">
        import { Window } from "/src/ActionUI.js";
        let current = null;
        window.renderFixture = (json) => {
            current?.dismiss();
            current = Window.fromJSON(json);
            current.present(document.getElementById("stage"));
        };
        window.harnessReady = true;
        </script></body></html>
        """

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let data: Data?
        if url.path == "/harness.html" {
            data = Data(Self.harness.utf8)
        } else {
            // Only files inside ActionUIWeb: url.path decodes "%2F", so "/..%2F" would climb out.
            let folder = Self.folder.standardizedFileURL.path + "/"
            let file = Self.folder.appendingPathComponent(url.path).standardizedFileURL
            data = file.path.hasPrefix(folder) ? try? Data(contentsOf: file) : nil
        }
        guard let data else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "mjs": "text/javascript", "css": "text/css",
                     "json": "application/json", "map": "text/plain", "svg": "image/svg+xml"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": types[url.pathExtension] ?? "application/octet-stream"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// What a call run with a deadline returned or threw, once it has.
@MainActor
private final class Outcome<T> {
    var result: Result<T, any Error>?
}

/// A WebKit call that did not return in time, or a harness page that failed.
private struct WebHarnessError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class WebLayoutParityTests: XCTestCase {
    /// Fixtures the web renderer does not match yet, with the causes. A fixture that starts to
    /// match fails the test until it is removed here. The causes, found with this test:
    /// - center: the frame sizes the element's own node, so content in a bigger frame is not centered (SwiftUI's frame centers the view it wraps)
    /// - stretch: a Color with a fixed size sits at its stack's start (.aui-shape align-self: stretch), ignoring the stack's alignment
    /// - empty: a Color with no frame in a nested stack takes no space (SwiftUI's fills)
    /// - paint: a Color's fill paints under its own padding (SwiftUI's padding is clear)
    /// - spacing: VStack default 8 (ActionUI's is 0), a gap next to a Spacer, no Spacer minimum
    /// - spacer: Spacers share space with other flexible views (SwiftUI sizes them last)
    /// - cap: a stack's cap and expansion do not come from its children
    /// - groupbox: content inset and title metrics differ
    /// - unavailable: ContentUnavailableView is not capped at 400
    /// - zstack: the children are placed at the frame's corner, not in a centered stack
    /// - order: the least flexible view is not sized first
    /// - effects: offset, and a scaleEffect with x, y and anchor, are not applied
    private static let knownDifferences: [String: String] = [
        "cap-in-infinite-frame-leading": "center",
        "cap-in-infinite-frame-zstack": "empty, zstack",
        "cap-in-wider-frame": "cap",
        "cap-root-frame-leading": "center",
        "cap-root-frame-top": "center, stretch",
        "cap-root-leading": "center, cap",
        "cap-root-padding-leading": "center, cap",
        "contentunavailable-in-vstack": "unavailable",
        "contentunavailable-padding": "unavailable",
        "contentunavailable-width-1000": "unavailable",
        "contentunavailable-width-600": "unavailable",
        "contentunavailable-zstack": "unavailable",
        "divider-hstack-height": "spacing, stretch",
        "effects-offset-keeps-layout": "effects, stretch",
        "effects-offset-then-rotation": "effects, stretch",
        "effects-rotation-around-center": "stretch",
        "effects-scale-around-anchor": "effects, stretch",
        "frame-alignment": "center",
        "groupbox-capped-hstack": "empty, groupbox, cap",
        "groupbox-capped-vstack": "empty, groupbox, cap",
        "groupbox-children": "groupbox, center, stretch",
        "groupbox-fills": "empty, groupbox",
        "groupbox-spacer-squeezed": "groupbox, spacing",
        "groupbox-spacer-zero-min": "groupbox, spacing",
        "hstack-default-spacing": "stretch",
        "hstack-emptyview": "center, stretch",
        "hstack-fixed-and-filler": "stretch",
        "hstack-larger-minimum-first": "order",
        "hstack-spacer-yields": "spacer, stretch",
        "labeledcontent-empty-title": "empty, stretch",
        "labeledcontent-spacer": "spacing",
        "nested-cap-cross-axis": "empty, cap",
        "nested-cap-fixed-frame": "empty",
        "nested-cap-hidden": "cap",
        "nested-cap-min-only-frame": "empty",
        "nested-cap-padding-inside-frame": "paint, cap",
        "nested-cap-propagation": "empty, cap",
        "nested-cap-sum-in-hstack": "empty, cap",
        "nested-cap-with-padding": "empty, cap",
        "nested-cap-zstack": "empty, zstack",
        "nested-unbounded": "empty, cap",
        "nested-unbounded-spacer": "empty, spacer",
        "padding-in-frame": "center, paint, stretch",
        "vstack-alignment-leading": "center",
        "vstack-alignment-trailing": "center, stretch",
        "vstack-fill-width-and-spacer": "stretch",
        "zstack-top-trailing": "zstack",
    ]

    /// The LayoutParity folder: this file is ActionUITests/Views/WebLayoutParityTests.swift.
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("LayoutParity")

    private var window: NSWindow?
    private var files: WebFiles?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        files = nil
        try await super.tearDown()
    }

    /// A web view showing the harness page, ready to render.
    private func makeWebView() async throws -> WKWebView {
        let files = WebFiles()
        self.files = files
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: WebFiles.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        self.window = window
        webView.load(URLRequest(url: URL(string: "\(WebFiles.scheme)://local/harness.html")!))
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            // "" once ready, the error once one is reported, nil while loading.
            let state = try await withDeadline(5, "asking the harness page whether it is ready") {
                try? await webView.evaluateJavaScript("window.harnessReady === true ? '' : (window.harnessError ?? null)") as? String
            }
            if state == "" { return webView }
            if let state {
                XCTFail("the harness page failed: \(state)")
                throw WebHarnessError(description: "the harness page failed")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw WebHarnessError(description: "the harness page did not load within 20 s")
    }

    /// Runs `body`, and fails the test when it has not returned after `seconds`: a WebKit call that
    /// never returns (a promise that never settles, a snapshot that never comes) would otherwise
    /// block the whole run. The abandoned call is left running.
    private func withDeadline<T>(_ seconds: TimeInterval, _ what: String,
                                 _ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let outcome = Outcome<T>()
        let finished = expectation(description: what)
        Task { @MainActor in
            do { outcome.result = .success(try await body()) } catch { outcome.result = .failure(error) }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: seconds)
        guard let result = outcome.result else { throw WebHarnessError(description: "\(what) took over \(Int(seconds)) s") }
        return try result.get()
    }

    func testTheWebRendererMatchesSwiftUIsFrames() async throws {
        let webView = try await makeWebView()
        let fixtures = try FileManager.default
            .contentsOfDirectory(at: Self.folder.appendingPathComponent("fixtures"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(Self.folder.path)/fixtures")
        for fixture in fixtures {
            let name = fixture.deletingPathExtension().lastPathComponent
            let expected = try JSONDecoder().decode(LayoutParityExpectation.self, from: Data(contentsOf:
                Self.folder.appendingPathComponent("expected").appendingPathComponent(name + ".json")))
            let differences = try await differences(fixture, expected, in: webView)
            if let reason = Self.knownDifferences[name] {
                if differences.isEmpty {
                    XCTFail("\(name) now matches SwiftUI: remove it from knownDifferences")
                } else {
                    print("[web layout parity] \(name): known difference (\(reason)): \(differences.joined(separator: "; "))")
                }
            } else {
                for difference in differences {
                    XCTFail("\(name): \(difference)")
                }
            }
        }
    }

    /// Renders the fixture and lists each Color frame that differs from SwiftUI's.
    private func differences(_ fixture: URL, _ expected: LayoutParityExpectation, in webView: WKWebView) async throws -> [String] {
        let data = try Data(contentsOf: fixture)
        let document = try JSONSerialization.jsonObject(with: data)
        let (width, height) = try LayoutParityPixels.rootSize(of: document, fixture: fixture.lastPathComponent)
        // Rendered, its layout forced, then a turn of the page's event loop. (Animation frames do
        // not run for a window WebKit thinks is hidden.)
        let json = String(decoding: data, as: UTF8.self)
        try await withDeadline(30, "rendering \(fixture.lastPathComponent)") {
            _ = try await webView.callAsyncJavaScript("""
                renderFixture(json);
                document.body.getBoundingClientRect();
                await new Promise(done => setTimeout(done, 0));
                return true;
                """, arguments: ["json": json], contentWorld: .page)
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        let image = try await withDeadline(30, "the snapshot of \(fixture.lastPathComponent)") {
            try await webView.takeSnapshot(configuration: configuration)
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let measured = LayoutParityPixels.frames(in: bitmap, width: width, leaves: LayoutParityPixels.leaves(of: document),
                                                 fixture: fixture.lastPathComponent)
        var result: [String] = []
        for (id, frame) in expected.frames.sorted(by: { $0.key < $1.key }) {
            guard let actual = measured[id] else {
                result.append("element \(id) is not drawn, SwiftUI's is \(frame)")
                continue
            }
            if zip(frame, actual).contains(where: { abs($0 - $1) > LayoutParityTests.tolerance }) {
                result.append("element \(id) is \(actual), SwiftUI's is \(frame)")
            }
        }
        for id in Set(measured.keys).subtracting(expected.frames.keys).sorted() {
            result.append("element \(id) is drawn at \(measured[id]!), SwiftUI draws none")
        }
        return result
    }
}
#endif

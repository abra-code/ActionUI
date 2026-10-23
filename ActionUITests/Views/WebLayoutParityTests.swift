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
    /// match fails the test until it is removed here. ActionUIWeb/README.md describes them for
    /// users ("Known layout differences from SwiftUI"). The causes, found with this test:
    /// - padding: a view's own CSS padding is a floor under its flex share (flex-basis 0 cannot go below it), so ContentUnavailableView takes 316 of 600 where SwiftUI shares 300 and 300
    /// - form: a Form fills its parent's width with its rows at the leading edge, where macOS's hugs its rows and is centered like a VStack; its rows sit 4 lower beside a filling row; no label column
    /// - group: a Group's padding or frame goes on one box around the whole Group, which lays its children out in a column, where SwiftUI applies them to each child in the parent stack
    /// - minimum: an expanding child's minimum is added to its share of the remainder (CSS flex-basis auto) instead of being sized first; basis 0 would do that but collapses a greedy child (a List with padding) to nothing in a stack sized by its content
    private static let knownDifferences: [String: String] = [
        "contentunavailable-width-600": "padding",
        "divider-hstack-height": "minimum",
        "form-empty-control-title": "form",
        "form-filling-row": "form",
        "form-rows-hug": "form",
        "form-sections-add-no-space": "form",
        "group-frame-per-child": "group",
        "group-padding-per-child": "group",
        "hstack-larger-minimum-first": "minimum",
        "nested-unbounded-spacer": "minimum",
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

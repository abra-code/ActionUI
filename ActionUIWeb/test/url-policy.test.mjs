// Tests for the address rules ActionUI JSON cannot get around (src/Helpers/URLPolicy.js) and the
// elements that apply them: WebView (sandbox and http/https only), Link, Map "Open in Maps",
// ShareLink, and LoadableView (no "//host" sources, no self-inclusion, a nesting limit).

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";

let isOpenedURL, isFramedURL, webViewSandboxFor, WEBVIEW_HTML_SANDBOX, WEBVIEW_URL_SANDBOX;
let classifyLoadableSource;
let getConstruction;
let Window, Application;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ isOpenedURL, isFramedURL, webViewSandboxFor, WEBVIEW_HTML_SANDBOX, WEBVIEW_URL_SANDBOX } = await import("../src/Helpers/URLPolicy.js"));
    ({ classifyLoadableSource } = await import("../src/Helpers/LoadableSource.js"));
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
    ({ Window, Application } = await import("../src/ActionUI.js"));
});

const savedFetch = globalThis.fetch;
after(() => { globalThis.fetch = savedFetch; });

// A model that records bindings, enough for buildView of a single element.
function makeModel() {
    const bindings = new Map();
    return {
        bindings,
        bind(id, binding) { bindings.set(id, binding); },
        bindState() {},
        dispatchAction() {},
    };
}

const build = (type, properties, logger = makeLogger(), model = makeModel()) =>
    getConstruction(type).buildView({ type, id: 1, properties }, properties, { logger, model });

const frameOf = (node) => node.children.find((child) => child.tagName.toLowerCase() === "iframe");

test("javascript:, vbscript: and data: are never opened, however they are spelled", () => {
    for (const url of ["javascript:alert(1)", "JavaScript:alert(1)", " javascript:alert(1)",
        "java\nscript:alert(1)", "java\tscript:alert(1)", "vbscript:x", "data:text/html,<b>x</b>"]) {
        assert.equal(isOpenedURL(url), false, JSON.stringify(url));
    }
    for (const url of ["https://example.com", "mailto:a@example.com", "tel:123", "page.html"]) {
        assert.equal(isOpenedURL(url), true, url);
    }
});

test("a frame shows only http and https addresses, relative ones included", () => {
    for (const url of ["https://example.com/a", "http://example.com", "docs/page.html", "/root.html", "//example.com/x"]) {
        assert.equal(isFramedURL(url), true, url);
    }
    for (const url of ["javascript:alert(1)", "java\nscript:alert(1)", "data:text/html,x", "blob:https://x/1",
        "file:///etc/passwd", "about:blank", "vbscript:x"]) {
        assert.equal(isFramedURL(url), false, JSON.stringify(url));
    }
});

test("WebView html runs in a sandbox without the host page's origin", () => {
    const frame = frameOf(build("WebView", { html: "<script>parent.document.title = 'x'</script>" }));
    assert.equal(frame.sandbox, WEBVIEW_HTML_SANDBOX);
    assert.ok(!frame.sandbox.includes("allow-same-origin"));
    assert.ok(!frame.sandbox.includes("allow-top-navigation"));
    assert.ok(frame.sandbox.split(" ").includes("allow-popups"), "links may open tabs");
    assert.ok(!frame.sandbox.includes("allow-popups-to-escape-sandbox"), "which keep the sandbox");
    assert.ok(frame.srcdoc.includes("<script>"));
});

test("WebView url gets the url sandbox, which still cannot navigate the host page", () => {
    const frame = frameOf(build("WebView", { url: "https://example.com" }));
    assert.equal(frame.sandbox, WEBVIEW_URL_SANDBOX);
    assert.ok(!frame.sandbox.includes("allow-top-navigation"));
    assert.ok(!frame.sandbox.includes("allow-popups-to-escape-sandbox"));
    assert.equal(frame.src, "https://example.com");
});

test("WebView refuses a javascript: url, as a property and as a value write", () => {
    const logger = makeLogger();
    const model = makeModel();
    const node = build("WebView", { url: "javascript:alert(document.cookie)" }, logger, model);
    const frame = frameOf(node);
    assert.ok(!frame.src, "nothing was loaded");
    assert.equal(model.bindings.get(1).getValue(), "", "a refused url is not the value");
    assert.ok(logger.warned("is not an http or https address"));

    model.bindings.get(1).setValue("java\nscript:alert(1)");
    assert.ok(!frame.src, "a value write is refused too");
    model.bindings.get(1).setValue("https://example.com/next");
    assert.equal(frame.src, "https://example.com/next");
    assert.equal(model.bindings.get(1).getValue(), "https://example.com/next");
});

test("WebView html switched to a url gets a fresh frame, so the html never runs with the url sandbox", () => {
    const model = makeModel();
    const node = build("WebView", { html: "<p>x</p>" }, makeLogger(), model);
    const htmlFrame = frameOf(node);
    model.bindings.get(1).setValue("javascript:alert(1)");
    assert.equal(frameOf(node), htmlFrame, "a refused url keeps the html");
    assert.equal(htmlFrame.sandbox, WEBVIEW_HTML_SANDBOX);

    model.bindings.get(1).setValue("https://example.com/");
    const urlFrame = frameOf(node);
    assert.notEqual(urlFrame, htmlFrame);
    assert.equal(node.children.length, 1);
    assert.equal(htmlFrame.sandbox, WEBVIEW_HTML_SANDBOX, "the html frame's sandbox was not widened");
    assert.equal(urlFrame.getAttribute("srcdoc"), null);
    assert.equal(urlFrame.sandbox, WEBVIEW_URL_SANDBOX);
    assert.equal(urlFrame.src, "https://example.com/");

    model.bindings.get(1).setValue("#reload");
    assert.equal(frameOf(node), urlFrame);
});

test("a WebView url on the host page's own origin gets the opaque-origin sandbox", () => {
    // The tests' page is http://localhost/, so a relative address is on the page's origin.
    const frame = frameOf(build("WebView", { url: "docs/page.html" }));
    assert.equal(frame.sandbox, WEBVIEW_HTML_SANDBOX);
    assert.ok(!frame.sandbox.includes("allow-same-origin"));
    assert.equal(frame.src, "docs/page.html");
});

test("a WebView whose sandbox changes between pages gets a fresh frame each time", () => {
    const model = makeModel();
    const node = build("WebView", { url: "https://example.com/" }, makeLogger(), model);
    const crossFrame = frameOf(node);
    assert.equal(crossFrame.sandbox, WEBVIEW_URL_SANDBOX);

    model.bindings.get(1).setValue("https://example.com/other");
    assert.equal(frameOf(node), crossFrame, "same flags: the frame is reused");

    model.bindings.get(1).setValue("/local.html");
    const localFrame = frameOf(node);
    assert.notEqual(localFrame, crossFrame);
    assert.equal(crossFrame.sandbox, WEBVIEW_URL_SANDBOX, "the old frame's flags were not narrowed in place");
    assert.equal(localFrame.sandbox, WEBVIEW_HTML_SANDBOX);

    model.bindings.get(1).setValue("https://example.com/back");
    const backFrame = frameOf(node);
    assert.notEqual(backFrame, localFrame);
    assert.equal(localFrame.sandbox, WEBVIEW_HTML_SANDBOX, "the same-origin page never gets allow-same-origin");
    assert.equal(backFrame.sandbox, WEBVIEW_URL_SANDBOX);
    assert.equal(node.children.length, 1);
});

test("on a page served from a custom scheme, relative WebView urls stay allowed", () => {
    const saved = globalThis.document.baseURI;
    globalThis.document.baseURI = "actionui-web://app/index.html";
    try {
        assert.equal(isFramedURL("page.html"), true);
        assert.equal(isFramedURL("actionui-web://app/other.html"), true);
        assert.equal(isFramedURL("actionui-web://other-host/x.html"), false, "only the page's own host");
        assert.equal(isFramedURL("https://example.com"), true);
        assert.equal(isFramedURL("javascript:alert(1)"), false);
        assert.equal(isFramedURL("file:///etc/passwd"), false);
        assert.equal(isFramedURL("data:text/html,x"), false);
    } finally {
        if (saved === undefined) delete globalThis.document.baseURI;
        else globalThis.document.baseURI = saved;
    }
});

test("a WebView url on the page's origin is opaque even when <base href> names another server", () => {
    const savedBase = globalThis.document.baseURI;
    const savedLocation = globalThis.location;
    globalThis.document.baseURI = "https://cdn.example/app/";
    globalThis.location = { href: "https://app.example/index.html", origin: "https://app.example" };
    try {
        assert.equal(webViewSandboxFor("https://app.example/upload/x.html"), WEBVIEW_HTML_SANDBOX);
        assert.equal(webViewSandboxFor("page.html"), WEBVIEW_HTML_SANDBOX, "relative: on the base's server");
        assert.equal(webViewSandboxFor("https://other.example/"), WEBVIEW_URL_SANDBOX);
    } finally {
        if (savedBase === undefined) delete globalThis.document.baseURI;
        else globalThis.document.baseURI = savedBase;
        if (savedLocation === undefined) delete globalThis.location;
        else globalThis.location = savedLocation;
    }
    globalThis.document.baseURI = "actionui-web://app/index.html";
    try {
        assert.equal(webViewSandboxFor("actionui-web://app/other.html"), WEBVIEW_HTML_SANDBOX, "an opaque origin counts as the page's");
        assert.equal(webViewSandboxFor("https://example.com/"), WEBVIEW_URL_SANDBOX);
    } finally {
        if (savedBase === undefined) delete globalThis.document.baseURI;
        else globalThis.document.baseURI = savedBase;
    }
});

test("on a page opened from file:, no file: address is framed", () => {
    const saved = globalThis.document.baseURI;
    globalThis.document.baseURI = "file:///Users/someone/app/index.html";
    try {
        assert.equal(isFramedURL("page.html"), false);
        assert.equal(isFramedURL("file:///etc/passwd"), false);
        assert.equal(isFramedURL("https://example.com"), true);
    } finally {
        if (saved === undefined) delete globalThis.document.baseURI;
        else globalThis.document.baseURI = saved;
    }
});

test("Link does not open a javascript: url hidden by a line break", () => {
    const node = build("Link", { title: "x", url: "java\nscript:alert(1)" });
    assert.ok(!node.href);
});

test("Map hides 'Open in Maps' for a javascript: template and sandboxes its embed", () => {
    const logger = makeLogger();
    const node = build("Map", { coordinate: { latitude: 1, longitude: 2 }, openInMapsURL: "javascript:alert({lat})" }, logger);
    const open = node.children.find((child) => child.className === "aui-map-open");
    assert.ok(!open.href);
    assert.equal(open.hidden, true);
    assert.ok(logger.warned("opens nothing"));
    const frame = frameOf(node);
    assert.ok(frame.sandbox.includes("allow-scripts"));
    assert.ok(!frame.sandbox.includes("allow-top-navigation"));
    assert.ok(!frame.sandbox.includes("allow-popups-to-escape-sandbox"));

    const ok = build("Map", { coordinate: { latitude: 1, longitude: 2 }, openInMapsURL: "https://maps.example/?q={lat},{lon}" });
    const okOpen = ok.children.find((child) => child.className === "aui-map-open");
    assert.equal(okOpen.href, "https://maps.example/?q=1,2");
});

test("ShareLink with a javascript: item renders nothing", () => {
    const node = build("ShareLink", { item: "javascript:alert(1)" });
    assert.equal(node.className, "aui-empty");
});

test("a LoadableView source starting with // is not fetched from another server", () => {
    for (const source of ["//evil.example/doc.json", "file:////evil.example/doc.json", "\\\\evil.example/doc.json",
        "\\\\evil.example\\doc.json", "/\\evil.example/doc.json", "https:evil.example/doc.json", "/\n/evil.example/doc.json"]) {
        assert.equal(classifyLoadableSource(source).kind, "none", JSON.stringify(source));
    }
    assert.equal(classifyLoadableSource("docs/doc.json").kind, "filePath");
    assert.equal(classifyLoadableSource("file:///docs/doc.json").kind, "filePath");
    assert.equal(classifyLoadableSource("Section").kind, "bundle");
});

// Renders a LoadableView with fetch answering from `files` (address suffix to
// JSON), lets every load settle, and returns the fetched addresses and the logger.
async function renderLoadable(rootSource, files) {
    const fetched = [];
    globalThis.fetch = async (url) => {
        fetched.push(url);
        const json = files(url);
        return { ok: json !== null, status: json !== null ? 200 : 404, text: async () => JSON.stringify(json) };
    };
    const logger = makeLogger();
    const win = Window.fromJSON({ type: "LoadableView", id: 1, properties: { url: rootSource } }, undefined, logger);
    new Application({ name: "T" }).presentWindow(win, makeElement());
    for (let i = 0; i < 100; i++) await new Promise((resolve) => setImmediate(resolve));
    return { fetched, logger };
}

const including = (source) => ({ type: "VStack", children: [{ type: "LoadableView", properties: { url: source } }] });

test("JSON that loads itself is fetched twice at most, then refused", async () => {
    const { fetched, logger } = await renderLoadable("https://example.com/self.json", () => including("https://example.com/self.json"));
    assert.ok(fetched.length <= 2, `fetched ${fetched.length} times`);
    assert.ok(logger.messages.some((m) => m.message.includes("it includes itself")));
});

test("a loop through two JSON files is refused", async () => {
    const { fetched, logger } = await renderLoadable("https://example.com/a.json",
        (url) => including(url.endsWith("a.json") ? "https://example.com/b.json" : "https://example.com/a.json"));
    assert.ok(fetched.length <= 3, `fetched ${fetched.length} times`);
    assert.ok(logger.messages.some((m) => m.message.includes("it includes itself")));
});

test("an endless chain of new JSON files stops at the nesting limit", async () => {
    const { fetched, logger } = await renderLoadable("https://example.com/n0.json", (url) => {
        const n = Number(url.match(/n(\d+)\.json$/)[1]);
        return including(`https://example.com/n${n + 1}.json`);
    });
    assert.ok(fetched.length <= 17, `fetched ${fetched.length} times`);
    assert.ok(logger.messages.some((m) => m.message.includes("nested more than")));
});

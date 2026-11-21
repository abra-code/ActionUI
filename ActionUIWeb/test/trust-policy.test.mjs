// Tests for where content came from (Common/TrustPolicy.js), the host's trust policy, and the
// limits every document is held to (Helpers/JSONLimits.js): the origin a LoadableView's
// content records, the id rule for less-trusted content, the 16 MB and depth caps, and the load
// budget. The page here is http://localhost/ (the stub DOM has no base address).

import { test, before, after, afterEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";

let TP, DL, Window, Application;
const savedFetch = globalThis.fetch;

before(async () => {
    installDom();
    TP = await import("../src/Common/TrustPolicy.js");
    DL = await import("../src/Helpers/JSONLimits.js");
    ({ Window, Application } = await import("../src/ActionUI.js"));
});

afterEach(() => {
    TP.setTrustPolicy();
});

after(() => {
    globalThis.fetch = savedFetch;
});

const remote = Object.freeze({ source: "remote", url: "https://example.com/v.json", trust: "lessTrusted", parentID: 3 });

test("the default rules: trusted content anything, less-trusted content web links and addresses only", () => {
    const { allowsByDefault, HOST_ORIGIN } = TP;
    for (const url of ["tel:123", "file:///etc/hosts", "intent://x", "relative/page"]) {
        assert.equal(allowsByDefault({ capability: "openLink", url }, HOST_ORIGIN), true, url);
        assert.equal(allowsByDefault({ capability: "openLink", url }, remote), false, url);
    }
    assert.equal(allowsByDefault({ capability: "openLink", url: "MAILTO:a@example.com" }, remote), true);
    assert.equal(allowsByDefault({ capability: "webView", url: "https://example.com/" }, remote), true);
    assert.equal(allowsByDefault({ capability: "webView", url: null }, remote), true);
    assert.equal(allowsByDefault({ capability: "webView", url: "file:///etc/hosts" }, remote), false);
    assert.equal(allowsByDefault({ capability: "webViewBaseURL", url: "https://example.com/other/" }, remote), true);
    assert.equal(allowsByDefault({ capability: "webViewBaseURL", url: "https://bank.example/" }, remote), false);
    assert.equal(allowsByDefault({ capability: "windowTitle" }, remote), false);
    assert.equal(allowsByDefault({ capability: "presentModal" }, remote), false);
    assert.equal(allowsByDefault({ capability: "action", actionID: "app.save" }, remote), true);
});

test("a source on the page's origin is a resource, another origin less trusted, no more trusted than its parent", () => {
    const { resolvedOrigin, HOST_ORIGIN } = TP;
    assert.deepEqual(resolvedOrigin({ kind: "bundle", fetchURL: "Sub.json" }, HOST_ORIGIN, 2),
        { source: "resource", path: "http://localhost/Sub.json", trust: "trusted", parentID: 2 });
    assert.equal(resolvedOrigin({ kind: "remote", fetchURL: "http://localhost/docs/a.json" }, HOST_ORIGIN, 2).trust, "trusted");
    assert.deepEqual(resolvedOrigin({ kind: "remote", fetchURL: "https://example.com/v.json" }, HOST_ORIGIN, 0),
        { source: "remote", url: "https://example.com/v.json", trust: "lessTrusted" });
    assert.equal(resolvedOrigin({ kind: "bundle", fetchURL: "Sub.json" }, remote, 4).trust, "lessTrusted");
    assert.equal(resolvedOrigin({ kind: "none", fetchURL: "" }, HOST_ORIGIN, 2), null);
});

test("the host's policy decides trust and each capability; one that throws fails closed", () => {
    const { resolvedOrigin, allows, setTrustPolicy, HOST_ORIGIN } = TP;
    assert.throws(() => setTrustPolicy({ trust: "yes" }), TypeError);
    assert.throws(() => setTrustPolicy(() => {}), TypeError);
    setTrustPolicy({
        trust: (source, parent, byDefault) => (source.url ?? "").startsWith("https://example.com/") ? "trusted" : byDefault,
        allows: (capability, origin) => capability.capability !== "action",
    });
    assert.equal(resolvedOrigin({ kind: "remote", fetchURL: "https://example.com/v.json" }, HOST_ORIGIN, 2).trust, "trusted");
    assert.equal(resolvedOrigin({ kind: "remote", fetchURL: "https://other.example/v.json" }, HOST_ORIGIN, 2).trust, "lessTrusted");
    assert.equal(allows({ capability: "action", actionID: "x" }, HOST_ORIGIN), false);
    setTrustPolicy({ trust: () => { throw new Error("boom"); }, allows: () => { throw new Error("boom"); } });
    const logger = makeLogger();
    assert.equal(resolvedOrigin({ kind: "bundle", fetchURL: "Sub.json" }, HOST_ORIGIN, 2, logger).trust, "lessTrusted");
    assert.equal(allows({ capability: "openLink", url: "https://example.com/" }, HOST_ORIGIN, logger), false);
    assert.equal(logger.messages.filter((m) => m.level === "error").length, 2);
});

test("a document larger than 16 MB, or nested deeper than 512, is not decoded", async () => {
    assert.equal(DL.utf8LongerThan("abc", 3), false);
    assert.equal(DL.utf8LongerThan("\u00e9\u00e9", 3), true);
    assert.equal(DL.utf8LongerThan("\uD83D\uDE00", 4), false);
    assert.equal(DL.nestsDeeperThan("[[[]]]", 3), false);
    assert.equal(DL.nestsDeeperThan("[[[[]]]]", 3), true);
    assert.equal(DL.nestsDeeperThan("[\"[[[[\"]", 3), false, "brackets in strings do not count");
    assert.equal(DL.jsonRefusal("[".repeat(513)), "Nested deeper than 512 levels");
    const logger = makeLogger();
    assert.throws(() => Window.fromJSON("x".repeat(DL.MAX_DOCUMENT_BYTES + 1), undefined, logger));
    assert.ok(logger.messages.some((m) => m.message.includes("Larger than 16 MB")));
    // A download stops at the cap, by its declared length or as it is read.
    await assert.rejects(DL.readJSONText({ headers: { get: () => String(DL.MAX_DOCUMENT_BYTES + 1) }, text: async () => "" }), /Larger than 16 MB/);
    const chunk = new Uint8Array(4 * 1024 * 1024);
    let reads = 0;
    const body = { getReader: () => ({ read: async () => (reads++ < 5 ? { done: false, value: chunk } : { done: true }), cancel: async () => {} }) };
    await assert.rejects(DL.readJSONText({ headers: { get: () => null }, body }), /Larger than 16 MB/);
    assert.equal(reads, 5, "stopped as soon as the cap was passed");
});

test("the load budget allows 256 loads in a minute per window", () => {
    let now = 0;
    const budget = new DL.LoadBudget({ loads: 3, seconds: 60 }, () => now);
    assert.equal(budget.spend() && budget.spend() && budget.spend(), true);
    assert.equal(budget.spend(), false);
    now = 60_000;
    assert.equal(budget.spend(), true, "a minute later, again");
    assert.deepEqual(DL.LOAD_BUDGET, { loads: 256, seconds: 60 });
});

// Renders `root` with fetch answering from `documents` (address to document, or text), lets
// every load settle, and returns the window and the logger.
async function render(root, documents) {
    globalThis.fetch = async (url) => {
        const document = documents(url);
        return { ok: document != null, status: document != null ? 200 : 404,
            text: async () => (typeof document === "string" ? document : JSON.stringify(document)) };
    };
    const logger = makeLogger();
    const win = Window.fromJSON(root, undefined, logger);
    const container = makeElement();
    new Application({ name: "T" }).presentWindow(win, container);
    for (let i = 0; i < 50; i++) await new Promise((resolve) => setImmediate(resolve));
    return { win, logger, container };
}

test("a LoadableView's content records its origin; the host's document is the host's", async () => {
    const { win } = await render(
        { type: "VStack", id: 1, children: [
            { type: "LoadableView", id: 2, properties: { url: "https://example.com/v.json" } },
            { type: "LoadableView", id: 3, properties: { name: "Own" } }] },
        (url) => url.startsWith("https://example.com/")
            ? { type: "VStack", id: 20, children: [{ type: "Text", id: 21, properties: { text: "remote" } }] }
            : { type: "Text", id: 30, properties: { text: "own" } });
    assert.deepEqual(win.getElementOrigin(1), { source: "host", trust: "trusted" });
    assert.deepEqual(win.getElementOrigin(21), { source: "remote", url: "https://example.com/v.json", trust: "lessTrusted", parentID: 2 });
    assert.equal(win.getElementOrigin(30).source, "resource");
    assert.equal(win.getElementOrigin(30).trust, "trusted");
    assert.equal(win.getElementOrigin(999), null);
});

test("less-trusted content may not use a trusted element's id, even one not built yet", async () => {
    const { win, logger } = await render(
        { type: "VStack", id: 1, children: [
            { type: "TextField", id: 5, properties: { text: "secret" } },
            { type: "LoadableView", id: 2, properties: { url: "https://example.com/v.json" } }],
          sheet: { type: "Text", id: 7, properties: { text: "later" } } },
        () => ({ type: "VStack", id: 20, children: [{ type: "Button", id: 7, properties: { title: "Mine" } }] }));
    assert.ok(logger.messages.some((m) => m.message === "Not loading a less-trusted sub-view for parent 2: id 7 is already in the window"), JSON.stringify(logger.messages));
    assert.equal(win.getElementOrigin(20), null, "nothing of it was recorded");
    assert.equal(win.getElementOrigin(7).trust, "trusted");
});

test("a LoadableView's document larger than 16 MB is refused", async () => {
    const { logger } = await render(
        { type: "LoadableView", id: 2, properties: { url: "https://example.com/big.json" } },
        () => `{"type":"Text","id":20,"properties":{"text":"${"x".repeat(DL.MAX_DOCUMENT_BYTES)}"}}`);
    assert.ok(logger.messages.some((m) => m.message.includes("Larger than 16 MB")), JSON.stringify(logger.messages.map((m) => m.message)));
});

test("less-trusted content opens only web and mail links, titles nothing and presents nothing", async () => {
    const document = { type: "VStack", id: 20, properties: { navigationTitle: "Bank sign-in" }, children: [
        { type: "Link", id: 21, properties: { title: "Call", url: "tel:123" } },
        { type: "Link", id: 22, properties: { title: "Site", url: "https://example.com/" } },
        { type: "ShareLink", id: 23, properties: { item: "tel:123" } },
        { type: "Button", id: 24, properties: { title: "More" }, sheet: { type: "Text", id: 25, properties: { text: "Password?" } } },
        { type: "WebView", id: 26, properties: { html: "<p>hi</p>", baseURL: "https://bank.example/" } }] };
    const { logger } = await render({ type: "LoadableView", id: 2, properties: { url: "https://example.com/v.json" } }, () => document);
    const said = (text) => logger.messages.some((m) => m.message === text);
    assert.ok(said("Link not opening tel:123: the trust policy refuses it"), JSON.stringify(logger.messages.map((m) => m.message)));
    assert.ok(!said("Link not opening https://example.com/: the trust policy refuses it"));
    assert.ok(said("ShareLink not sharing tel:123: the trust policy refuses it"));
    assert.ok(said("Not setting the title for element 20: the trust policy refuses it"));
    assert.ok(said("Not presenting a sheet, cover or popover for element 24: the trust policy refuses it"));
    assert.ok(said("WebView html not given the base https://bank.example/: the trust policy refuses it"));
});

test("the host's own content is not held to those rules", async () => {
    const { logger } = await render({ type: "VStack", id: 20, properties: { navigationTitle: "Host" }, children: [
        { type: "Link", id: 21, properties: { title: "Call", url: "tel:123" } },
        { type: "Button", id: 24, properties: { title: "More" }, sheet: { type: "Text", id: 25, properties: { text: "Sheet" } } },
        { type: "WebView", id: 26, properties: { html: "<p>hi</p>", baseURL: "https://bank.example/" } }] }, () => null);
    assert.ok(!logger.messages.some((m) => m.message.includes("the trust policy refuses it")), JSON.stringify(logger.messages.map((m) => m.message)));
});

test("an id keeps its first record: trusted content reusing a less-trusted id does not relabel it", async () => {
    const { win } = await render(
        { type: "VStack", id: 1, children: [
            { type: "LoadableView", id: 2, properties: { url: "https://example.com/v.json" } },
            { type: "LoadableView", id: 3, properties: { name: "Empty" } }] },
        (url) => url.startsWith("https://example.com/") ? { type: "Button", id: 50, properties: { title: "Remote" } }
            : url.includes("Own") ? { type: "Text", id: 50, properties: { text: "own" } }
            : { type: "Text", id: 60, properties: { text: "empty" } });
    win.model.bindings.get(3).setValue("Own");
    for (let i = 0; i < 50; i++) await new Promise((resolve) => setImmediate(resolve));
    assert.equal(win.getElementOrigin(50).trust, "lessTrusted", "still the less-trusted button's");
    assert.equal(win.getElementOrigin(60), null, "the replaced content's id is forgotten");
});

test("a LoadableView forgets its content's ids when the next load fails; a removed element's origin goes", async () => {
    const { win } = await render({ type: "VStack", id: 1, children: [
            { type: "Text", id: 5, properties: { text: "a" } },
            { type: "LoadableView", id: 2, properties: { name: "Own" } }] },
        (url) => url.includes("Own") ? { type: "Text", id: 30, properties: { text: "own" } } : "not json");
    assert.equal(win.getElementOrigin(30).trust, "trusted");
    win.model.bindings.get(2).setValue("Bad");
    for (let i = 0; i < 50; i++) await new Promise((resolve) => setImmediate(resolve));
    assert.equal(win.getElementOrigin(30), null);
    win.model.cleanupElement(5); // removeElement cleans each removed id so (the stub DOM has no querySelector)
    assert.equal(win.getElementOrigin(5), null);
});

test("a policy object's methods keep their this", () => {
    class Policy { constructor() { this.answer = "trusted"; } trust() { return this.answer; } allows() { return this.answer === "trusted"; } }
    TP.setTrustPolicy(new Policy());
    assert.equal(TP.allows({ capability: "windowTitle" }, remote, makeLogger()), true);
    assert.equal(TP.resolvedOrigin({ kind: "remote", fetchURL: "https://example.com/v.json" }, TP.HOST_ORIGIN, 2).trust, "trusted");
});

test("what the host inserts into a window loaded from another origin is the host's", async () => {
    globalThis.fetch = async () => ({ ok: true, status: 200, text: async () => JSON.stringify({ type: "VStack", id: 1, children: [] }) });
    const win = await Window.fromURL("https://example.com/w.json", undefined, makeLogger());
    new Application({ name: "T" }).presentWindow(win, makeElement());
    assert.equal(win.getElementOrigin(1).trust, "lessTrusted");
    win.insertElement(1, { type: "Text", id: 9, properties: { text: "host" } });
    assert.deepEqual(win.getElementOrigin(9), { source: "host", trust: "trusted" });
});

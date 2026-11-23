// Tests for ActionUI's configuration on the web (Common/Configuration.js): the defaults, the keys
// (each optional, the rest kept), a change refused whole, the configuration fixed once a window
// is made, the limits read from it, and trusted origins: trusted only by the address the ActionUI
// JSON finally came from (the Response's url) and only inside trusted content. The page here is
// http://localhost/ (the stub DOM has no base address).

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";

let C, DL, TP, Window, Application, api;
const savedFetch = globalThis.fetch;

before(async () => {
    installDom();
    C = await import("../src/Common/Configuration.js");
    DL = await import("../src/Helpers/JSONLimits.js");
    TP = await import("../src/Common/TrustPolicy.js");
    api = await import("../src/ActionUI.js");
    ({ Window, Application } = api);
});

beforeEach(() => {
    C.resetConfigurationForTesting();
    TP.setTrustPolicy();
});

after(() => {
    globalThis.fetch = savedFetch;
    C.resetConfigurationForTesting();
});

const DEFAULTS = {
    limits: { maximumJSONSize: 16777216, loadBudget: { loads: 256, seconds: 60 }, maximumNestingDepth: 16, maximumDownloadTime: 120 },
    trust: { trustedOrigins: [] },
    resourceFolder: null,
    addOns: {},
};

test("the defaults, every key read back as a copy", () => {
    assert.deepEqual(api.getConfiguration(), DEFAULTS);
    const copy = api.getConfiguration();
    copy.limits.maximumJSONSize = 1;
    assert.equal(api.getConfiguration().limits.maximumJSONSize, 16777216, "changing the copy changes nothing");
    assert.ok(Object.isFrozen(C.currentConfiguration().limits), "ActionUI's own value is frozen");
});

test("configure changes only the keys it names", () => {
    api.configure({ limits: { maximumJSONSize: 67108864, loadBudget: { seconds: 30 } } });
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com", "https://cdn.example.com:8443/"] }, addOns: { Sample: { level: 2 } } });
    const configuration = api.getConfiguration();
    assert.equal(configuration.limits.maximumJSONSize, 64 * 1024 * 1024, "a host may raise a limit");
    assert.deepEqual(configuration.limits.loadBudget, { loads: 256, seconds: 30 }, "loads kept");
    assert.deepEqual(configuration.trust.trustedOrigins, ["https://ui.example.com", "https://cdn.example.com:8443/"]);
    assert.deepEqual(configuration.addOns, { Sample: { level: 2 } });
    api.configure({ addOns: { Sample: null }, resourceFolder: null });
    assert.deepEqual(api.getConfiguration().addOns, {}, "null removes a section");
    api.configure({});
    assert.equal(api.getConfiguration().limits.maximumJSONSize, 64 * 1024 * 1024, "an empty change keeps everything");
    api.configure({ limits: { maximumDownloadTime: 600 } });
    assert.equal(api.getConfiguration().limits.maximumDownloadTime, 600);
    api.configure({ limits: { maximumDownloadTime: null } });
    assert.equal(api.getConfiguration().limits.maximumDownloadTime, null, "null removes the time limit");
});

test("a bad change is refused whole", () => {
    const refused = [
        [{ limits: { maximumJSONSize: 1000 }, trustedOrigins: [] }, "unknown configuration key trustedOrigins"],
        [{ limits: { maximumJSONSize: 1000, maxJSONSize: 5 } }, "unknown configuration key limits.maxJSONSize"],
        [{ limits: { loadBudget: { loads: 3, span: 1 } } }, "unknown configuration key limits.loadBudget.span"],
        [{ limits: { maximumJSONSize: "big" } }, "limits.maximumJSONSize must be a whole number"],
        [{ limits: { maximumJSONSize: true } }, "limits.maximumJSONSize must be a whole number"],
        [{ limits: { maximumJSONSize: 1.5 } }, "limits.maximumJSONSize must be a whole number"],
        [{ limits: { maximumJSONSize: 0 } }, "limits.maximumJSONSize must be more than 0"],
        [{ limits: { loadBudget: { seconds: 0 } } }, "limits.loadBudget.seconds must be a number more than 0"],
        [{ limits: { loadBudget: { seconds: NaN } } }, "limits.loadBudget.seconds must be a number"],
        [{ limits: { maximumNestingDepth: -1 } }, "limits.maximumNestingDepth must not be negative"],
        [{ limits: { maximumDownloadTime: 0 } }, "limits.maximumDownloadTime must be a number more than 0, or null for no limit"],
        [{ limits: { maximumDownloadTime: -5 } }, "limits.maximumDownloadTime must be a number more than 0, or null for no limit"],
        [{ limits: { maximumDownloadTime: "slow" } }, "limits.maximumDownloadTime must be a number"],
        [{ limits: { maximumDownloadTime: true } }, "limits.maximumDownloadTime must be a number"],
        [{ limits: [] }, "limits must be an object"],
        [{ trust: { trustedOrigins: "https://ui.example.com" } }, "trust.trustedOrigins must be an array of strings"],
        [{ trust: { trustedOrigins: ["http://ui.example.com"] } }, "trust.trustedOrigins: http://ui.example.com is not an https address"],
        [{ trust: { trustedOrigins: ["https://ui.example.com/app"] } }, "trust.trustedOrigins: https://ui.example.com/app has a path; an origin is the scheme, host and port only"],
        [{ trust: { trustedOrigins: ["https://me@ui.example.com"] } }, "trust.trustedOrigins: https://me@ui.example.com has a user name or password"],
        [{ trust: { trustedOrigins: ["https://ui.example.com/?a=1"] } }, "trust.trustedOrigins: https://ui.example.com/?a=1 has a query or fragment"],
        [{ trust: { trustedOrigins: ["ui.example.com"] } }, "trust.trustedOrigins: ui.example.com is not an https address"],
        [{ resourceFolder: "/srv/ui" }, "resourceFolder has no meaning on the web: the page's own origin holds the app's resources; pass null or leave it out"],
        [{ addOns: 3 }, "addOns must be an object"],
        [JSON.parse('{"addOns": {"__proto__": {"level": 1}}}'), "addOns: a section may not be named __proto__"],
    ];
    for (const [settings, message] of refused) {
        assert.throws(() => api.configure(settings), (error) => error instanceof api.ConfigurationError && error.message === message, JSON.stringify(settings));
        assert.deepEqual(api.getConfiguration(), DEFAULTS, `nothing of ${JSON.stringify(settings)} applied`);
    }
    for (const bad of [null, "limits", [1], 3]) {
        assert.throws(() => api.configure(bad), TypeError, String(bad));
    }
});

test("the first window fixes the configuration", () => {
    api.configure({ limits: { maximumNestingDepth: 4 } });
    assert.equal(C.isConfigurationFixed(), false);
    Window.fromJSON({ type: "Text", id: 1, properties: { text: "hi" } }, undefined, makeLogger());
    assert.equal(C.isConfigurationFixed(), true);
    assert.throws(() => api.configure({ limits: { maximumNestingDepth: 8 } }),
        { message: "the configuration is fixed once a window has loaded its ActionUI JSON; set it before" });
    assert.equal(api.getConfiguration().limits.maximumNestingDepth, 4, "the setting from before stays");
});

test("the limits come from the configuration", () => {
    api.configure({ limits: { maximumJSONSize: 2 * 1024 * 1024, loadBudget: { loads: 1, seconds: 60 } } });
    assert.equal(DL.maximumJSONSize(), 2 * 1024 * 1024);
    assert.equal(DL.jsonRefusal("x".repeat(2 * 1024 * 1024 + 1)), "Larger than 2 MB");
    assert.equal(DL.jsonRefusal("x".repeat(2 * 1024 * 1024)), null);
    const budget = new DL.LoadBudget(null, () => 0);
    assert.equal(budget.spend(), true);
    assert.equal(budget.spend(), false, "one load in the span");
});

test("a trusted origin is trusted only by its exact origin and inside trusted content", () => {
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com"] } });
    const trust = (address, parent = null) => TP.resolvedOrigin({ kind: "remote", fetchURL: address }, parent, null, null)?.trust;
    assert.equal(trust("https://ui.example.com/app/main.json"), "trusted");
    assert.equal(trust("https://UI.Example.com:443/main.json"), "trusted", "case and the default port");
    assert.equal(trust("http://ui.example.com/main.json"), "lessTrusted", "plain http");
    assert.equal(trust("https://ui.example.com:8443/main.json"), "lessTrusted", "another port");
    assert.equal(trust("https://evil.ui.example.com/main.json"), "lessTrusted", "a subdomain");
    const remote = { source: "remote", url: "https://other.net/a.json", trust: "lessTrusted" };
    assert.equal(trust("https://ui.example.com/main.json", remote), "lessTrusted", "named by less-trusted content");
    assert.equal(TP.resolvedOrigin({ kind: "remote", fetchURL: "https://ui.example.com/main.json" }, null, null, null).source, "remote",
        "still remote, only trusted");
    C.resetConfigurationForTesting();
    assert.equal(trust("https://ui.example.com/a.json"), "lessTrusted", "no trusted origins by default");
});

// Renders `root` with fetch answering from `answer(url)` ({ body, url } or null), lets every load
// settle, and returns the window and the logger.
async function render(root, answer) {
    globalThis.fetch = async (url) => {
        const reply = answer(url);
        return { ok: reply != null, status: reply != null ? 200 : 404, url: reply?.url ?? "",
            text: async () => (typeof reply.body === "string" ? reply.body : JSON.stringify(reply.body)) };
    };
    const logger = makeLogger();
    const win = Window.fromJSON(root, undefined, logger);
    new Application({ name: "T" }).presentWindow(win, makeElement());
    for (let i = 0; i < 50; i++) await new Promise((resolve) => setImmediate(resolve));
    return { win, logger };
}

test("a LoadableView's content is judged by where it finally came from", async () => {
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com"] } });
    const panel = (id) => ({ type: "Text", id, properties: { text: "panel" } });
    const { win } = await render(
        { type: "VStack", id: 1, children: [
            { type: "LoadableView", id: 2, properties: { url: "https://ui.example.com/straight.json" } },
            { type: "LoadableView", id: 3, properties: { url: "https://ui.example.com/moved.json" } },
            { type: "LoadableView", id: 4, properties: { name: "Own" } }] },
        (url) => {
            if (url === "https://ui.example.com/straight.json") return { body: panel(20), url };
            if (url === "https://ui.example.com/moved.json") return { body: panel(30), url: "https://cdn.other.net/moved.json" };
            // A page-relative name the server redirects to another origin.
            return { body: panel(40), url: "https://cdn.other.net/Own.json" };
        });
    assert.deepEqual(win.getElementOrigin(20), { source: "remote", url: "https://ui.example.com/straight.json", trust: "trusted", parentID: 2 });
    assert.deepEqual(win.getElementOrigin(30), { source: "remote", url: "https://cdn.other.net/moved.json", trust: "lessTrusted", parentID: 3 },
        "redirected off the trusted server");
    assert.deepEqual(win.getElementOrigin(40), { source: "remote", url: "https://cdn.other.net/Own.json", trust: "lessTrusted", parentID: 4 },
        "the page's own name redirected to another origin");
});

test("JSON from a trusted origin inside less-trusted content stays less trusted", async () => {
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com"] } });
    const { win } = await render(
        { type: "LoadableView", id: 2, properties: { url: "https://other.net/outer.json" } },
        (url) => url === "https://other.net/outer.json"
            ? { body: { type: "LoadableView", id: 20, properties: { url: "https://ui.example.com/inner.json" } }, url }
            : { body: { type: "Text", id: 30, properties: { text: "inner" } }, url });
    assert.equal(win.getElementOrigin(20).trust, "lessTrusted");
    assert.equal(win.getElementOrigin(30).trust, "lessTrusted");
    assert.equal(win.getElementOrigin(30).url, "https://ui.example.com/inner.json");
});

test("on a page served from a custom scheme, its own files stay resources once fetched", () => {
    const saved = globalThis.document.baseURI;
    globalThis.document.baseURI = "actionui-web://app/index.html";
    try {
        const own = { kind: "filePath", fetchURL: "views/a.json" };
        assert.deepEqual(TP.resolvedOrigin(own, null, null, null, "actionui-web://app/views/a.json"),
            { source: "resource", path: "actionui-web://app/views/a.json", trust: "trusted" });
        assert.deepEqual(TP.resolvedOrigin(own, null, null, null, "actionui-web://other/views/a.json"),
            { source: "remote", url: "actionui-web://other/views/a.json", trust: "lessTrusted" }, "another host");
        assert.equal(TP.resolvedOrigin(own, null, null, null, "https://cdn.other.net/a.json").trust, "lessTrusted", "another server");
    } finally {
        if (saved === undefined) delete globalThis.document.baseURI;
        else globalThis.document.baseURI = saved;
    }
});

test("a window from a URL is judged by where it finally came from", async () => {
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com"] } });
    const body = JSON.stringify({ type: "Text", id: 1, properties: { text: "root" } });
    globalThis.fetch = async (url) => ({ ok: true, status: 200, url: url.includes("moved") ? "https://cdn.other.net/root.json" : url, text: async () => body });
    const straight = await Window.fromURL("https://ui.example.com/root.json", undefined, makeLogger());
    assert.equal(straight.origin.trust, "trusted");
    const moved = await Window.fromURL("https://ui.example.com/moved.json", undefined, makeLogger());
    assert.deepEqual(moved.origin, { source: "remote", url: "https://cdn.other.net/root.json", trust: "lessTrusted" });
});

// A fetch that answers only when its signal ends it: with headers never (`stallHeaders`), or
// with headers at once and a body that never comes.
function stallingFetch(stallHeaders) {
    return async (url, init) => {
        const aborted = () => new Promise((_, reject) => {
            if (!init?.signal) return;
            init.signal.addEventListener("abort", () => reject(init.signal.reason));
        });
        if (stallHeaders) return aborted();
        return {
            ok: true, status: 200, url, headers: { get: () => null },
            body: { getReader: () => ({ read: aborted, cancel: async () => {} }) },
        };
    };
}

test("a fetch of ActionUI JSON is given up after the configured time, the body's reading included", async () => {
    api.configure({ limits: { maximumDownloadTime: 0.2 } });
    for (const stallHeaders of [true, false]) {
        globalThis.fetch = stallingFetch(stallHeaders);
        const start = Date.now();
        await assert.rejects(Window.fromURL("https://ui.example.com/root.json", undefined, makeLogger()),
            { message: "loading it took longer than 0.2 seconds" }, `stalled ${stallHeaders ? "headers" : "body"}`);
        assert.ok(Date.now() - start < 5000);
    }
});

test("with no time limit a slow fetch of ActionUI JSON finishes", async () => {
    api.configure({ limits: { maximumDownloadTime: null } });
    const body = JSON.stringify({ type: "Text", id: 1, properties: { text: "root" } });
    let signalGiven = "unset";
    globalThis.fetch = async (url, init) => {
        signalGiven = init?.signal !== undefined;
        await new Promise((resolve) => setTimeout(resolve, 300));
        return { ok: true, status: 200, url, text: async () => body };
    };
    const window = await Window.fromURL("https://ui.example.com/root.json", undefined, makeLogger());
    assert.ok(window);
    assert.equal(signalGiven, false, "no time limit, no signal");
});

test("a trust policy sees the trusted origin as its default", () => {
    api.configure({ trust: { trustedOrigins: ["https://ui.example.com"] } });
    const defaults = [];
    TP.setTrustPolicy({ trust: (source, parent, byDefault) => { defaults.push(byDefault); return "lessTrusted"; } });
    const origin = TP.resolvedOrigin({ kind: "remote", fetchURL: "https://ui.example.com/a.json" }, null, null, null);
    assert.deepEqual(defaults, ["trusted"]);
    assert.equal(origin.trust, "lessTrusted", "the policy has the last word");
});

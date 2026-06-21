// Tests for the public Window / Application API (src/ActionUI.js).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";

let Window, Application;

before(async () => {
    installDom();
    ({ Window, Application } = await import("../src/ActionUI.js"));
});

test("Window.fromJSON parses an object and resolves :web suffixes", () => {
    const win = Window.fromJSON(
        { type: "VStack", properties: { "font:web": "largeTitle", font: "title" }, children: [{ type: "Text", id: 1 }] },
        undefined, makeLogger(),
    );
    assert.equal(win.rootElement.type, "VStack");
    assert.equal(win.rootElement.properties.font, "largeTitle", ":web variant wins");
    assert.equal(win.rootElement.children()[0].type, "Text");
});

test("Window.fromJSON parses a JSON string too", () => {
    const win = Window.fromJSON('{"type":"Text","id":5}', undefined, makeLogger());
    assert.equal(win.rootElement.type, "Text");
    assert.equal(win.rootElement.id, 5);
});

test("Window value/state/property bridges delegate to the model", () => {
    const win = Window.fromJSON({ type: "Text" }, undefined, makeLogger());
    const calls = [];
    win.model = {
        setElementValue: (...a) => calls.push(["setValue", ...a]),
        getElementValue: () => "v",
        setElementState: (...a) => calls.push(["setState", ...a]),
        setElementProperty: (...a) => calls.push(["setProp", ...a]),
    };
    win.setString(1, 0, "hi");
    win.setState(1, "k", true);
    win.setElementProperty(1, "opacity", 0.5);
    assert.deepEqual(calls, [
        ["setValue", 1, 0, "hi"],
        ["setState", 1, "k", true],
        ["setProp", 1, "opacity", 0.5],
    ]);
    assert.equal(win.getString(1), "v");
});

test("Application.action registers handlers; presentWindow wires the dispatcher", () => {
    const app = new Application({ name: "T" });
    let received = null;
    app.action("greet", (ctx) => { received = ctx; });

    const win = Window.fromJSON({ type: "Text", properties: { text: "hi" } }, undefined, makeLogger());
    app.presentWindow(win, makeElement());

    win.model.dispatchAction("greet", 7, 0, "payload");
    assert.ok(received, "the handler ran");
    assert.equal(received.actionID, "greet");
    assert.equal(received.viewID, 7);
    assert.equal(received.context, "payload");
});

test("presentWindow renders the root node into the container", () => {
    const app = new Application({ name: "T" });
    const win = Window.fromJSON({ type: "VStack", children: [{ type: "Text", id: 1, properties: { text: "hi" } }] }, undefined, makeLogger());
    const container = makeElement();
    app.presentWindow(win, container);
    assert.ok(win.rootNode, "a root node was built");
    assert.ok(container.children.includes(win.rootNode), "mounted into the container");
});

test("one Application presents several windows, each tracked by uuid", () => {
    const app = new Application({ name: "T" });
    const a = Window.fromJSON({ type: "Text", properties: { text: "a" } }, undefined, makeLogger());
    const b = Window.fromJSON({ type: "Text", properties: { text: "b" } }, undefined, makeLogger());
    app.presentWindow(a, makeElement());
    app.presentWindow(b, makeElement());
    assert.notEqual(a.uuid, b.uuid, "distinct surfaces have distinct uuids");
    assert.equal(app.getWindow(a.uuid), a);
    assert.equal(app.getWindow(b.uuid), b);
    assert.deepEqual(app.windowList, [a, b], "tracked in presentation order");
});

test("each presented window has its own model (same viewID addresses different surfaces)", () => {
    const app = new Application({ name: "T" });
    const a = Window.fromJSON({ type: "Text", id: 1, properties: { text: "a" } }, undefined, makeLogger());
    const b = Window.fromJSON({ type: "Text", id: 1, properties: { text: "b" } }, undefined, makeLogger());
    app.presentWindow(a, makeElement());
    app.presentWindow(b, makeElement());
    assert.notEqual(a.model, b.model, "separate models");
    a.setString(1, 0, "from A");
    b.setString(1, 0, "from B");
    assert.equal(a.getString(1), "from A");
    assert.equal(b.getString(1), "from B", "viewID 1 is independent per surface");
});

test("a sub-window action carries its own windowUUID so the host can disambiguate", () => {
    const app = new Application({ name: "T" });
    const seen = [];
    app.action("ping", (ctx) => seen.push(ctx.windowUUID));
    const a = Window.fromJSON({ type: "Text" }, undefined, makeLogger());
    const b = Window.fromJSON({ type: "Text" }, undefined, makeLogger());
    app.presentWindow(a, makeElement());
    app.presentWindow(b, makeElement());
    a.model.dispatchAction("ping", 0); // the model injects its own windowUUID
    b.model.dispatchAction("ping", 0);
    assert.deepEqual(seen, [a.uuid, b.uuid]);
});

test("closeWindow unmounts the node, disposes the model, and drops it from the registry", () => {
    const app = new Application({ name: "T" });
    const win = Window.fromJSON({ type: "Text", id: 1, properties: { text: "x" } }, undefined, makeLogger());
    const container = makeElement();
    app.presentWindow(win, container);
    win.setString(1, 0, "live");
    const node = win.rootNode;

    assert.equal(app.closeWindow(win), true, "closed");
    assert.equal(win.rootNode, null, "root reference cleared");
    assert.ok(!container.children.includes(node), "unmounted from the container");
    assert.equal(win.model.values.size, 0, "model bindings/values disposed");
    assert.equal(app.getWindow(win.uuid), undefined, "dropped from the registry");
    assert.equal(app.windowList.length, 0);
    assert.equal(app.closeWindow(win), false, "closing again is a no-op");
});

test("closeWindow also accepts a uuid string", () => {
    const app = new Application({ name: "T" });
    const win = Window.fromJSON({ type: "Text" }, undefined, makeLogger());
    app.presentWindow(win, makeElement());
    assert.equal(app.closeWindow(win.uuid), true);
    assert.equal(app.windowList.length, 0);
});

test("the menu-bar app shell wraps the primary window but not appShell:false surfaces", () => {
    const app = new Application({ name: "T" });
    app.setMenuBar([{ type: "CommandMenu", properties: { name: "Go" },
        children: [{ type: "Button", properties: { title: "Home", actionID: "go.home" } }] }], makeLogger());

    const primary = Window.fromJSON({ type: "Text", properties: { text: "main" } }, undefined, makeLogger());
    const primaryContainer = makeElement();
    app.presentWindow(primary, primaryContainer);
    assert.ok(!primaryContainer.children.includes(primary.rootNode), "primary is wrapped in the shell");

    const panel = Window.fromJSON({ type: "Text", properties: { text: "panel" } }, undefined, makeLogger());
    const panelContainer = makeElement();
    app.presentWindow(panel, panelContainer, { appShell: false });
    assert.ok(panelContainer.children.includes(panel.rootNode), "auxiliary surface mounts directly, no shell");
});

// ---- window uuid generation (crypto.randomUUID secure-context fallback) ----
// crypto.randomUUID() is secure-context-only - undefined on a plain-http origin that
// is not localhost (the Android emulator's http://10.0.2.2, a LAN IP). generateUUID()
// must still produce a valid uuid there, or every window build throws and blanks the app.

const UUID_V4_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function withCrypto(stub, fn) {
    const real = Object.getOwnPropertyDescriptor(globalThis, "crypto");
    Object.defineProperty(globalThis, "crypto", { value: stub, configurable: true, writable: true });
    try { fn(); } finally { Object.defineProperty(globalThis, "crypto", real); }
}

test("Window.uuid is a valid v4 UUID via crypto.randomUUID (secure context)", () => {
    assert.match(Window.fromJSON({ type: "Text", id: 1 }, undefined, makeLogger()).uuid, UUID_V4_RE);
});

test("Window.uuid falls back when crypto.randomUUID is unavailable (insecure-context http origin)", () => {
    const getRandomValues = globalThis.crypto.getRandomValues.bind(globalThis.crypto);
    withCrypto({ getRandomValues }, () => { // crypto present but no randomUUID, as on http://10.0.2.2
        assert.match(Window.fromJSON({ type: "Text", id: 1 }, undefined, makeLogger()).uuid, UUID_V4_RE);
    });
});

test("Window.uuid falls back to Math.random when crypto is entirely absent", () => {
    withCrypto(undefined, () => {
        assert.match(Window.fromJSON({ type: "Text", id: 1 }, undefined, makeLogger()).uuid, UUID_V4_RE);
    });
});

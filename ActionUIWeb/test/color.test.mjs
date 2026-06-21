// Tests for the Color element (src/Views/Color.js) - SwiftUI's Color used as a View.
// Covers registration, the color type-check, and the buildView DOM (greedy shape box,
// background painted from the resolved color, frame pinning).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers Color as a side effect
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

test("Color is registered with a callable validateProperties/buildView", () => {
    const c = getConstruction("Color");
    assert.ok(c, "Color registered");
    assert.equal(typeof c.validateProperties, "function");
    assert.equal(typeof c.buildView, "function");
});

test("validateProperties keeps a string color, drops a non-string", () => {
    const c = getConstruction("Color");
    assert.equal(c.validateProperties({ color: "blue" }, makeLogger()).color, "blue");
    assert.equal(c.validateProperties({ color: 123 }, makeLogger()).color, undefined);
});

test("buildView paints the resolved color and is a greedy shape box", () => {
    installDom();
    const node = getConstruction("Color").buildView({ type: "Color" }, { color: "red" }, { logger: makeLogger() });
    assert.ok(node.className.includes("aui-shape"), "greedy shape box");
    assert.ok(node.className.includes("aui-color"));
    assert.ok(node.style.background, "background painted from the color");
});

test("buildView with a frame pins the box (flex-grow 0)", () => {
    installDom();
    const node = getConstruction("Color").buildView(
        { type: "Color" }, { color: "blue", frame: { width: 100, height: 60 } }, { logger: makeLogger() },
    );
    assert.equal(node.style.flexGrow, "0");
});

test("buildView with no color does not throw (renders transparent)", () => {
    installDom();
    assert.doesNotThrow(() =>
        getConstruction("Color").buildView({ type: "Color" }, {}, { logger: makeLogger() }));
});

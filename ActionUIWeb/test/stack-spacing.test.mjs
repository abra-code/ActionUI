// Tests for the stacks' default spacing and the Spacer's minimum (src/Views/VStack.js, HStack.js,
// Spacer.js, LabeledContent.js, theme.css), as ActionUI lays them out on Apple: a VStack given no spacing has 0; an
// HStack given none has SwiftUI's default, 8 between views and none next to a Spacer; a Spacer is
// at least its minLength (8 by default) along its stack only.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { installDom, makeLogger } from "./dom-stub.mjs";

const css = readFileSync(fileURLToPath(new URL("../theme.css", import.meta.url)), "utf8");

let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const build = (type, properties) => {
    const ctx = { logger: makeLogger(), build: () => document.createElement("div"), model: {} };
    return getConstruction(type).buildView({ type, id: 0, properties, children: () => [] }, properties, ctx);
};

test("a VStack given no spacing has none; given one, that gap", () => {
    assert.equal(build("VStack", {}).style.gap, "0px");
    assert.equal(build("VStack", { spacing: 12 }).style.gap, "12px");
});

test("an HStack given no spacing takes SwiftUI's default rules; given one, that gap", () => {
    const plain = build("HStack", {});
    assert.ok(plain.classList.contains("aui-default-spacing"));
    assert.ok(!plain.style.gap, "the gap comes from the class");
    const spaced = build("HStack", { spacing: 4 });
    assert.equal(spaced.style.gap, "4px");
    assert.ok(!spaced.classList.contains("aui-default-spacing"));
    assert.match(css, /\.aui-hstack\.aui-default-spacing \{ gap: 8px; \}/);
    assert.match(css, /\.aui-hstack\.aui-default-spacing > \.aui-spacer,[^{]*\{ margin-inline: -8px; \}/,
        "a Spacer cancels the gap on its sides");
});

test("a Spacer's minLength is its minimum along its stack only", () => {
    const spacer = build("Spacer", { minLength: 30 });
    assert.equal(spacer.style.getPropertyValue("--aui-spacer-min"), "30px");
    assert.ok(!spacer.style.minWidth && !spacer.style.minHeight, "not both axes inline");
    assert.match(css, /\.aui-hstack > \.aui-spacer[^{]*\{ min-width: var\(--aui-spacer-min, 8px\); \}/);
    assert.match(css, /\.aui-vstack > \.aui-spacer[^{]*\{ min-height: var\(--aui-spacer-min, 8px\); \}/);
});

test("a LabeledContent is an HStack with the default spacing, and an empty title is 0 by 0", () => {
    const empty = build("LabeledContent", { title: "" });
    assert.ok(empty.className.split(" ").includes("aui-default-spacing"));
    const [title] = empty.querySelectorAll(".aui-labeled-content-title");
    assert.deepEqual(title.auiExtent, { w: { kind: "fixed", value: 0 }, h: { kind: "fixed", value: 0 } });
    const named = build("LabeledContent", { title: "Name" });
    assert.equal(named.querySelectorAll(".aui-labeled-content-title")[0].auiExtent, undefined, "its text decides");
    assert.match(css, /\.aui-form \.aui-labeled-content-title \{ flex: 1; \}/, "the title flexes only in a Form");
});

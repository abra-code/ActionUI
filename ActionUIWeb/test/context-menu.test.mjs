// Tests for the `contextMenu` View modifier (src/Helpers/ContextMenuModifier.js),
// the web side of Apple's `.contextMenu` / Android's long-press DropdownMenu.
//
// contextMenu / contextMenuPreview are TOP-LEVEL subview keys (real element subtrees),
// mirroring SwiftUI's two-builder `.contextMenu(menuItems:preview:)` - NOT a property
// descriptor array. So these exercise: the subview parsing, and applyContextMenu's DOM
// wiring (a panel built from the real menu-item elements + the optional preview subtree,
// an item click dispatching the item Button's own actionID, a right-click opening it).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { applyContextMenu } from "../src/Helpers/ContextMenuModifier.js";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers views (Menu — buildMenuChildNodes — etc.)
});

// Parses an element (so its contextMenu / contextMenuPreview subviews are real
// ActionUIElement subtrees) and wires it with a fake rootNode + dispatch/build spies.
function wired(raw) {
    installDom();
    const logger = makeLogger();
    const element = ActionUIElement.fromObject({ type: "Text", id: 7, ...raw }, logger);
    const node = makeElement("div");
    const rootNode = makeElement("div");
    const dispatched = [];
    const built = [];
    const ctx = {
        logger,
        model: { rootNode, dispatchAction: (...args) => dispatched.push(args) },
        // The preview is built through the registry; stub it to a marker so the test
        // does not need the full model. The interpreted menu items do not use build.
        build: (el) => { built.push(el); const m = makeElement("div"); m.className = "built-preview"; m.dataset.auiId = String(el.id); return m; },
    };
    applyContextMenu(node, element, element.properties, ctx);
    const panel = rootNode.children.find((c) => typeof c.className === "string" && c.className.includes("aui-context-menu"));
    return { node, panel, dispatched, built };
}

test("no contextMenu subview is a no-op", () => {
    const { panel, node } = wired({});
    assert.equal(panel, undefined, "no panel built");
    assert.equal(node.listenerCount("contextmenu"), 0, "no trigger wired");
});

test("a preview-only element (no items) does not make a context menu", () => {
    // An Apple context menu IS its action list; a preview alone is not one.
    const { panel } = wired({ contextMenuPreview: { type: "Image", id: 9, properties: { systemName: "photo" } } });
    assert.equal(panel, undefined);
});

test("menu items build as real menu rows; a destructive Button row is flagged", () => {
    const { panel } = wired({
        contextMenu: [
            { type: "Button", id: 10, properties: { title: "Rename", actionID: "ctx.rename" } },
            { type: "Divider", id: 11 },
            { type: "Button", id: 12, properties: { title: "Delete", role: "destructive", actionID: "ctx.delete" } },
        ],
    });
    assert.ok(panel, "panel appended to rootNode");
    const rows = panel.children;
    assert.equal(rows.length, 3, "two Buttons + a Divider");
    assert.equal(rows[0].children.at(-1).textContent, "Rename"); // title lives in the trailing span
    assert.equal(rows[0].classList.contains("aui-menu-item-destructive"), false);
    assert.ok(rows[2].classList.contains("aui-menu-item-destructive"), "destructive Delete row flagged");
});

test("choosing an item dispatches that Button's own actionID (viewID = the Button id)", () => {
    const { panel, dispatched } = wired({
        contextMenu: [
            { type: "Button", id: 10, properties: { title: "Rename", actionID: "ctx.rename" } },
            { type: "Button", id: 12, properties: { title: "Delete", role: "destructive", actionID: "ctx.delete" } },
        ],
    });
    panel.children[1].fire("click"); // choose "Delete"
    assert.deepEqual(dispatched, [["ctx.delete", 12]]);
});

test("a contextMenuPreview subtree renders as a block above the items", () => {
    const { panel, built } = wired({
        contextMenu: [{ type: "Button", id: 10, properties: { title: "Open", actionID: "ctx.open" } }],
        contextMenuPreview: { type: "Image", id: 9, properties: { systemName: "photo" } },
    });
    // The preview element was built through the registry (ctx.build), once.
    assert.deepEqual(built.map((e) => e.id), [9]);
    const first = panel.children[0];
    assert.ok(first.className.includes("aui-context-menu-preview"), "preview is the first block");
    assert.equal(first.children[0].className, "built-preview");
    // The item row follows the preview.
    assert.equal(panel.children[1].children.at(-1).textContent, "Open");
});

test("a context-menu host is marked so the iOS long-press callout / selection is suppressed", () => {
    const { node } = wired({
        contextMenu: [{ type: "Button", id: 10, properties: { title: "Open", actionID: "ctx.open" } }],
    });
    assert.ok(node.classList.contains("aui-context-menu-host"),
        "host gets the class that sets -webkit-touch-callout / user-select to none");
});

test("a right-click opens the menu and suppresses the browser's own", () => {
    const { node, panel } = wired({
        contextMenu: [{ type: "Button", id: 10, properties: { title: "Open", actionID: "ctx.open" } }],
    });
    node.getBoundingClientRect = () => ({ top: 10, left: 10, right: 60, bottom: 30, width: 50, height: 20 });
    global.document.documentElement = { clientWidth: 800, clientHeight: 600 };
    let prevented = false;
    node.fire("contextmenu", { preventDefault: () => { prevented = true; } });
    assert.ok(prevented, "default browser menu suppressed");
    assert.ok(panel.classList.contains("is-open"), "panel opened on right-click (Popover fallback class)");
});

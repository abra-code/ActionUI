// Tests for toolbar placement bucketing (resolveToolbar) plus the chrome wrap
// (wrapWithToolbar): the secondaryAction overflow menu and the navigation-title
// size modes (toolbarTitleDisplayMode). src/Helpers/ToolbarHelper.js.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";
import { resolveToolbar, wrapWithToolbar, buildPersistentToolbar, persistentToolbarItems } from "../src/Helpers/ToolbarHelper.js";

before(() => { installDom(); }); // wrapWithToolbar builds DOM via document.createElement

function withToolbar(items, properties = {}) {
    return ActionUIElement.fromObject({ type: "VStack", toolbar: items, properties }, makeLogger());
}
const item = (placement, title) => ({
    type: "ToolbarItem", properties: { placement }, content: { type: "Button", properties: { title } },
});

// Depth-first search of the stub element tree for the first node carrying a class.
// The renderer sets classes both ways (`.className =` assignment and
// classList.add), so check both.
function hasClass(node, cls) {
    const cn = node?.className;
    if (typeof cn === "string" && cn.split(/\s+/).includes(cls)) return true;
    return !!node?.classList?.contains?.(cls);
}
function findByClass(node, cls) {
    if (hasClass(node, cls)) return node;
    for (const child of node?.children ?? []) {
        const hit = findByClass(child, cls);
        if (hit) return hit;
    }
    return null;
}
// A ctx for wrapWithToolbar: a no-op model + a build that returns a fresh node.
const makeCtx = (logger) => ({ logger, model: { dispatchAction() {} }, build: () => makeElement("div") });

test("placements map to leading / principal / trailing / overflow / bottom buckets", () => {
    const el = withToolbar([
        item("navigation", "Back"),
        item("principal", "Title"),
        item("primaryAction", "Add"),
        item("secondaryAction", "Archive"),
        item("bottomBar", "Status"),
    ]);
    const b = resolveToolbar(el, makeLogger());
    assert.equal(b.leading.length, 1, "navigation -> leading");
    assert.equal(b.principal.length, 1, "principal -> principal");
    assert.equal(b.trailing.length, 1, "primaryAction -> trailing (default)");
    assert.equal(b.overflow.length, 1, "secondaryAction -> overflow");
    assert.equal(b.bottom.length, 1, "bottomBar -> bottom");
});

// The chrome half of the `hidden` parity work (Private/Missing_Features.md #30 / #41):
// in a bar - and ONLY in a bar - `hidden` collapses the action instead of reserving its
// space, matching Android's role-gating contract. The Button case is the one that was
// broken: renderChromeItem builds a toolbar Button's node directly, bypassing
// applyViewModifiers, so `hidden` on it used to do nothing at all on the web.
//
// The item is BUILT and then collapsed rather than filtered out of the buckets, which is
// what keeps its id addressable so a host can reveal it at runtime (see the applier test
// in property-mutation.test.mjs). These assertions pin that pair: collapsed, but present.
const hiddenItem = (placement, title) => ({
    type: "ToolbarItem",
    properties: { placement },
    content: { type: "Button", properties: { title, hidden: true } },
});

test("hidden chrome is built but collapsed, not dropped", () => {
    const logger = makeLogger();
    const el = withToolbar([item("navigation", "Back"), hiddenItem("primaryAction", "Admin")]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));

    const leading = findByClass(host, "aui-toolbar-leading");
    assert.equal(leading.children.length, 1);
    assert.equal(hasClass(leading.children[0], "aui-chrome-hidden"), false, "a visible item is untouched");
    assert.ok(hasClass(leading.children[0], "aui-chrome-item"), "every chrome node is marked for the runtime applier");

    const trailing = findByClass(host, "aui-toolbar-trailing");
    assert.equal(trailing.children.length, 1, "the hidden Button is still built (its id stays addressable)");
    assert.ok(hasClass(trailing.children[0], "aui-chrome-hidden"), "but it is collapsed, so it takes no room in the bar");
    assert.equal(logger.warningCount(), 0, "hiding chrome is not a warning");

    // Buckets are NOT filtered - the collapse is a render concern.
    const b = resolveToolbar(el, makeLogger());
    assert.equal(b.trailing.length, 1);
});

test("an all-hidden overflow still builds its trigger, its items and the bar", () => {
    const logger = makeLogger();
    const el = withToolbar([hiddenItem("secondaryAction", "Purge")]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));

    // Nothing is filtered anywhere: the bar renders (Android counts overflow items
    // unfiltered for that same decision), the trigger is there, and the hidden entry is
    // built - so its id is registered and setElementProperty can still reveal it. Android
    // does drop the trigger itself, which it can afford because it recomposes; on the web
    // an unbuilt item can never be revealed, so the dead ellipsis is the accepted cost.
    assert.ok(findByClass(host, "aui-toolbar-top"), "the bar renders");
    const overflow = findByClass(host, "aui-toolbar-overflow");
    assert.ok(overflow, "the trigger is built");
    const items = findByClass(overflow, "aui-toolbar-overflow-items");
    assert.equal(items.children.length, 1, "the hidden entry is built inside the panel");
    assert.ok(hasClass(items.children[0], "aui-chrome-hidden"), "and collapsed");
});

test("a chrome item marks its wrapper and flags its addressable node separately", () => {
    const logger = makeLogger();
    // A registry-built item whose buildElementView returns a WRAPPER around the element
    // node - what a decoration subview produces. The collapse class must land on the
    // wrapper (it is what takes up room in the bar) and the data-aui-chrome flag on the
    // inner node (it is what the property bridge resolves the id to).
    const ctx = {
        logger,
        model: { dispatchAction() {} },
        build: (element) => {
            const wrapper = makeElement("div");
            const inner = makeElement("div");
            inner.dataset.auiId = String(element.id);
            wrapper.appendChild(inner);
            return wrapper;
        },
    };
    const el = withToolbar([{
        type: "ToolbarItem",
        properties: { placement: "primaryAction" },
        content: { type: "Menu", id: 900, properties: { hidden: true } },
    }]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, ctx);
    const trailing = findByClass(host, "aui-toolbar-trailing");
    const wrapper = trailing.children[0];
    assert.ok(hasClass(wrapper, "aui-chrome-item"), "the wrapper carries the marker");
    assert.ok(hasClass(wrapper, "aui-chrome-hidden"), "and starts collapsed");
    assert.equal(wrapper.dataset.auiChrome, undefined, "the wrapper is not the addressable node");
    assert.equal(wrapper.children[0].dataset.auiChrome, "1", "the id node is flagged instead");
});

test("a hidden principal item falls through to the navigationTitle", () => {
    const logger = makeLogger();
    const el = withToolbar([hiddenItem("principal", "Switcher")], { navigationTitle: "Library" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    const title = findByClass(host, "aui-toolbar-title");
    assert.ok(title, "nothing visible claims the principal slot, so the title takes it");
    assert.equal(title.textContent, "Library");

    // A VISIBLE principal item still wins over the title, as before.
    const shown = withToolbar([item("principal", "Switcher")], { navigationTitle: "Library" });
    const shownHost = wrapWithToolbar(makeElement("div"), shown, shown.properties, makeCtx(logger));
    assert.equal(findByClass(shownHost, "aui-toolbar-title"), null);
});

test("a hidden persistent item is collapsed in its group, not filtered out", () => {
    const logger = makeLogger();
    const carrier = ActionUIElement.fromObject({
        type: "NavigationStack",
        persistentToolbar: [item("primaryAction", "Sync"), hiddenItem("primaryAction", "Admin")],
        properties: {},
    }, logger);
    const groups = buildPersistentToolbar(persistentToolbarItems(carrier), makeCtx(logger));
    assert.ok(groups?.trailing, "the group is built");
    assert.equal(groups.trailing.children.length, 2, "both items are built - the hidden one keeps its id");
    assert.equal(hasClass(groups.trailing.children[0], "aui-chrome-hidden"), false);
    assert.ok(hasClass(groups.trailing.children[1], "aui-chrome-hidden"), "the hidden one is collapsed");
});

test("a bar whose every item is hidden still renders, blank (Android parity)", () => {
    const logger = makeLogger();
    const el = withToolbar([hiddenItem("primaryAction", "Admin")]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    // Android computes "is there a top bar" from the unfiltered items and collapses each
    // one at render, so it shows an empty strip; the web now agrees rather than dropping
    // the bar entirely. Apple shows a bar too (its slots are merely blank).
    assert.ok(findByClass(host, "aui-toolbar-top"), "the bar itself is still there");
});

test("an unsupported placement (keyboard) is dropped with a warning", () => {
    const logger = makeLogger();
    const b = resolveToolbar(withToolbar([item("keyboard", "X")]), logger);
    assert.equal(b.leading.length + b.principal.length + b.trailing.length + b.overflow.length + b.bottom.length, 0);
    assert.ok(logger.warned("not supported on the web"));
});

test("ToolbarItemGroup contributes all its children to one slot", () => {
    const group = {
        type: "ToolbarItemGroup",
        properties: { placement: "primaryAction" },
        children: [{ type: "Button", properties: { title: "A" } }, { type: "Button", properties: { title: "B" } }],
    };
    const b = resolveToolbar(withToolbar([group]), makeLogger());
    assert.equal(b.trailing.length, 2, "both group children land in trailing");
});

test("secondaryAction items render as an overflow ('...') menu in the trailing slot", () => {
    const logger = makeLogger();
    const el = withToolbar([item("secondaryAction", "Archive"), item("secondaryAction", "Move")]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    const trailing = findByClass(host, "aui-toolbar-trailing");
    const overflow = findByClass(trailing, "aui-toolbar-overflow");
    assert.ok(overflow, "an overflow menu is appended to the trailing slot");
    const trigger = findByClass(overflow, "aui-toolbar-overflow-trigger");
    assert.ok(trigger, "the overflow has a '...' trigger");
    const items = findByClass(overflow, "aui-toolbar-overflow-items");
    assert.equal(items.children.length, 2, "both secondary actions are items in the panel");
});

test("a large title mode renders the title on its own large row, not inline", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "Library", toolbarTitleDisplayMode: "large" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "large");
    assert.ok(findByClass(host, "aui-toolbar-largetitle"), "a large-title row is rendered");
    assert.equal(findByClass(host, "aui-toolbar-title"), null, "no compact inline title in the bar");
});

test("an inline/automatic title stays compact in the principal slot", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "Documents", toolbarTitleDisplayMode: "inline" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "inline");
    assert.ok(findByClass(host, "aui-toolbar-title"), "the compact inline title is rendered");
    assert.equal(findByClass(host, "aui-toolbar-largetitle"), null, "no large-title row");
});

test("an invalid toolbarTitleDisplayMode warns and falls back to automatic", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "X", toolbarTitleDisplayMode: "huge" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "automatic");
    assert.ok(logger.warned("Invalid toolbarTitleDisplayMode"));
});

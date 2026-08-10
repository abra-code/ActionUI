// Tests for `persistentToolbar` on the web renderer (Missing_Features #36, design
// section 7): the items a NavigationStack / NavigationSplitView keeps in the bar on every
// screen inside it.
//
// The web is the host where this is structurally hard, and the tests are shaped around
// why. Every destination pane is built up front and toggled with `display`, so all panes
// are live in the DOM at once. Building the persistent items into each pane would put N
// live nodes behind ONE authored id, and ActionUIModel.findNode resolves an id to a single
// node - the host would update the first pane's copy and silently miss the rest. So the
// items are built once and MOVED into the visible pane, and the assertion that pins that
// design is a node count: after switching panes twice, exactly one instance exists.
//
// That count is only meaningful because the stub's appendChild detaches from the previous
// parent, as the real DOM does (see dom-stub.mjs). Before that fix a moved node stayed in
// its old parent's children too, so the count came back 2 whatever the renderer did - the
// assertion failed on a correct implementation and could not tell it from a per-pane copy.

import { test, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, ActionUIModel, ActionUIElement, Window, dom;

before(async () => {
    dom = installDom();
    ({ Window } = await import("../src/ActionUI.js")); // also registers every view
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});
beforeEach(() => { dom = installDom(); });

function hasClass(node, cls) {
    const cn = node?.className;
    if (typeof cn === "string" && cn.split(/\s+/).includes(cls)) return true;
    return !!node?.classList?.contains?.(cls);
}
function findAllByClass(node, cls, out = []) {
    if (hasClass(node, cls)) out.push(node);
    for (const child of node?.children ?? []) findAllByClass(child, cls, out);
    return out;
}
function findByClass(node, cls) {
    return findAllByClass(node, cls)[0] ?? null;
}
// Every node under `node` stamped with the given authored element id. One id must never
// resolve to more than one live node.
function findAllByDataId(node, id, out = []) {
    if (node?.dataset?.auiId === String(id)) out.push(node);
    for (const child of node?.children ?? []) findAllByDataId(child, id, out);
    return out;
}
// Every text visible anywhere under `node`, for asserting which probe labels render.
function textsUnder(node, out = []) {
    if (typeof node?.textContent === "string" && node.textContent.length) out.push(node.textContent);
    for (const child of node?.children ?? []) textsUnder(child, out);
    return out;
}

function build(raw) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    model.dispatchAction = () => {};
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    model.rootNode = root;
    return { root, model, logger };
}

const item = (placement, id, title) => ({
    type: "ToolbarItem",
    properties: { placement },
    content: { type: "Button", id, properties: { title } },
});

// A stack with one persistent item, a root that declares its own toolbar, a destination
// that declares its own, and a destination that declares nothing at all.
const STACK = {
    type: "NavigationStack",
    id: 1,
    persistentToolbar: [item("topBarTrailing", 61, "PERS")],
    content: {
        type: "VStack",
        id: 2,
        properties: { navigationTitle: "TBRoot" },
        toolbar: [item("topBarTrailing", 21, "ROOT")],
        children: [{ type: "Text", id: 3, properties: { text: "root" } }],
    },
    destinations: [
        {
            type: "VStack",
            id: 500,
            properties: { navigationTitle: "TBDestA" },
            toolbar: [item("topBarTrailing", 41, "DSTA")],
            children: [{ type: "Text", id: 501, properties: { text: "a" } }],
        },
        {
            type: "VStack",
            id: 600,
            children: [{ type: "Text", id: 601, properties: { text: "b" } }],
        },
    ],
};

// The visible pane: the root pane, or the destination pane that is not display:none.
function visiblePane(root) {
    return findAllByClass(root, "aui-nav-stack-pane").find((p) => p.style.display !== "none") ?? null;
}

test("persistentToolbar: the container's item renders on the root screen, beside the root's own", () => {
    const { root } = build(STACK);
    const texts = textsUnder(visiblePane(root));
    assert.ok(texts.includes("PERS"), `expected PERS on the root screen, saw ${JSON.stringify(texts)}`);
    assert.ok(texts.includes("ROOT"), "the root's own item must still render");
});

test("persistentToolbar: exactly ONE instance exists after switching panes twice", () => {
    // The assertion that would have caught the N-instance design. One authored id must
    // never be behind more than one live node, or setElementProperty silently updates the
    // wrong copy.
    const { root, model } = build(STACK);
    const count = () => findAllByClass(root, "aui-toolbar-persistent-trailing").length;

    assert.equal(count(), 1, "one instance at the root");
    model.setElementState(1, "navigationPath", [500]);
    assert.equal(count(), 1, "still one after pushing a destination");
    model.setElementState(1, "navigationPath", [600]);
    assert.equal(count(), 1, "still one after switching to another destination");
    model.setElementState(1, "navigationPath", []);
    assert.equal(count(), 1, "still one back at the root");
});

test("persistentToolbar: the item follows the visible pane", () => {
    const { root, model } = build(STACK);
    const group = findByClass(root, "aui-toolbar-persistent-trailing");

    const livesInVisiblePane = () => {
        const pane = visiblePane(root);
        return findAllByClass(pane, "aui-toolbar-persistent-trailing")[0] === group;
    };

    assert.ok(livesInVisiblePane(), "at the root");
    model.setElementState(1, "navigationPath", [500]);
    assert.ok(livesInVisiblePane(), "on the pushed destination");
    model.setElementState(1, "navigationPath", [600]);
    assert.ok(livesInVisiblePane(), "on the destination that declares no toolbar");
    model.setElementState(1, "navigationPath", []);
    assert.ok(livesInVisiblePane(), "back at the root");
});

test("persistentToolbar: a destination that declares no toolbar still gets a bar", () => {
    // Destination 600 has no toolbar and no navigationTitle, so before this feature it had
    // no chrome host at all. The container's items have to bring one with them.
    const { root, model } = build(STACK);
    model.setElementState(1, "navigationPath", [600]);
    const pane = visiblePane(root);

    assert.ok(findByClass(pane, "aui-toolbar-host"), "the bare destination needs a chrome host");
    const texts = textsUnder(pane);
    assert.ok(texts.includes("PERS"), `expected PERS, saw ${JSON.stringify(texts)}`);
    assert.ok(!texts.includes("DSTA"), "the other destination's item must not leak in");
});

test("persistentToolbar: a screen's own items keep their place and the persistent one trails", () => {
    // Ordering: within a slot the screen's items come first, so a persistent item holds the
    // same outer position as screens change.
    const { root, model } = build(STACK);
    model.setElementState(1, "navigationPath", [500]);
    const trailing = findByClass(visiblePane(root), "aui-toolbar-trailing");
    const texts = textsUnder(trailing);

    assert.deepEqual(texts.filter((t) => t === "DSTA" || t === "PERS"), ["DSTA", "PERS"]);
});

test("persistentToolbar: a container's own `toolbar` is the deprecated alias, and warns", () => {
    const aliased = { ...STACK, persistentToolbar: undefined, toolbar: [item("topBarTrailing", 11, "ALIAS")] };
    delete aliased.persistentToolbar;

    const logger = makeLogger();
    Window.fromJSON(aliased, "w", logger);
    assert.ok(logger.warned("Deprecated"), "authoring the old spelling must say so");

    const { root } = build(aliased);
    assert.ok(textsUnder(visiblePane(root)).includes("ALIAS"), "and it must still work");
});

test("persistentToolbar: declared where nothing can render it, it warns rather than vanishing", () => {
    const logger = makeLogger();
    Window.fromJSON({
        type: "VStack",
        id: 1,
        persistentToolbar: [item("topBarTrailing", 61, "PERS")],
        children: [{ type: "Text", id: 2, properties: { text: "x" } }],
    }, "w", logger);

    assert.ok(logger.warned("is ignored"), "a persistentToolbar off a container renders nothing");
});

test("persistentToolbar: a correct document is silent", () => {
    const logger = makeLogger();
    Window.fromJSON(STACK, "w", logger);
    assert.equal(logger.warningCount(), 0);
});

test("persistentToolbar: an id-bearing item stays exactly one addressable node across panes", () => {
    // This is the failure the one-instance design exists to prevent, stated precisely.
    // A chrome Button is special-cased into a raw <button> with no data-aui-id (existing
    // web behavior, shared with screen toolbars), so it is not host-addressable either
    // way. Any OTHER content goes through the registry and IS stamped with its id - and
    // ActionUIModel.findNode resolves an id to a single node via querySelector. Build the
    // items per pane and the host would update whichever copy happened to come first in
    // the DOM, which is usually one in a hidden pane.
    const withText = {
        ...STACK,
        persistentToolbar: [{
            type: "ToolbarItem",
            properties: { placement: "topBarTrailing" },
            content: { type: "Text", id: 62, properties: { text: "SYNC" } },
        }],
    };
    const { root, model } = build(withText);
    const addressable = () => findAllByDataId(root, 62);

    assert.equal(addressable().length, 1, "one node for id 62 at the root");
    model.setElementState(1, "navigationPath", [500]);
    assert.equal(addressable().length, 1, "still one after a push");
    model.setElementState(1, "navigationPath", [600]);
    assert.equal(addressable().length, 1, "still one after switching destination");

    // And it is the one on screen, not a stranded copy.
    assert.ok(findAllByDataId(visiblePane(root), 62).length === 1, "and it is in the visible pane");
});

const SPLIT = {
    type: "NavigationSplitView",
    id: 50,
    persistentToolbar: [item("topBarTrailing", 61, "PERS")],
    sidebar: {
        type: "List", id: 51,
        children: [
            { type: "Label", id: 60, properties: { title: "A", destinationViewId: 70 } },
            { type: "Label", id: 62, properties: { title: "B", destinationViewId: 71 } },
        ],
    },
    detail: { type: "Text", id: 52, properties: { text: "Pick one" } },
    destinations: [
        { type: "Text", id: 70, properties: { text: "Detail A" } },
        { type: "Text", id: 71, properties: { text: "Detail B" } },
    ],
};

test("persistentToolbar: a split view keeps one instance across selection changes", () => {
    const { root, model } = build(SPLIT);
    const count = () => findAllByClass(root, "aui-toolbar-persistent-trailing").length;

    assert.equal(count(), 1, "one instance before any selection");
    model.setElementState(50, "selectedDestination", 70);
    assert.equal(count(), 1, "still one after selecting a destination");
    model.setElementState(50, "selectedDestination", 71);
    assert.equal(count(), 1, "still one after selecting another");
});

test("persistentToolbar: a split view puts the items in the SELECTED detail node", () => {
    // A count alone would pass with the items parked in a hidden detail node. This pins
    // that they are in the one on screen.
    const { root, model } = build(SPLIT);
    const detailPane = findByClass(root, "aui-nav-split-detail");
    // Walk UP from the group to the direct child of the detail pane holding it; that node
    // is the detail whose `display` the selection toggles. Walking down instead would pick
    // the compact Back affordance, which is also a child of the pane.
    const hostDetailNode = () => {
        let n = findByClass(root, "aui-toolbar-persistent-trailing");
        while (n && n.parentNode !== detailPane) n = n.parentNode;
        return n;
    };

    model.setElementState(50, "selectedDestination", 70);
    assert.ok(hostDetailNode(), "the items must be inside the detail pane");
    assert.notEqual(hostDetailNode().style.display, "none", "and inside the detail that is SHOWN (A)");
    const nodeForA = hostDetailNode();

    model.setElementState(50, "selectedDestination", 71);
    assert.notEqual(hostDetailNode().style.display, "none", "and inside the detail that is SHOWN (B)");
    assert.notEqual(hostDetailNode(), nodeForA, "selecting another destination must move them");
});

test("persistentToolbar: an expanded split view builds NO sidebar bar", () => {
    // The sidebar host is created lazily, on the first placement that targets it. Built
    // eagerly it would be a permanently empty strip - with a rule under it - above the
    // first sidebar row on every desktop render.
    const { root } = build(SPLIT);
    const sidebar = findByClass(root, "aui-nav-split-sidebar");
    assert.equal(findAllByClass(sidebar, "aui-toolbar-host").length, 0);
});

test("persistentToolbar: a compact split view moves the items to the sidebar, and back", () => {
    // The compact one-column flow is the only layout where the detail is hidden, so it is
    // the only one where the sidebar has to carry the items or they would be on screen
    // nowhere. It is also the most fragile path here, hence a test rather than an argument.
    const { root, model } = build(SPLIT);
    const split = findByClass(root, "aui-nav-split");
    const sidebar = findByClass(root, "aui-nav-split-sidebar");
    const inSidebar = () => findAllByClass(sidebar, "aui-toolbar-persistent-trailing").length;

    dom.fireResize(split, 400);
    assert.equal(split.dataset.compact, "true", "the split must actually be compact");
    assert.equal(inSidebar(), 1, "nothing selected: the sidebar is the only pane on screen");
    assert.equal(findAllByClass(root, "aui-toolbar-persistent-trailing").length, 1, "and still just one");

    model.setElementState(50, "selectedDestination", 70);
    assert.equal(inSidebar(), 0, "selecting shows the detail, so the items go with it");
    assert.equal(findAllByClass(root, "aui-toolbar-persistent-trailing").length, 1);

    dom.fireResize(split, 1200);
    assert.equal(findAllByClass(root, "aui-toolbar-persistent-trailing").length, 1, "expanding keeps one");
});

test("persistentToolbar: expanding again leaves no empty bar behind in the sidebar", () => {
    // Building the sidebar host lazily is not enough on its own: once a narrow window has
    // created it, widening must also hide it, or the empty strip and its rule sit above
    // the first sidebar row for the rest of the session.
    const { root } = build(SPLIT);
    const split = findByClass(root, "aui-nav-split");
    const sidebar = findByClass(root, "aui-nav-split-sidebar");

    dom.fireResize(split, 400);
    const host = findByClass(sidebar, "aui-toolbar-host");
    assert.ok(host, "compact builds it");
    assert.notEqual(host.style.display, "none", "and shows it");

    dom.fireResize(split, 1200);
    assert.equal(host.style.display, "none", "expanding must hide it again");
    assert.equal(findAllByClass(sidebar, "aui-toolbar-persistent-trailing").length, 0,
        "and the items must have gone back to the detail");
});

test("persistentToolbar: a static split view puts the items in the detail pane", () => {
    const STATIC = {
        type: "NavigationSplitView",
        id: 80,
        persistentToolbar: [item("topBarTrailing", 61, "PERS")],
        sidebar: { type: "Text", id: 81, properties: { text: "side" } },
        detail: { type: "Text", id: 82, properties: { text: "detail" } },
    };
    const { root } = build(STATIC);
    const detailPane = findByClass(root, "aui-nav-split-detail");
    const sidebar = findByClass(root, "aui-nav-split-sidebar");

    assert.equal(findAllByClass(detailPane, "aui-toolbar-persistent-trailing").length, 1);
    assert.equal(findAllByClass(sidebar, "aui-toolbar-persistent-trailing").length, 0,
        "both panes are visible here, so the sidebar must not show a second copy");
});

test("persistentToolbar: a bottomBar item lands in a bottom bar, not the top one", () => {
    // ensureBottomMount is a separate path from the three top slots.
    const withBottom = { ...STACK, persistentToolbar: [item("bottomBar", 63, "PBOTTOM")] };
    const { root } = build(withBottom);
    const pane = visiblePane(root);
    const bottom = findByClass(pane, "aui-toolbar-bottom");

    assert.ok(bottom, "a bottom bar must exist");
    assert.ok(textsUnder(bottom).includes("PBOTTOM"));
    assert.ok(!textsUnder(findByClass(pane, "aui-toolbar-top") ?? { children: [] }).includes("PBOTTOM"));
});

test("persistentToolbar: a leading item lands in the leading slot", () => {
    const withLeading = { ...STACK, persistentToolbar: [item("topBarLeading", 64, "PLEAD")] };
    const { root } = build(withLeading);
    const pane = visiblePane(root);

    assert.ok(textsUnder(findByClass(pane, "aui-toolbar-leading")).includes("PLEAD"));
});

test("persistentToolbar: persistentToolbar and the alias merge, persistent first", () => {
    const both = {
        ...STACK,
        persistentToolbar: [item("topBarTrailing", 61, "PERS")],
        toolbar: [item("topBarTrailing", 11, "ALIAS")],
    };
    const { root } = build(both);
    const group = findByClass(visiblePane(root), "aui-toolbar-persistent-trailing");

    assert.deepEqual(textsUnder(group).filter((t) => t === "PERS" || t === "ALIAS"), ["PERS", "ALIAS"]);
});

test("persistentToolbar: a stack nested in a destination keeps BOTH containers' items, each once", () => {
    // The nesting property that matters: pushing into an inner stack, and then pushing
    // again INSIDE it, must not lose the outer container's item, duplicate it, or drop the
    // inner container's own.
    //
    // Note what this does NOT assert. On Apple and Android the outer items are merged into
    // each inner screen's bar; on the web they sit in a bar attached above the inner stack,
    // because `wrapWithToolbar` refuses to wrap a container and the mount goes on the node
    // that holds it. Both keep the item on screen throughout, which is the contract; the
    // layout differs, and that is recorded in the commit note rather than pinned here.
    const nested = {
        type: "NavigationStack",
        id: 1,
        persistentToolbar: [item("topBarTrailing", 61, "PERS")],
        content: {
            type: "VStack", id: 2, properties: { navigationTitle: "Outer" },
            children: [{ type: "NavigationLink", id: 30, properties: { title: "Go", destinationViewId: 900 } }],
        },
        destinations: [
            {
                type: "NavigationStack",
                id: 900,
                persistentToolbar: [item("topBarTrailing", 65, "INNER")],
                content: {
                    type: "VStack", id: 901, properties: { navigationTitle: "Inner" },
                    children: [{ type: "NavigationLink", id: 31, properties: { title: "Deeper", destinationViewId: 950 } }],
                },
                destinations: [
                    {
                        type: "VStack", id: 950, properties: { navigationTitle: "Deep" },
                        children: [{ type: "Text", id: 951, properties: { text: "deep" } }],
                    },
                ],
            },
        ],
    };
    const { root, model } = build(nested);
    const countText = (label) => textsUnder(root).filter((t) => t === label).length;

    model.setElementState(1, "navigationPath", [900]);
    assert.equal(countText("PERS"), 1, "the outer container's item, once");
    assert.equal(countText("INNER"), 1, "the inner container's item, once");

    model.setElementState(900, "navigationPath", [950]);
    assert.equal(countText("PERS"), 1, "still exactly one outer item after pushing inside the inner stack");
    assert.equal(countText("INNER"), 1, "and still exactly one inner item");
});

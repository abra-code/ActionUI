// ToolbarHelper.js — renders an element's `toolbar` (and `navigationTitle`) as
// screen chrome. Web analog of ActionUI/Helpers/ToolbarHelper.swift and
// ActionUIAndroid Helpers/ToolbarHelper.kt (Private/Toolbar_Design.md).
//
// SwiftUI's `.toolbar {}` attaches to a view; the enclosing navigation chrome /
// window renders it. The web has no navigation bar to inherit, so — like
// Android's screen-level Scaffold — a `toolbar` (or a `navigationTitle`) wraps
// the view's node in a chrome host: a top bar (leading | title-or-principal |
// trailing) plus an optional bottom bar, with the original node as the body.
// The wrap is applied at the single build choke point (ActionUIRegistry's
// buildElementView), so any view that declares chrome gets it — the document
// root, a NavigationStack destination, an NSV pane's content, etc.
//
// JSON shape (mirrors Apple/Android): a `"toolbar": [ ... ]` array of
//   { "type": "ToolbarItem", "properties": { "placement": "..." }, "content": {...} }
//   { "type": "ToolbarItemGroup", "properties": { "placement": "..." }, "children": [...] }
// A ToolbarItem contributes its single `content`; a ToolbarItemGroup each of its
// `children`; both at the item's placement slot. These carriers are never built
// through the registry — resolveToolbar extracts their content/children here.
//
// Two refinements toward iOS parity:
//   * `secondaryAction`-placed items collapse into an overflow ("...") pull-down
//     at the trailing end (buildOverflowMenu), instead of trailing inline -
//     Apple's own secondary-action reading.
//   * `navigationTitle` honors `toolbarTitleDisplayMode` (automatic/inline/large/
//     inlineLarge): large modes render the title on its own large row beneath the
//     action bar; automatic/inline keep it compact inline (titleDisplayMode).

import { selectLabelIcon, labelIcon, systemSymbolGlyph } from "./SymbolIcon.js";
import { makeFloatingPanel } from "./PopoverPlacement.js";

// The navigation containers own their own per-pane chrome (NavigationStack
// renders chrome on each destination it builds; NavigationSplitView on its
// panes), so the container element itself is never wrapped — mirrors Android's
// hasRootToolbarChrome exclusion. The list lives in the model (ActionUIElement.js)
// because the parser needs it too, and the model is the layer neither side can
// avoid importing - one definition rather than two that can drift.
import { isNavigationContainer } from "../Common/ActionUIElement.js";

// Maps a SwiftUI toolbar placement to a web chrome slot. The web is a
// macOS-like desktop target: iOS leading/trailing map to the bar ends, the
// macOS `navigation` to leading and `status` to trailing, `bottomBar` to a
// bottom bar, `secondaryAction` to an overflow ("...") menu (Apple's own
// reading: secondary actions collapse into an overflow), `keyboard` is
// unsupported (dropped), and everything else (incl. `automatic` and the primary
// action placements) trails. Pure.
function resolveSlot(placement) {
    switch (placement) {
        case "topBarLeading":
        case "cancellationAction":
        case "navigation":
            return "leading";
        case "principal":
            return "principal";
        case "bottomBar":
            return "bottom";
        case "secondaryAction":
            return "overflow";
        case "keyboard":
            return "unsupported";
        default:
            // automatic / topBarTrailing / confirmationAction / destructiveAction
            // / primaryAction / status / unknown -> trailing
            return "trailing";
    }
}

// The items a navigation container keeps in the bar on every screen inside it: its
// `persistentToolbar`, plus its `toolbar` as a DEPRECATED ALIAS.
//
// The alias exists because a container-level `toolbar` was never a screen toolbar on any
// host - the web dropped it outright at wrapWithToolbar's guard, macOS put it in the
// window toolbar where it already persisted - so reading it here gives all four hosts one
// behavior and keeps existing documents working. ActionUIElement.fromObject warns at parse
// time when it sees one. Pure.
export function persistentToolbarItems(element) {
    return [...element.persistentToolbar(), ...element.toolbar()];
}

// The items to apply as THIS SCREEN's own toolbar. Empty for a navigation container: its
// `toolbar` belongs to the container, and the container applies it to every screen inside
// instead. Pure.
export function screenToolbarItems(element) {
    return isNavigationContainer(element.type) ? [] : element.toolbar();
}

// Flattens a list of ToolbarItem / ToolbarItemGroup carriers into chrome buckets by slot.
// Pure (logging aside).
function bucketItems(items, logger) {
    const buckets = { leading: [], principal: [], trailing: [], overflow: [], bottom: [] };
    for (const item of items) {
        const placement = item.properties?.placement;
        const contents = item.type === "ToolbarItemGroup"
            ? item.children()
            : (item.content() ? [item.content()] : []);
        const slot = resolveSlot(placement);
        if (slot === "unsupported") {
            logger.log(`Toolbar placement '${placement}' is not supported on the web; item dropped`, "warning");
            continue;
        }
        buckets[slot].push(...contents);
    }
    return buckets;
}

// Flattens an element's own `toolbar` into chrome buckets by slot. Pure (logging
// aside), so it is unit-testable.
export function resolveToolbar(element, logger) {
    return bucketItems(screenToolbarItems(element), logger);
}

// The navigation-title size modes (Apple's `toolbarTitleDisplayMode`, mirrored in
// View.swift). The web is a macOS-like desktop target, so "automatic" and "inline"
// both render the compact in-bar title; "large"/"inlineLarge" render the iOS-style
// large title on its own row beneath the action bar. `inlineLarge`'s collapse-on-
// scroll is not modeled (no scroll listener) - it renders large, the documented
// best-effort divergence. Returns "automatic" for absent/invalid (warns on invalid),
// mirroring View.swift's validation. Pure (logging aside).
const VALID_TITLE_MODES = new Set(["automatic", "inline", "large", "inlineLarge"]);
function titleDisplayMode(properties, logger) {
    const mode = properties.toolbarTitleDisplayMode;
    if (mode === undefined) return "automatic";
    if (typeof mode !== "string" || !VALID_TITLE_MODES.has(mode)) {
        logger.log(`Invalid toolbarTitleDisplayMode '${mode}'; expected one of automatic/inline/large/inlineLarge. Using 'automatic'.`, "warning");
        return "automatic";
    }
    return mode;
}

// Renders one chrome item. A Button becomes a borderless app-bar action (the
// toolbar idiom — firing its actionID with the title as context), the same
// special-case as Android's RenderChrome: the registered Button is a styled
// pill, wrong inside a bar where actions are borderless. Any other content
// (e.g. a Menu) is built through the registry, where it renders itself the same
// everywhere. Like Apple/Android, a toolbar item ignores layout modifiers.
function renderChromeItem(element, ctx) {
    if (element.type === "Button") {
        const props = element.properties ?? {};
        const node = document.createElement("button");
        node.type = "button";
        node.className = "aui-toolbar-button";
        const icon = labelIcon(selectLabelIcon(props, "assetImage", "ToolbarItem", ctx.logger), props, "ToolbarItem", ctx.logger);
        const title = typeof props.title === "string" ? props.title : "";
        if (icon) {
            node.classList.add("aui-toolbar-button-has-icon");
            node.appendChild(icon);
        }
        if (title) {
            const span = document.createElement("span");
            span.textContent = title;
            node.appendChild(span);
        }
        if (typeof props.actionID === "string") {
            node.addEventListener("click", () => ctx.model.dispatchAction(props.actionID, element.id, 0, { title }));
        }
        return node;
    }
    return ctx.build(element);
}

function slotDiv(cls, items, ctx) {
    const div = document.createElement("div");
    div.className = cls;
    items.forEach((el) => div.appendChild(renderChromeItem(el, ctx)));
    return div;
}

// The overflow menu: an "..." trigger that opens a floating list of the
// `secondaryAction` items - Apple's secondary-action idiom rendered as the web's
// own pull-down. Built on the shared top-layer panel (Helpers/PopoverPlacement.js,
// the same machinery as Menu / the `.popover` modifier), so it escapes the
// toolbar's clip and light-dismisses on outside-click / Escape. Each item is a
// normal chrome item (a toolbar Button becomes a borderless row); clicking one
// fires its actionID and closes the menu. The dropdown reuses Menu's `.aui-menu-
// items` chrome.
function buildOverflowMenu(items, ctx) {
    const wrap = document.createElement("div");
    wrap.className = "aui-toolbar-overflow";

    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "aui-toolbar-button aui-toolbar-overflow-trigger";
    trigger.setAttribute("aria-label", "More");
    trigger.setAttribute("aria-haspopup", "menu");
    // The ellipsis glyph through the shared SF->Material seam (iOS's overflow icon).
    trigger.appendChild(systemSymbolGlyph("ellipsis", {}, ctx.logger, (name) =>
        `Toolbar overflow systemImage '${name}' has no SF->Material mapping; icon omitted.`));

    const panel = document.createElement("div");
    panel.className = "aui-menu-items aui-toolbar-overflow-items";
    panel.setAttribute("role", "menu");

    const floating = makeFloatingPanel(panel, trigger, { containmentRoots: [wrap] });
    trigger.addEventListener("click", () => { if (floating.open) floating.close(); else floating.show(); });

    items.forEach((el) => {
        const itemNode = renderChromeItem(el, ctx);
        itemNode.classList.add("aui-toolbar-overflow-item");
        itemNode.addEventListener("click", () => floating.close());
        panel.appendChild(itemNode);
    });

    wrap.append(trigger, panel);
    return wrap;
}

// Wraps bodyNode in a chrome host when the element declares a `toolbar` or a
// `navigationTitle`; otherwise returns bodyNode unchanged. The navigation
// containers are never wrapped (they own their per-pane chrome).
export function wrapWithToolbar(bodyNode, element, properties, ctx) {
    if (isNavigationContainer(element.type)) return bodyNode;

    const hasToolbar = element.toolbar().length > 0;
    const title = typeof properties.navigationTitle === "string" ? properties.navigationTitle : null;
    if (!hasToolbar && title === null) return bodyNode;

    const buckets = hasToolbar
        ? resolveToolbar(element, ctx.logger)
        : { leading: [], principal: [], trailing: [], overflow: [], bottom: [] };

    const host = document.createElement("div");
    host.className = "aui-toolbar-host";

    // Navigation-title size mode. "large"/"inlineLarge" pull the title out of the
    // action bar and onto its own large row beneath it (the iOS large-title idiom);
    // "automatic"/"inline" keep it compact, inline in the bar. The CSS reads the
    // mode off the host.
    const mode = titleDisplayMode(properties, ctx.logger);
    host.dataset.auiTitleMode = mode;
    const largeTitle = mode === "large" || mode === "inlineLarge";
    const inlineTitle = largeTitle ? null : title; // title shown inside the action bar
    const hasOverflow = buckets.overflow.length > 0;

    // Top action bar: rendered when there are top items (incl. an overflow menu) or
    // an inline title.
    if (buckets.leading.length || buckets.principal.length || buckets.trailing.length || hasOverflow || inlineTitle !== null) {
        const bar = document.createElement("div");
        bar.className = "aui-toolbar-bar aui-toolbar-top";

        const principal = document.createElement("div");
        principal.className = "aui-toolbar-principal";
        if (buckets.principal.length) {
            buckets.principal.forEach((el) => principal.appendChild(renderChromeItem(el, ctx)));
        } else if (inlineTitle !== null) {
            const t = document.createElement("span");
            t.className = "aui-toolbar-title";
            t.textContent = inlineTitle;
            principal.appendChild(t);
        }

        // Trailing slot: the trailing items, then (if any) the overflow menu at the end.
        const trailing = slotDiv("aui-toolbar-trailing", buckets.trailing, ctx);
        if (hasOverflow) trailing.appendChild(buildOverflowMenu(buckets.overflow, ctx));

        bar.append(
            slotDiv("aui-toolbar-leading", buckets.leading, ctx),
            principal,
            trailing,
        );
        host.appendChild(bar);
    }

    // Large title row (iOS-style), beneath the action bar and above the body.
    if (largeTitle && title !== null) {
        const big = document.createElement("div");
        big.className = "aui-toolbar-largetitle";
        big.textContent = title;
        host.appendChild(big);
    }

    const body = document.createElement("div");
    body.className = "aui-toolbar-body";
    body.appendChild(bodyNode);
    host.appendChild(body);

    if (buckets.bottom.length) {
        const bar = document.createElement("div");
        bar.className = "aui-toolbar-bar aui-toolbar-bottom";
        buckets.bottom.forEach((el) => bar.appendChild(renderChromeItem(el, ctx)));
        host.appendChild(bar);
    }

    return host;
}

// ---------------------------------------------------------------------------
// persistentToolbar: ONE instance, reparented
//
// The web builds every destination pane up front and toggles `display`, so all panes are
// live in the DOM at once. Merging a container's persistent items into each pane's bar
// would put N live nodes behind ONE authored id, and `ActionUIModel.findNode` resolves an
// id to a SINGLE node (`querySelector` returns the first match) - so a host
// `setElementProperty` would update the first pane's copy and silently miss the rest. That
// bug is invisible on a one-destination smoke test, which is exactly how it would ship.
//
// Instead the items are built once, owned by the container, and MOVED into the visible
// pane's bar whenever the active pane changes. One node, one id: every existing property
// applier and the whole host-addressing path keep working untouched. And one bar: the
// persistent items share the pane's own bar rather than adding a second, which is what
// both Apple hosts do.
// ---------------------------------------------------------------------------

const PERSISTENT_MOUNT_CLASS = "aui-toolbar-persistent-mount";

// The bar slots a persistent group can occupy. `overflow` is not among them: persistent
// secondaryAction items ride at the end of the trailing group instead (see below).
const PERSISTENT_SLOTS = ["leading", "principal", "trailing", "bottom"];

function hasClass(node, className) {
    return typeof node?.className === "string" && node.className.split(/\s+/).includes(className);
}

// First direct child carrying `className`, or null. Deliberately not `querySelector`: this
// only ever wants a direct child, and a descendant match would find an inner element's own
// chrome (a pane can contain another toolbar host) and mount the items into the wrong bar.
function findChildByClass(node, className) {
    for (const child of node.children ?? []) {
        if (hasClass(child, className)) return child;
    }
    return null;
}

// Builds the ONE set of nodes for a container's persistent items, keyed by the bar slot
// each belongs in; null when there are none. These nodes are never rebuilt, only moved.
export function buildPersistentToolbar(items, ctx) {
    if (!items.length) return null;
    const buckets = bucketItems(items, ctx.logger);
    const groups = {};
    for (const slot of PERSISTENT_SLOTS) {
        const contents = buckets[slot];
        // Persistent secondaryAction items get their own overflow menu at the end of the
        // trailing group. Apple folds them into the screen's single menu; the web cannot,
        // because a pane's menu is built per pane while this node is built once. So a
        // document that uses secondaryAction on BOTH a screen and its container shows two
        // "..." menus here where Apple shows one. Documented divergence, not a bug to hunt.
        const overflow = slot === "trailing" && buckets.overflow.length ? buckets.overflow : null;
        if (!contents.length && overflow === null) continue;
        const group = document.createElement("span");
        group.className = `aui-toolbar-persistent aui-toolbar-persistent-${slot}`;
        contents.forEach((el) => group.appendChild(renderChromeItem(el, ctx)));
        if (overflow !== null) group.appendChild(buildOverflowMenu(overflow, ctx));
        groups[slot] = group;
    }
    return Object.keys(groups).length ? groups : null;
}

function ensureTopMount(host, slot) {
    let bar = findChildByClass(host, "aui-toolbar-top");
    if (bar === null) {
        // The pane declared no toolbar and no navigationTitle, so it has no action bar to
        // merge into. It needs one now: a screen inside a container with persistent items
        // gets a bar even when it declares nothing itself.
        bar = document.createElement("div");
        bar.className = "aui-toolbar-bar aui-toolbar-top";
        const leading = document.createElement("div");
        leading.className = "aui-toolbar-leading";
        const principal = document.createElement("div");
        principal.className = "aui-toolbar-principal";
        const trailing = document.createElement("div");
        trailing.className = "aui-toolbar-trailing";
        bar.append(leading, principal, trailing);
        host.insertBefore(bar, host.children[0] ?? null);
    }
    let slotNode = findChildByClass(bar, `aui-toolbar-${slot}`);
    if (slotNode === null) {
        slotNode = document.createElement("div");
        slotNode.className = `aui-toolbar-${slot}`;
        bar.appendChild(slotNode);
    }
    const mount = document.createElement("span");
    mount.className = PERSISTENT_MOUNT_CLASS;
    // Appended LAST, after whatever the screen declared in this slot, so a persistent item
    // keeps the same outer position as screens change.
    slotNode.appendChild(mount);
    return mount;
}

function ensureBottomMount(host) {
    let bar = findChildByClass(host, "aui-toolbar-bottom");
    if (bar === null) {
        bar = document.createElement("div");
        bar.className = "aui-toolbar-bar aui-toolbar-bottom";
        host.appendChild(bar);
    }
    const mount = document.createElement("span");
    mount.className = PERSISTENT_MOUNT_CLASS;
    bar.appendChild(mount);
    return mount;
}

// Gives one pane a mount point per slot in `slots`, creating the chrome host and whichever
// bar rows it is missing. Returns the node to place in the pane - `builtNode` itself when
// it was already a chrome host, otherwise a new host wrapping it - and the mount per slot.
export function attachPersistentToolbarMounts(builtNode, slots) {
    if (!slots.length) return { node: builtNode, mounts: {} };

    let host = builtNode;
    if (!hasClass(host, "aui-toolbar-host")) {
        host = document.createElement("div");
        host.className = "aui-toolbar-host";
        host.dataset.auiTitleMode = "automatic";
        const body = document.createElement("div");
        body.className = "aui-toolbar-body";
        body.appendChild(builtNode);
        host.appendChild(body);
    }

    const mounts = {};
    for (const slot of slots) {
        mounts[slot] = slot === "bottom" ? ensureBottomMount(host) : ensureTopMount(host, slot);
    }
    return { node: host, mounts };
}

// Moves the persistent groups into one pane's mount points. Called synchronously from the
// pane switch, so it lands before paint and there is no flash of a bar without its items.
// `appendChild` on a node that already has a parent detaches it from that parent, which is
// what keeps exactly one live node per authored id.
//
// A missing mount is a bug in the caller, not an authoring error: every pane is given a
// mount for every slot the container occupies. It leaves the group where it is - stranded
// in the pane the user just left, which is at least visible and traceable - and says so,
// rather than removing it and leaving the author looking for items that are simply gone.
export function movePersistentToolbar(groups, mounts, logger) {
    if (groups === null) return;
    for (const slot of Object.keys(groups)) {
        const mount = mounts?.[slot];
        if (!mount) {
            logger?.log(`persistentToolbar: no '${slot}' mount in the pane being shown; items left in place`, "warning");
            continue;
        }
        // Already there: do nothing. Re-appending a node to its current parent is a real
        // move in the DOM, and moving a node blurs anything focused inside it - so a
        // no-op placement (a repeated setState of the same selection, a compact crossing
        // that does not change which pane shows) would silently steal focus from a
        // persistent button the user is tabbing through.
        if (groups[slot].parentNode === mount) continue;
        mount.appendChild(groups[slot]);
    }
}

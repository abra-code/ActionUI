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
// hasRootToolbarChrome exclusion.
const NAV_CONTAINER_TYPES = new Set(["NavigationStack", "NavigationSplitView"]);

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

// Flattens an element's `toolbar` into chrome buckets by slot. Pure (logging
// aside), so it is unit-testable.
export function resolveToolbar(element, logger) {
    const buckets = { leading: [], principal: [], trailing: [], overflow: [], bottom: [] };
    for (const item of element.toolbar()) {
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
    if (NAV_CONTAINER_TYPES.has(element.type)) return bodyNode;

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

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

import { selectLabelIcon, labelIcon } from "./SymbolIcon.js";

// The navigation containers own their own per-pane chrome (NavigationStack
// renders chrome on each destination it builds; NavigationSplitView on its
// panes), so the container element itself is never wrapped — mirrors Android's
// hasRootToolbarChrome exclusion.
const NAV_CONTAINER_TYPES = new Set(["NavigationStack", "NavigationSplitView"]);

// Maps a SwiftUI toolbar placement to a web chrome slot. The web is a
// macOS-like desktop target: iOS leading/trailing map to the bar ends, the
// macOS `navigation` to leading and `status` to trailing, `bottomBar` to a
// bottom bar, `keyboard` is unsupported (dropped), and everything else (incl.
// `automatic` and the action placements) trails. Pure.
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
        case "keyboard":
            return "unsupported";
        default:
            // automatic / topBarTrailing / confirmationAction / destructiveAction
            // / primaryAction / secondaryAction / status / unknown → trailing
            return "trailing";
    }
}

// Flattens an element's `toolbar` into chrome buckets by slot. Pure (logging
// aside), so it is unit-testable.
export function resolveToolbar(element, logger) {
    const buckets = { leading: [], principal: [], trailing: [], bottom: [] };
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
        : { leading: [], principal: [], trailing: [], bottom: [] };

    const host = document.createElement("div");
    host.className = "aui-toolbar-host";

    // Top bar: rendered when there are top items or a title.
    if (buckets.leading.length || buckets.principal.length || buckets.trailing.length || title !== null) {
        const bar = document.createElement("div");
        bar.className = "aui-toolbar-bar aui-toolbar-top";

        const principal = document.createElement("div");
        principal.className = "aui-toolbar-principal";
        if (buckets.principal.length) {
            buckets.principal.forEach((el) => principal.appendChild(renderChromeItem(el, ctx)));
        } else if (title !== null) {
            const t = document.createElement("span");
            t.className = "aui-toolbar-title";
            t.textContent = title;
            principal.appendChild(t);
        }

        bar.append(
            slotDiv("aui-toolbar-leading", buckets.leading, ctx),
            principal,
            slotDiv("aui-toolbar-trailing", buckets.trailing, ctx),
        );
        host.appendChild(bar);
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

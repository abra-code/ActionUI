// ContextMenuModifier.js - the `contextMenu` View modifier.
// Web analog of Apple's `.contextMenu` (View.swift applyModifiers) and Android's
// long-press DropdownMenu (Helpers/ContextMenuHelper.kt). Applies to ANY view.
//
// Why two subview slots, not a property array:
// SwiftUI's `.contextMenu(menuItems:preview:)` is itself TWO ViewBuilders - a menu of
// action items, and an optional arbitrary "preview" card shown above the menu on a
// long-press (iOS). The preview is the only slot where free-form layout (an HStack of
// items) or a big Image renders richly. So ActionUI models it the same way: `contextMenu`
// is an ARRAY subview of real menu-item elements (Button / Divider / Section) and
// `contextMenuPreview` is an optional SINGLE arbitrary subview. Real element subtrees let
// a designer place any views, not buttons synthesized from a flat descriptor array.
//
// The menu items reuse Menu's exact interpretation (a Button -> a menu row that fires its
// actionID and dismisses); the preview subtree is rendered as-is (ctx.build) into a block
// above the items - the web stand-in for the iOS lift-and-enlarge preview.
//
// The menu is the shared top-layer floating panel the Menu pull-down uses
// (Helpers/PopoverPlacement.js, the Popover API), anchored to the element; the trigger is
// the web idiom for a context menu: the native `contextmenu` event (right-click) plus a
// long-press on touch.

import { buildMenuChildNodes } from "./MenuItems.js";
import { makeFloatingPanel } from "./PopoverPlacement.js";

const LONG_PRESS_MS = 500; // touch hold to open (the platform long-press convention)

// Attaches a context menu to `node` when the element declares a non-empty `contextMenu`
// subview array, otherwise a no-op. Called from ModifierResolver.applyViewModifiers, so
// any view inherits it. A `contextMenuPreview` subview (optional) renders above the items.
export function applyContextMenu(node, element, properties, ctx) {
    const items = element.subviews?.contextMenu;
    // An Apple context menu IS its action list; a preview with no items is not one.
    if (!Array.isArray(items) || items.length === 0) return;
    const previewElement = element.subviews?.contextMenuPreview ?? null;

    const panel = document.createElement("div");
    panel.className = "aui-menu-items aui-context-menu";
    panel.setAttribute("role", "menu");

    const controller = makeFloatingPanel(panel, node, { containmentRoots: [node], arrowEdge: "top" });
    const dismiss = () => controller.close();

    // The preview subtree (when present): an arbitrary element rendered as-is, above the
    // items. Built through the registry (ctx.build), so it is a real view, not interpreted.
    if (previewElement) {
        const preview = document.createElement("div");
        preview.className = "aui-context-menu-preview";
        preview.appendChild(ctx.build(previewElement));
        panel.appendChild(preview);
    }

    // The action items: real elements interpreted as menu rows (Button -> a row that fires
    // its actionID and dismisses, Divider, Section), reusing Menu's interpretation exactly.
    for (const item of items) {
        for (const itemNode of buildMenuChildNodes(item, ctx, dismiss)) {
            panel.appendChild(itemNode);
        }
    }

    // Top-layer sibling (escapes ancestor overflow); rootNode is not set yet at build
    // time, so the live renderer lands it on document.body (a test passes rootNode).
    (ctx.model.rootNode ?? document.body).appendChild(panel);

    // Suppress the host's NATIVE long-press behaviour so only our menu shows. On desktop
    // `preventDefault()` on contextmenu (below) cancels the browser menu, but iOS Safari's
    // long-press is a separate mechanism - the callout bar (Save Image / Copy / link
    // preview) and the text-selection magnifier - that contextmenu/preventDefault does not
    // cover (and older iOS does not even fire contextmenu). The CSS class kills both:
    // `-webkit-touch-callout: none` (the callout) + `user-select: none` (the selection).
    node.classList.add("aui-context-menu-host");

    // The long-press fallback timer (for browsers that do NOT fire `contextmenu` on a
    // long-press, e.g. iOS < 16.4); declared first so the contextmenu handler can cancel it.
    let pressTimer = null;
    const cancelPress = () => { if (pressTimer !== null) { clearTimeout(pressTimer); pressTimer = null; } };

    // Open the menu, cancelling any pending long-press timer. show() is idempotent, so a
    // browser that fires BOTH the timer AND `contextmenu` (modern iOS / Android) opens once
    // instead of the two paths fighting - a toggle here would close the just-opened menu.
    // Dismiss is outside-click / Escape (makeFloatingPanel), so opening need not toggle.
    const open = () => { cancelPress(); controller.show(); };

    // Right-click (desktop) + long-press where the browser fires `contextmenu` (modern
    // iOS/Android): suppress the browser's own menu and open ours.
    node.addEventListener("contextmenu", (event) => {
        event.preventDefault();
        open();
    });

    // Long-press fallback (touch): a stationary hold opens the menu; movement / release cancels.
    node.addEventListener("touchstart", () => {
        cancelPress();
        pressTimer = setTimeout(() => { pressTimer = null; controller.show(); }, LONG_PRESS_MS);
    }, { passive: true });
    node.addEventListener("touchend", cancelPress, { passive: true });
    node.addEventListener("touchmove", cancelPress, { passive: true });
}

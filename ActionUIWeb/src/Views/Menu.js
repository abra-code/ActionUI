// Menu.js — Menu element.
// Web analog of ActionUI/Views/Menu.swift (and ActionUIAndroid Views/Menu.kt).
//
// A pull-down menu: a trigger that opens a floating list of action items. The
// item list is a native top-layer popover (the Popover API), so it overlays
// content and - crucially - escapes every ancestor overflow/clip (e.g. the
// NavigationSplitView pane's overflow:scroll), the way a SwiftUI Menu pull-down
// escapes its window. This is the web's "window-level overlay" / popover infra.
// The trigger is the `title`
// (or a custom `label` view, when present — the ellipsis-icon Menu), and the
// `children` are interpreted as menu items, not rendered as standalone views:
//   * Button  → an item showing the button's title (+ its systemImage /
//     materialName:web icon through the shared SymbolIcon seam); clicking it
//     dismisses the menu and dispatches the button's actionID.
//   * Divider → a separator line between items.
//   * Section → its `header` as a non-interactive label, then its children as
//     nested items — a named group.
//   * anything else → a best-effort label item (warns); arbitrary view content
//     has no menu analog.
//
// Divergence from Apple: submenus collapse to inline items (no nested popovers),
// and the trigger defaults to "Menu" when the title is empty and there is no
// label (so the control is visible), the Android stance. See
// Private/Web_Porting_Notes.md (Menu).

import { register } from "../Common/ActionUIRegistry.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";

// The Popover API renders the dropdown in the browser top layer, escaping every
// ancestor overflow/clip (e.g. the NavigationSplitView pane). We use a "manual"
// popover driven by our own click + dismiss handlers, NOT the declarative
// popovertarget invoker with auto light-dismiss: that keeps open/close,
// positioning, and dismissal uniform across engines (Safari's declarative-invoker
// and toggle-event timing diverge from Firefox/Chrome) while still getting the
// top layer. Detected once; when unavailable the dropdown degrades to an in-flow
// absolute panel toggled by a class (clipped by overflow ancestors, the prior
// behavior) with a manual outside-click dismiss.
const SUPPORTS_POPOVER = typeof HTMLElement !== "undefined"
    && Object.prototype.hasOwnProperty.call(HTMLElement.prototype, "popover");

register("Menu", {
    valueType: "none",

    // Mirrors Menu.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("Menu title must be a String; ignoring", "warning");
            delete validated.title;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const menu = document.createElement("div");
        menu.className = "aui-menu";

        const trigger = document.createElement("button");
        trigger.type = "button";
        trigger.className = "aui-menu-trigger";

        // A custom `label` view replaces the title (the SF-Symbol-trigger Menu);
        // otherwise the title text, defaulting to "Menu" so the trigger shows.
        const labelElement = element.subviews?.label;
        if (labelElement) {
            trigger.appendChild(ctx.build(labelElement));
        } else {
            const text = document.createElement("span");
            text.className = "aui-menu-title";
            text.textContent = properties.title || "Menu";
            trigger.appendChild(text);
        }
        const caret = document.createElement("span");
        caret.className = "aui-menu-caret";
        caret.textContent = "▾"; // a downward caret
        trigger.appendChild(caret);
        menu.appendChild(trigger);

        const items = document.createElement("div");
        items.className = "aui-menu-items";
        items.setAttribute("role", "menu");

        // Wire open/close before building items so each item can dismiss the menu.
        let dismiss;
        if (SUPPORTS_POPOVER) {
            items.setAttribute("popover", "manual"); // top layer; we own dismissal
            dismiss = wirePopover(items, trigger, menu);
        } else {
            dismiss = () => menu.classList.remove("is-open");
            wireFallbackToggle(menu, trigger);
        }

        for (const child of element.children()) {
            appendMenuChild(items, child, ctx, dismiss);
        }
        menu.appendChild(items);

        return menu;
    },
});

// Drives a manual top-layer popover: the trigger toggles it, and while open we
// anchor it under the trigger (the Popover API shows it centered by default) and
// dismiss on an outside pointerdown or Escape. Positioning runs synchronously
// right after showPopover() - not from the async `toggle` event - so it does not
// depend on toggle-event timing (which differs in Safari). Returns a close()
// the menu items reuse to dismiss. This is event-driven floating-element
// placement (what any menu needs; a native <select> does the same internally),
// not the JS measure/relayout layout loop the layout engine avoids - the browser
// still sizes the panel.
function wirePopover(popover, trigger, menu) {
    const place = () => placePopover(popover, trigger);
    let open = false;
    const onPointerDown = (event) => { if (!menu.contains(event.target)) close(); };
    const onKeyDown = (event) => { if (event.key === "Escape") close(); };

    function show() {
        if (open) return;
        open = true;
        popover.showPopover();
        place();
        window.addEventListener("scroll", place, true); // capture: follow the scrolling pane
        window.addEventListener("resize", place);
        document.addEventListener("pointerdown", onPointerDown, true);
        document.addEventListener("keydown", onKeyDown);
    }
    function close() {
        if (!open) return;
        open = false;
        popover.hidePopover();
        window.removeEventListener("scroll", place, true);
        window.removeEventListener("resize", place);
        document.removeEventListener("pointerdown", onPointerDown, true);
        document.removeEventListener("keydown", onKeyDown);
    }

    trigger.addEventListener("click", () => { if (open) close(); else show(); });
    return close;
}

function placePopover(popover, trigger) {
    const rect = trigger.getBoundingClientRect();
    const gap = 4;
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    const panelWidth = popover.offsetWidth;
    const panelHeight = popover.offsetHeight;

    // Horizontal: align the panel's left edge to the trigger, clamped on-screen.
    let left = Math.min(rect.left, viewportWidth - panelWidth - gap);
    left = Math.max(gap, left);

    // Vertical: open below the trigger; flip above if it would overflow the
    // bottom and there is room above (SwiftUI menus flip the same way).
    let top = rect.bottom + gap;
    if (top + panelHeight > viewportHeight - gap && rect.top - panelHeight - gap >= gap) {
        top = rect.top - panelHeight - gap;
    }
    top = Math.max(gap, Math.min(top, viewportHeight - panelHeight - gap));

    popover.style.left = `${left}px`;
    popover.style.top = `${top}px`;
}

// Legacy fallback (no Popover API): toggle an in-flow absolute panel via a class,
// with a manual outside-click dismiss. The panel is clipped by overflow
// ancestors - the behavior before the top-layer popover - but functional.
function wireFallbackToggle(menu, trigger) {
    trigger.addEventListener("click", () => menu.classList.toggle("is-open"));
    document.addEventListener("pointerdown", (event) => {
        if (menu.classList.contains("is-open") && !menu.contains(event.target)) {
            menu.classList.remove("is-open");
        }
    });
}

// Classifies one Menu child by type, mirroring Android's menuItemKind.
function menuItemKind(child) {
    switch (child.type) {
        case "Button": return "action";
        case "Divider": return "divider";
        case "Section": return "section";
        default: return "other";
    }
}

// Appends one Menu child as item(s) to `container`; `dismiss` closes the menu
// after an action. Children are interpreted (a Button is an action declaration —
// title / icon / actionID — that the menu presents as an item), not built
// through the registry as the filled controls they would render standalone.
function appendMenuChild(container, child, ctx, dismiss) {
    switch (menuItemKind(child)) {
        case "action": {
            const props = child.properties ?? {};
            const item = document.createElement("button");
            item.type = "button";
            item.className = "aui-menu-item";
            item.setAttribute("role", "menuitem");

            const icon = labelIcon(
                selectLabelIcon(props, "assetImage", "Menu item", ctx.logger),
                props, "Menu item", ctx.logger,
            );
            if (icon) item.appendChild(icon);

            const text = document.createElement("span");
            text.textContent = typeof props.title === "string" ? props.title : "";
            item.appendChild(text);

            item.addEventListener("click", () => {
                dismiss();
                if (typeof props.actionID === "string") {
                    ctx.model.dispatchAction(props.actionID, child.id);
                }
            });
            container.appendChild(item);
            break;
        }
        case "divider": {
            const rule = document.createElement("hr");
            rule.className = "aui-menu-divider";
            container.appendChild(rule);
            break;
        }
        case "section": {
            const header = child.properties?.header;
            if (typeof header === "string") {
                const heading = document.createElement("div");
                heading.className = "aui-menu-section-header";
                heading.textContent = header;
                container.appendChild(heading);
            }
            for (const nested of child.children()) {
                appendMenuChild(container, nested, ctx, dismiss);
            }
            break;
        }
        default: {
            ctx.logger.log(`Menu child '${child.type}' is not a menu item; showing a plain label`, "warning");
            const props = child.properties ?? {};
            const label = (typeof props.title === "string" && props.title)
                || (typeof props.text === "string" && props.text)
                || child.type;
            const item = document.createElement("button");
            item.type = "button";
            item.className = "aui-menu-item aui-menu-item-plain";
            item.textContent = label;
            item.addEventListener("click", dismiss);
            container.appendChild(item);
        }
    }
}

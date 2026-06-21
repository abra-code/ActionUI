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
import { buildMenuChildNodes } from "../Helpers/MenuItems.js";
import { makeFloatingPanel } from "../Helpers/PopoverPlacement.js";
import { interpretiveFlatBinding } from "../Helpers/InsertionHelper.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
// At phone width a Menu pull-down presents as a bottom action sheet rather than an
// anchored dropdown (the bottom-sheet theme rules use the same 480px breakpoint).
import { isCompactWidth } from "../Helpers/Modality.js";

// The dropdown is a shared top-layer floating panel (Helpers/PopoverPlacement.js):
// it renders in the browser top layer (the Popover API), escaping every ancestor
// overflow/clip (e.g. the NavigationSplitView pane), and falls back to a
// class-toggled fixed panel when the Popover API is absent. The same controller
// backs the element-level `.popover` modifier — this is where that machinery was
// first written.

register("Menu", {
    valueType: "none",

    // `children` is a runtime-insertable flat container (Apple's
    // Menu.insertableContainers["children"]): a host can add/remove items at
    // runtime. A child is interpreted into menu item node(s) (a Section expands to
    // a header + its items), so this is the interpretive insertion path.
    insertableContainers: { children: ContainerShape.FLAT },

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
        // The whole menu (trigger + items) counts as "inside" for outside-click
        // dismissal; the trigger toggles it.
        const panel = makeFloatingPanel(items, trigger, { containmentRoots: [menu] });
        trigger.addEventListener("click", () => {
            if (panel.open) { panel.close(); return; }
            // Compact (phone): present as a bottom action sheet (the iOS idiom),
            // not an anchored dropdown - the theme overrides the JS placement when
            // the class is set; the controller still owns open/close + light-dismiss.
            items.classList.toggle("aui-menu-sheet", isCompactWidth());
            panel.show();
        });
        const dismiss = () => panel.close();

        // Each child maps to one slot of one-or-more DOM nodes (a Section expands
        // to a header + its items). The slots track child order/nodes so a runtime
        // insertElement places an item at the right offset and removeElement tears
        // its node(s) down.
        const slots = []; // [{ id, nodes: [Node, ...] }]
        for (const child of element.children()) {
            const nodes = buildMenuChildNodes(child, ctx, dismiss);
            nodes.forEach((n) => items.appendChild(n));
            slots.push({ id: child.id, nodes });
        }
        menu.appendChild(items);

        if (element.id > 0) {
            ctx.model.bindContainer(element.id, "children", interpretiveFlatBinding(
                (childEl, id, index) => {
                    const nodes = buildMenuChildNodes(childEl, ctx, dismiss);
                    if (nodes.length && id > 0) nodes[0].dataset.auiId = String(id); // so removeElement finds it
                    const ref = slots[index]?.nodes[0] ?? null;
                    nodes.forEach((n) => items.insertBefore(n, ref));
                    slots.splice(index, 0, { id, nodes });
                },
                (id) => {
                    const i = slots.findIndex((slot) => slot.id === id);
                    if (i < 0) return;
                    slots[i].nodes.forEach((n) => n.remove());
                    slots.splice(i, 1);
                },
                element.children().map((child) => child.id),
            ));
        }

        return menu;
    },
});


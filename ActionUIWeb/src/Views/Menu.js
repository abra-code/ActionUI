// Menu.js — Menu element.
// Web analog of ActionUI/Views/Menu.swift (and ActionUIAndroid Views/Menu.kt).
//
// A pull-down menu: a trigger that opens a floating list of action items, built
// as the native <details>/<summary> pair (the same primitive as DisclosureGroup,
// so no Phase 3 popover infrastructure is needed) with the item list absolutely
// positioned to overlay content rather than push it. The trigger is the `title`
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
// Divergence from Apple: the items render in the document (a CSS-positioned
// dropdown), not a window-level popover — submenus collapse to inline items, and
// the trigger defaults to "Menu" when the title is empty and there is no label
// (so the control is visible), the Android stance. See
// Private/Web_Porting_Notes.md (Menu).

import { register } from "../Common/ActionUIRegistry.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";

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
        const details = document.createElement("details");
        details.className = "aui-menu";

        const summary = document.createElement("summary");
        summary.className = "aui-menu-trigger";

        // A custom `label` view replaces the title (the SF-Symbol-trigger Menu);
        // otherwise the title text, defaulting to "Menu" so the trigger shows.
        const labelElement = element.subviews?.label;
        if (labelElement) {
            summary.appendChild(ctx.build(labelElement));
        } else {
            const text = document.createElement("span");
            text.className = "aui-menu-title";
            text.textContent = properties.title || "Menu";
            summary.appendChild(text);
        }
        const caret = document.createElement("span");
        caret.className = "aui-menu-caret";
        caret.textContent = "▾"; // ▾
        summary.appendChild(caret);
        details.appendChild(summary);

        const items = document.createElement("div");
        items.className = "aui-menu-items";
        items.setAttribute("role", "menu");
        const dismiss = () => { details.open = false; };
        for (const child of element.children()) {
            appendMenuChild(items, child, ctx, dismiss);
        }
        details.appendChild(items);

        // A floating menu closes on an outside click (native <details> does not).
        document.addEventListener("pointerdown", (event) => {
            if (details.open && !details.contains(event.target)) details.open = false;
        });

        return details;
    },
});

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

// MenuItems.js - interpreting menu-item child elements into menu-row DOM nodes.
// Factored out of Views/Menu.js so both the `Menu` element and the `contextMenu`
// modifier (Helpers/ContextMenuModifier.js) share one interpretation WITHOUT a module
// cycle: this helper depends only on the glyph seam (SymbolIcon.js), never on the
// registry, so ContextMenuModifier can import it even though the registry imports the
// modifier resolver that calls ContextMenuModifier.
//
// A Menu/contextMenu child is INTERPRETED (a Button is an action declaration - title /
// icon / role / actionID - shown as a menu row), not built through the registry as the
// filled control it would render standalone.

import { selectLabelIcon, labelIcon } from "./SymbolIcon.js";

// Classifies one child by type, mirroring Android's menuItemKind.
function menuItemKind(child) {
    switch (child.type) {
        case "Button": return "action";
        case "Divider": return "divider";
        case "Section": return "section";
        default: return "other";
    }
}

// Interprets one child into its menu-item DOM node(s) (a Section expands to a header +
// its nested items, flattened - the web collapses submenus to inline items). `dismiss`
// closes the menu after an action. Returns the node list so the caller can append it or
// insert it at a runtime offset (the insertion API).
export function buildMenuChildNodes(child, ctx, dismiss) {
    switch (menuItemKind(child)) {
        case "action":
            return [buildActionItem(child, ctx, dismiss)];
        case "divider": {
            const rule = document.createElement("hr");
            rule.className = "aui-menu-divider";
            return [rule];
        }
        case "section": {
            const nodes = [];
            const header = child.properties?.header;
            if (typeof header === "string") {
                const heading = document.createElement("div");
                heading.className = "aui-menu-section-header";
                heading.textContent = header;
                nodes.push(heading);
            }
            for (const nested of child.children()) {
                nodes.push(...buildMenuChildNodes(nested, ctx, dismiss));
            }
            return nodes;
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
            return [item];
        }
    }
}

// An action item: the button's title (+ icon through the shared glyph seam); a
// destructive role tints the row red; clicking dismisses the menu and dispatches the
// declared actionID (viewID = the Button's own id).
function buildActionItem(child, ctx, dismiss) {
    const props = child.properties ?? {};
    const item = document.createElement("button");
    item.type = "button";
    item.className = "aui-menu-item";
    if (props.role === "destructive") item.classList.add("aui-menu-item-destructive");
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
    return item;
}

// TabView.js — TabView element.
// Web analog of ActionUI/Views/TabView.swift (and ActionUIAndroid Views/TabView.kt).
//
// A tabbed container: a strip of tab buttons over a content area showing one
// tab's `content` at a time. valueType is "int" — the selected tab index
// (0-based) — so a host reads/writes the selection with get/setInt(id) and the
// strip follows. `selection` seeds the initial index (default 0, clamped into
// range); `actionID` fires on every *user* tab switch with the new index as
// context (parity with Apple, which dispatches on interaction only; programmatic
// setInt is silent).
//
// Layout divergence: web places the tab strip at the **top** — the macOS TabView
// convention, matching the macOS-flavored default skin — where Android uses a
// bottom Material NavigationBar and iOS a bottom tab bar. All tab contents are
// built once and toggled with `display`, so each tab keeps its state across
// switches (Apple keeps tab views alive). `style` (page / sidebarAdaptable / …)
// is validated and stashed (data-attribute) but not honored — the strip is
// always used, the Android stance. Tab icons (systemImage / materialName:web)
// draw through the shared SymbolIcon seam; `assetImage` warns-and-skips like
// Image's assetName. See Private/Web_Porting_Notes.md (TabView).

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";
import { tabTitle, tabBadge } from "./Tab.js";

// The full SwiftUI style set; only "automatic" (the strip) is honored on web,
// the rest are accepted-and-stashed (the Android stance).
const VALID_STYLES = ["automatic", "tabBarOnly", "sidebarAdaptable", "page", "verticalPage", "grouped"];

register("TabView", {
    valueType: "int",

    // Mirrors TabView.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.selection !== undefined && !Number.isInteger(validated.selection)) {
            logger.log("TabView selection must be an Integer; defaulting to 0", "warning");
            delete validated.selection;
        }

        if (validated.style !== undefined) {
            if (typeof validated.style !== "string") {
                logger.log("TabView style must be a String; defaulting to 'automatic'", "warning");
                delete validated.style;
            } else if (!VALID_STYLES.includes(validated.style)) {
                logger.log(`TabView style must be one of ["automatic", "tabBarOnly", "sidebarAdaptable", "page", "verticalPage", "grouped"]; defaulting to 'automatic'`, "warning");
                delete validated.style;
            }
        }

        return validated;
    },

    initialValue: (element, properties) => (Number.isInteger(properties.selection) ? properties.selection : 0),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-tabview";
        if (typeof properties.style === "string") node.dataset.auiTabStyle = properties.style;

        const tabs = element.children();
        if (tabs.length === 0) return node; // empty TabView: nothing to show (Android returns early)

        const clamp = (index) => Math.min(Math.max(index, 0), tabs.length - 1);
        const initial = clamp(Number.isInteger(properties.selection) ? properties.selection : 0);
        let selected = initial;

        const bar = document.createElement("div");
        bar.className = "aui-tabbar";
        bar.setAttribute("role", "tablist");

        const contentArea = document.createElement("div");
        contentArea.className = "aui-tabview-content";

        const buttons = [];
        const panels = [];

        // Switches the visible tab and the strip's selected state. No dispatch /
        // model write here — getValue reads `selected` live, so a user click and a
        // programmatic setValue both route through this single place.
        const show = (index) => {
            selected = index;
            buttons.forEach((button, i) => {
                const on = i === index;
                button.classList.toggle("aui-tab-selected", on);
                button.setAttribute("aria-selected", on ? "true" : "false");
                button.tabIndex = on ? 0 : -1;
            });
            panels.forEach((panel, i) => { panel.style.display = i === index ? "" : "none"; });
        };

        tabs.forEach((tab, index) => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "aui-tab";
            button.setAttribute("role", "tab");

            // The tab's SF Symbol / Material glyph through the shared seam
            // (assetImage warns-and-skips); a tab with no icon is title-only.
            const icon = labelIcon(
                selectLabelIcon(tab.properties, "assetImage", "Tab", ctx.logger),
                tab.properties, "Tab", ctx.logger,
            );
            if (icon) {
                icon.classList.add("aui-tab-icon");
                button.appendChild(icon);
            }

            const titleSpan = document.createElement("span");
            titleSpan.className = "aui-tab-title";
            titleSpan.textContent = tabTitle(tab, index);
            button.appendChild(titleSpan);

            const badge = tabBadge(tab);
            if (badge !== null) {
                const badgeSpan = document.createElement("span");
                badgeSpan.className = "aui-tab-badge";
                badgeSpan.textContent = badge;
                button.appendChild(badgeSpan);
            }

            button.addEventListener("click", () => {
                if (index === selected) return;
                show(index);
                if (typeof properties.actionID === "string") {
                    ctx.model.dispatchAction(properties.actionID, element.id, 0, index);
                }
            });
            bar.appendChild(button);
            buttons.push(button);

            // Tab body, built once through the normal pipeline; an absent
            // `content` leaves an empty panel.
            const panel = document.createElement("div");
            panel.className = "aui-tab-panel";
            const contentElement = tab.subviews?.content;
            if (contentElement) panel.appendChild(ctx.build(contentElement));
            contentArea.appendChild(panel);
            panels.push(panel);
        });

        show(selected);

        // TabView dispatches actionID on selection change (with the index as
        // context), not as a whole-view click — opt out of the generic handler.
        markHandlesAction(node);
        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => selected,
                setValue: (value) => { // programmatic: silent (no actionID)
                    show(clamp(Math.trunc(Number(value)) || 0));
                },
            });
        }

        node.append(bar, contentArea);
        return node;
    },
});

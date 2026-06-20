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
// switches (Apple keeps tab views alive). `style` "sidebarAdaptable" is honored
// as a left sidebar rail — the tab items run down the side and the content fills
// the rest (Apple's adaptive sidebar, the expanded form). It is adaptive: a
// ResizeObserver collapses the rail to a bottom tab bar when the TabView gets
// narrow (the `.aui-tabview-compact` class restyles it via the theme), matching
// Apple's sidebar-when-wide / tab-bar-when-narrow (the iPhone idiom). The other
// styles (page / verticalPage / grouped / tabBarOnly) are validated and stashed
// (data-attribute) but not honored — the top strip is used, the Android stance.
// Tab icons (systemImage / materialName:web)
// draw through the shared SymbolIcon seam; `assetImage` warns-and-skips like
// Image's assetName. See Private/Web_Porting_Notes.md (TabView).

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";
import { interpretiveFlatBinding } from "../Helpers/InsertionHelper.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { tabTitle, tabBadge } from "./Tab.js";

// The full SwiftUI style set; only "automatic" (the strip) is honored on web,
// the rest are accepted-and-stashed (the Android stance).
const VALID_STYLES = ["automatic", "tabBarOnly", "sidebarAdaptable", "page", "verticalPage", "grouped"];

register("TabView", {
    valueType: "int",

    // `children` is a runtime-insertable flat container (Apple's
    // TabView.insertableContainers["children"]): a host can add/remove tabs at
    // runtime. A Tab child is interpreted (strip button + content panel), so this
    // is the interpretive insertion path (see InsertionHelper.interpretiveFlatBinding).
    insertableContainers: { children: ContainerShape.FLAT },

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
        // "sidebarAdaptable" lays the tab items out as a left rail instead of a top
        // strip; every other style keeps the strip (see the header note).
        const sidebarLayout = properties.style === "sidebarAdaptable";

        const node = document.createElement("div");
        node.className = sidebarLayout ? "aui-tabview aui-tabview-sidebar" : "aui-tabview";
        if (typeof properties.style === "string") node.dataset.auiTabStyle = properties.style;

        const bar = document.createElement("div");
        bar.className = sidebarLayout ? "aui-tabbar aui-tabbar-sidebar" : "aui-tabbar";
        bar.setAttribute("role", "tablist");
        if (sidebarLayout) bar.setAttribute("aria-orientation", "vertical");

        const contentArea = document.createElement("div");
        contentArea.className = "aui-tabview-content";

        const buttons = [];
        const panels = [];
        let selected = 0;
        const clamp = (index) => (panels.length === 0 ? 0 : Math.min(Math.max(index, 0), panels.length - 1));

        // Cross-fade the incoming tab panel on a switch - selecting a tab is
        // otherwise an instant display swap. lastShownIndex tracks the visible
        // tab so we animate only on a real change (not the initial show or a
        // re-show of the same tab). A gentle fade + small rise, matching the
        // NavigationSplitView detail cross-fade. Guarded for the headless test
        // DOM (no element.animate) and for reduced-motion.
        let lastShownIndex = null;
        const reduceMotion = () =>
            typeof window !== "undefined" && typeof window.matchMedia === "function" &&
            window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        const animatePanelIn = (panel) => {
            if (typeof panel.animate !== "function" || reduceMotion()) return;
            panel.animate(
                [{ opacity: 0, transform: "translateY(8px)" },
                 { opacity: 1, transform: "translateY(0)" }],
                { duration: 200, easing: "ease-out" },
            );
        };

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
            if (lastShownIndex !== null && lastShownIndex !== index && panels[index]) {
                animatePanelIn(panels[index]);
            }
            lastShownIndex = index;
        };

        // Builds a tab's strip button + content panel and inserts both at `atIndex`.
        // Reused by the initial build and by runtime insertElement. The click
        // handler resolves its index dynamically, so it stays correct after
        // insertions/removals shift positions.
        const makeTab = (tab, atIndex) => {
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
            titleSpan.textContent = tabTitle(tab, atIndex);
            button.appendChild(titleSpan);

            const badge = tabBadge(tab);
            if (badge !== null) {
                const badgeSpan = document.createElement("span");
                badgeSpan.className = "aui-tab-badge";
                badgeSpan.textContent = badge;
                button.appendChild(badgeSpan);
            }

            button.addEventListener("click", () => {
                const index = buttons.indexOf(button);
                if (index < 0 || index === selected) return;
                show(index);
                if (typeof properties.actionID === "string") {
                    ctx.model.dispatchAction(properties.actionID, element.id, 0, index);
                }
            });

            // Tab body, built once through the normal pipeline; an absent
            // `content` leaves an empty panel. The panel carries the Tab's id so
            // removeElement can find and tear it down.
            const panel = document.createElement("div");
            panel.className = "aui-tab-panel";
            if (tab.id > 0) panel.dataset.auiId = String(tab.id);
            const contentElement = tab.subviews?.content;
            if (contentElement) panel.appendChild(ctx.build(contentElement));

            bar.insertBefore(button, bar.children[atIndex] ?? null);
            contentArea.insertBefore(panel, contentArea.children[atIndex] ?? null);
            buttons.splice(atIndex, 0, button);
            panels.splice(atIndex, 0, panel);
        };

        const tabs = element.children();
        tabs.forEach((tab, index) => makeTab(tab, index));

        selected = clamp(Number.isInteger(properties.selection) ? properties.selection : 0);
        if (panels.length > 0) show(selected);

        // TabView dispatches actionID on selection change (with the index as
        // context), not as a whole-view click — opt out of the generic handler.
        markHandlesAction(node);
        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => selected,
                setValue: (value) => { // programmatic: silent (no actionID)
                    if (panels.length) show(clamp(Math.trunc(Number(value)) || 0));
                },
            });

            // `children` insertion: a Tab child becomes a strip button + panel.
            // Inserting at/under the current selection shifts it so the same tab
            // stays visible; removing adjusts likewise.
            ctx.model.bindContainer(element.id, "children", interpretiveFlatBinding(
                (tabEl, _id, index) => {
                    const wasEmpty = panels.length === 0;
                    makeTab(tabEl, index);
                    if (wasEmpty) show(0);
                    else { if (index <= selected) selected += 1; show(selected); }
                },
                (id) => {
                    const i = panels.findIndex((p) => Number(p.dataset.auiId) === id);
                    if (i < 0) return;
                    buttons[i].remove();
                    panels[i].remove();
                    buttons.splice(i, 1);
                    panels.splice(i, 1);
                    if (panels.length === 0) selected = 0;
                    else { if (i < selected) selected -= 1; show(clamp(selected)); }
                },
                tabs.map((tab) => tab.id),
            ));
        }

        node.append(bar, contentArea);

        // sidebarAdaptable is adaptive: the left rail collapses back to a top strip
        // when the TabView gets too narrow (Apple's sidebar-when-wide, tab-bar-when-
        // narrow). A ResizeObserver toggles `.aui-tabview-compact` (the CSS reverts
        // the rail overrides); guarded so the headless test DOM stays expanded. Only
        // the rail layout has a narrow form - the top strip is already compact.
        if (sidebarLayout && typeof ResizeObserver !== "undefined") {
            const COMPACT_WIDTH = 440;
            const observer = new ResizeObserver((entries) => {
                const width = entries[0]?.contentRect?.width;
                if (typeof width === "number") node.classList.toggle("aui-tabview-compact", width < COMPACT_WIDTH);
            });
            observer.observe(node);
            node._auiDestroy = () => observer.disconnect();
        }

        return node;
    },
});

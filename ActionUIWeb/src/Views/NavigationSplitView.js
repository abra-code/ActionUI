// NavigationSplitView.js — NavigationSplitView element.
// Web analog of ActionUI/Views/NavigationSplitView.swift (and ActionUIAndroid
// Views/NavigationSplitView.kt).
//
// A multi-column layout: a sidebar pane, an optional middle content pane, and a
// detail pane. Two forms, matching Apple/Android:
//
//   1. Static panes — no `destinations`. The declared `sidebar`, optional
//      `content`, and `detail` render side by side (two- or three-pane), each
//      built through the registry like any child.
//   2. Selection-driven — a `destinations` array plus a `sidebar` List whose
//      children carry a `destinationViewId`. Selecting a sidebar row shows the
//      matching destination in the detail pane. No NavigationLink needed.
//
// Sidebar rows (selection-driven). The sidebar List element is **not** itself
// built through the registry — that would create a nested, separately-selecting
// List. Instead, like Swift's buildSidebarList / Android's SidebarPane, this
// element builds one row per sidebar child directly (each via ctx.build), so an
// Apple-canonical Label row shows its `systemImage` leading icon for free. A row
// links to a destination by its child `destinationViewId` property.
//
// Detail switching. The default `detail` and every `destinations` entry are built
// once up front and toggled with `display` (like TabView panels), so destination
// ids are host-addressable immediately and each pane keeps its state across
// switches. The shown node is `destinations[selectedDestination]`, else the
// default detail.
//
// State (no value bridge; valueType "none"). Selection lives in element state, not
// the scalar value:
//   states["selectedDestination"]  Int   selected destination id (0 = none).
//   states["columnVisibility"]     String "automatic"|"all"|"doubleColumn"|"detail".
// Both are seeded by initialStates, host-addressable via get/setState, and bound
// when the element has an id. On a user selection the **sidebar List's** actionID
// fires (viewID = sidebar.id, no context) — matching Swift and the web's existing
// no-context selection convention; the host then reads selectedDestination.
// (Android instead fires the NSV's own actionID with context = destId — divergence
// documented in Private/Web_Porting_Notes.md.)
//
// Browser back/forward (opt-in, web-only): `browserHistory:web: true` makes a user
// sidebar selection a browser-history entry, so Back returns to the previously
// selected destination; a popstate restores selectedDestination (not the actionID).
// Off by default. Helpers/NavigationHistory.js owns the single global history and
// the user-vs-programmatic rule (programmatic setState syncs, never pushes).
//
// Best-effort vs. Apple. `columnVisibility` drives a container attribute the CSS
// reads ("detail" collapses to the detail pane; other values show all columns) and
// `style` ("balanced"/"prominentDetail"/"automatic") a data-attribute the skin
// reads.
//
// Adaptive width-class collapse (the iPad-expand / iPhone-collapse). A
// ResizeObserver watches the split's own width and toggles a compact mode below
// COMPACT_WIDTH (data-compact / data-compact-pane, read by the CSS). A
// selection-driven split then shows one column at a time - the sidebar until a row
// is picked, then the detail with a "‹ Back" affordance that deselects — while a
// static split stacks its panes vertically. Guarded so the headless test DOM (no
// ResizeObserver) stays in the expanded form.

import { register } from "../Common/ActionUIRegistry.js";
import { registerNavigationHistory } from "../Helpers/NavigationHistory.js";
import { navigateRowsOnKey } from "../Helpers/RowKeyboardNav.js";

const VALID_COLUMN_VISIBILITIES = ["automatic", "all", "doubleColumn", "detail"];
const VALID_STYLES = ["automatic", "balanced", "prominentDetail"];

// navigationSplitViewColumnWidth (View.md): a Number -> a fixed column, or
// { ideal, min, max } -> a preferred width bounded by min/max (ideal required).
// Declared on the sidebar/content/detail subview; applied to that pane here (the
// modifier is a no-op outside an NSV column, matching the schema). Mirrors the
// SwiftUI .navigationSplitViewColumnWidth modifier; the pane becomes rigid
// (flex:0 0 auto) so its width is governed by the declared values.
function applyColumnWidth(paneNode, element, logger) {
    const cw = element?.properties?.navigationSplitViewColumnWidth;
    if (cw === undefined) return;
    if (typeof cw === "number") {
        paneNode.style.flex = "0 0 auto";
        paneNode.style.width = `${cw}px`;
        paneNode.style.minWidth = `${cw}px`;
        paneNode.style.maxWidth = `${cw}px`;
        return;
    }
    if (typeof cw === "object" && cw !== null && typeof cw.ideal === "number") {
        paneNode.style.flex = "0 0 auto";
        paneNode.style.width = `${cw.ideal}px`;
        if (typeof cw.min === "number") paneNode.style.minWidth = `${cw.min}px`;
        if (typeof cw.max === "number") paneNode.style.maxWidth = `${cw.max}px`;
        return;
    }
    logger.log("navigationSplitViewColumnWidth requires a Number or a dictionary with a numeric 'ideal'; ignoring", "warning");
}

register("NavigationSplitView", {
    // Selection is element state, not the scalar value (Swift valueType Void).
    valueType: "none",

    // Mirrors NavigationSplitView.swift validateProperties (warnings verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (typeof validated.columnVisibility === "string" && !VALID_COLUMN_VISIBILITIES.includes(validated.columnVisibility)) {
            logger.log(`Invalid NavigationSplitView columnVisibility: ${validated.columnVisibility}; defaulting to 'all'`, "warning");
            validated.columnVisibility = "all";
        }
        if (typeof validated.style === "string" && !VALID_STYLES.includes(validated.style)) {
            logger.log(`Invalid NavigationSplitView style: ${validated.style}; defaulting to 'automatic'`, "warning");
            validated.style = "automatic";
        }
        // Web-only opt-in (authored `browserHistory:web`): no Swift/Kotlin
        // counterpart, validated here rather than mirrored.
        if (validated.browserHistory !== undefined && typeof validated.browserHistory !== "boolean") {
            logger.log("NavigationSplitView browserHistory (web) must be a Boolean; ignoring", "warning");
            delete validated.browserHistory;
        }

        return validated;
    },

    // selectedDestination 0 = none; columnVisibility from the author or "all"
    // (mirrors NavigationSplitView.kt initialStates).
    initialStates: (element, properties) => ({
        selectedDestination: 0,
        columnVisibility: typeof properties.columnVisibility === "string" ? properties.columnVisibility : "all",
    }),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-nav-split";
        node.dataset.auiSplitStyle = typeof properties.style === "string" ? properties.style : "automatic";

        const sidebar = element.sidebar();
        if (!sidebar) {
            ctx.logger.log("NavigationSplitView requires a 'sidebar'; nothing rendered", "warning");
            return node;
        }
        const content = element.content();   // optional middle pane → three-pane
        const detail = element.detail();
        const destinations = element.destinations();
        const threePane = content !== null;

        let columnVisibility = typeof properties.columnVisibility === "string" ? properties.columnVisibility : "all";
        const applyColumnVisibility = () => { node.dataset.columnVisibility = columnVisibility; };
        applyColumnVisibility();

        // Selection-driven when there are destinations AND the sidebar has children;
        // otherwise the panes render statically (Android's SidebarPane fallback).
        const sidebarChildren = sidebar.children();
        const selectionDriven = destinations.length > 0 && sidebarChildren.length > 0;

        const sidebarPane = document.createElement("div");
        sidebarPane.className = "aui-nav-split-sidebar";
        applyColumnWidth(sidebarPane, sidebar, ctx.logger);
        const detailPane = document.createElement("div");
        detailPane.className = "aui-nav-split-detail";
        applyColumnWidth(detailPane, detail, ctx.logger);

        // Selection state (only meaningful in the selection-driven form).
        let selectedDestination = 0;
        const rowsByDest = new Map();        // destId → row node (for highlight)
        const destinationsById = new Map();  // destId → built detail node
        const destinationNodes = [];
        let defaultDetailNode = null;

        // Opt-in browser back/forward (authored `browserHistory:web`, off by
        // default): a user selection adds a history entry, a popstate restores the
        // selection. See Helpers/NavigationHistory.js.
        const historyEnabled = properties.browserHistory === true;
        let historyHandle = null; // set after the state binding, when enabled
        const commitHistory = (mode) => { if (historyHandle) historyHandle.commit(mode); };

        // Adaptive width-class collapse (the deferred responsive part of Apple's
        // NavigationSplitView: expanded columns when wide, a single navigable column
        // when narrow). A ResizeObserver (wired below, guarded) toggles `compact`
        // when the split's own width drops below COMPACT_WIDTH; the CSS reads
        // data-compact / data-compact-pane. Selection-driven splits show one column
        // at a time (the sidebar until a row is picked, then the detail with a Back
        // affordance); static splits stack vertically. The data-driven `display`
        // toggling of destination nodes is untouched - compact only governs which
        // *pane* shows.
        const COMPACT_WIDTH = 640;
        let compact = false;
        // Pane-transition animation. In compact, switching the visible pane
        // (sidebar <-> detail) is otherwise an instant display swap; a short
        // slide + fade on the incoming pane gives navigation the push/pop feel
        // users expect from a native app. lastShownPane tracks the current pane
        // so we animate only on a real switch - not the first compaction or a
        // resize - and pick direction: forward (sidebar -> detail) enters from
        // the right, back (detail -> sidebar) from the left. Guarded for the
        // headless test DOM (no element.animate) and for reduced-motion;
        // .aui-nav-split overflow:hidden clips the slide so it adds no scrollbar.
        let lastShownPane = null;
        const reduceMotion = () =>
            typeof window !== "undefined" && typeof window.matchMedia === "function" &&
            window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        const animatePaneIn = (pane, fromRight) => {
            if (typeof pane.animate !== "function" || reduceMotion()) return;
            pane.animate(
                [{ transform: `translateX(${fromRight ? 24 : -24}px)`, opacity: 0 },
                 { transform: "translateX(0)", opacity: 1 }],
                { duration: 220, easing: "ease-out" },
            );
        };
        // In compact the sidebar fills the column (its declared rail width / the
        // applyColumnWidth inline styles would otherwise pin it narrow); restore
        // re-applies the declared width when expanding.
        const fillSidebarWidth = () => {
            sidebarPane.style.flex = "1 1 auto";
            sidebarPane.style.width = "auto";
            sidebarPane.style.minWidth = "0";
            sidebarPane.style.maxWidth = "none";
        };
        const restoreSidebarWidth = () => {
            sidebarPane.style.flex = "";
            sidebarPane.style.width = "";
            sidebarPane.style.minWidth = "";
            sidebarPane.style.maxWidth = "";
            applyColumnWidth(sidebarPane, sidebar, ctx.logger); // re-apply the declared rail width, if any
        };
        // Reflects compact + the current selection into the data-attributes the CSS
        // reads. Idempotent, so it is safe to call from applySelection and resize.
        const applyPaneVisibility = () => {
            if (!compact) {
                delete node.dataset.compact;
                delete node.dataset.compactPane;
                lastShownPane = null; // re-entering compact should not animate the first show
                return;
            }
            node.dataset.compact = "true";
            if (selectionDriven) {
                const pane = selectedDestination !== 0 ? "detail" : "sidebar";
                node.dataset.compactPane = pane;
                if (lastShownPane !== null && lastShownPane !== pane) {
                    animatePaneIn(pane === "detail" ? detailPane : sidebarPane, pane === "detail");
                }
                lastShownPane = pane;
            } else {
                delete node.dataset.compactPane; // static: the CSS stacks the panes vertically
                lastShownPane = null;
            }
        };
        const setCompact = (next) => {
            if (next === compact) return;
            compact = next;
            if (compact) fillSidebarWidth(); else restoreSidebarWidth();
            applyPaneVisibility();
        };

        const showDetail = () => {
            if (!selectionDriven) return;
            const target = destinationsById.get(selectedDestination) ?? null;
            defaultDetailNode.style.display = target ? "none" : "";
            destinationNodes.forEach((n) => { n.style.display = (n === target) ? "" : "none"; });
        };
        const applySelection = () => {
            rowsByDest.forEach((row, destId) => {
                const on = destId === selectedDestination && selectedDestination !== 0;
                row.classList.toggle("aui-nav-split-row-selected", on);
                row.setAttribute("aria-selected", on ? "true" : "false");
            });
            showDetail();
            applyPaneVisibility(); // a selection flips the visible pane when compact
        };
        // Reconcile the selection from a history entry: no commit (it came from
        // history) and no actionID (a restore, like setState - not a user click).
        const restoreSelection = (destId) => {
            selectedDestination = Number.isInteger(destId) ? destId : 0;
            applySelection();
        };

        if (selectionDriven) {
            if (sidebar.type !== "List") {
                ctx.logger.log(`NavigationSplitView with destinations requires sidebar to be a List for selection support; got '${sidebar.type}'`, "warning");
            }
            const sidebarActionID = sidebar.properties?.actionID;
            const sidebarID = sidebar.id;

            const selectDestination = (destId, fromUser) => {
                if (destId === selectedDestination) return;
                selectedDestination = destId;
                applySelection();
                // Fire the sidebar List's actionID (viewID = sidebar.id), no context;
                // the host reads getState(nsvID, "selectedDestination"). Matches Swift
                // and the web's no-context selection convention.
                if (fromUser && typeof sidebarActionID === "string") {
                    ctx.model.dispatchAction(sidebarActionID, sidebarID, 0, null);
                }
                if (fromUser) commitHistory("push"); // user selection = forward nav
            };

            // Compact-mode Back: returns to the sidebar (deselects). Fires the
            // sidebar actionID (so the host sees selectedDestination = 0, the
            // selection convention) but syncs history rather than pushing - a back
            // gesture, not forward nav. Shown only in compact+detail (CSS).
            const goBackToSidebar = () => {
                if (selectedDestination === 0) return;
                selectedDestination = 0;
                applySelection();
                if (typeof sidebarActionID === "string") ctx.model.dispatchAction(sidebarActionID, sidebarID, 0, null);
                commitHistory("replace");
            };
            const backButton = document.createElement("button");
            backButton.type = "button";
            backButton.className = "aui-nav-split-back";
            backButton.textContent = "‹ Back";
            backButton.addEventListener("click", goBackToSidebar);
            detailPane.appendChild(backButton); // first child, above the detail content

            // Detail host: the default detail plus one node per destination, built
            // once and toggled by display.
            defaultDetailNode = detail ? ctx.build(detail) : document.createElement("div");
            detailPane.appendChild(defaultDetailNode);
            for (const dest of destinations) {
                if (dest.id <= 0) continue; // detail targets are addressed by id
                const destNode = ctx.build(dest);
                destinationsById.set(dest.id, destNode);
                destinationNodes.push(destNode);
                detailPane.appendChild(destNode);
            }

            // Sidebar rows built from the List's children (the List itself is not built).
            // selectableRows keeps the destination-bearing rows in order so the arrow
            // keys can move selection to the adjacent one (skipping any non-selectable
            // header rows).
            sidebarPane.setAttribute("role", "listbox");
            const selectableRows = []; // [{ row, destId }] in sidebar order
            for (const child of sidebarChildren) {
                const row = document.createElement("div");
                row.className = "aui-nav-split-row";
                row.appendChild(ctx.build(child));
                const destId = Number.isInteger(child.properties?.destinationViewId) ? child.properties.destinationViewId : null;
                if (destId !== null) {
                    const rowIndex = selectableRows.length;
                    selectableRows.push({ row, destId });
                    row.dataset.auiDestId = String(destId);
                    rowsByDest.set(destId, row);
                    row.setAttribute("role", "option");
                    row.setAttribute("aria-selected", "false");
                    row.tabIndex = 0;
                    row.addEventListener("click", () => selectDestination(destId, true));
                    row.addEventListener("keydown", (event) => {
                        if (event.key === "Enter" || event.key === " ") {
                            event.preventDefault();
                            selectDestination(destId, true);
                            return;
                        }
                        // Arrow / Home / End move selection+focus to the adjacent
                        // sidebar row - else the key scrolls the sidebar pane.
                        navigateRowsOnKey(event, rowIndex, selectableRows.length, (target) => {
                            selectDestination(selectableRows[target].destId, true);
                            selectableRows[target].row.focus();
                        });
                    });
                }
                sidebarPane.appendChild(row);
            }

            if (threePane) {
                const contentPane = document.createElement("div");
                contentPane.className = "aui-nav-split-content";
                applyColumnWidth(contentPane, content, ctx.logger);
                contentPane.appendChild(ctx.build(content));
                node.append(sidebarPane, contentPane, detailPane);
            } else {
                node.append(sidebarPane, detailPane);
            }
        } else {
            // Static form: build each declared pane through the registry.
            sidebarPane.appendChild(ctx.build(sidebar));
            if (detail) detailPane.appendChild(ctx.build(detail));
            if (threePane) {
                const contentPane = document.createElement("div");
                contentPane.className = "aui-nav-split-content";
                applyColumnWidth(contentPane, content, ctx.logger);
                contentPane.appendChild(ctx.build(content));
                node.append(sidebarPane, contentPane, detailPane);
            } else {
                node.append(sidebarPane, detailPane);
            }
        }

        // State binding (both forms): selectedDestination + columnVisibility,
        // host-addressable. No value binding (valueType "none").
        if (element.id > 0) {
            ctx.model.bindState(element.id, {
                getState: (key) => {
                    if (key === "selectedDestination") return selectedDestination;
                    if (key === "columnVisibility") return columnVisibility;
                    return undefined;
                },
                setState: (key, value) => {
                    if (key === "selectedDestination") {
                        selectedDestination = Number.isInteger(value) ? value : 0;
                        applySelection();
                        commitHistory("replace"); // programmatic sync of the current entry
                    } else if (key === "columnVisibility") {
                        columnVisibility = typeof value === "string" ? value : "all";
                        applyColumnVisibility();
                    }
                },
            });

            // Opt-in browser history: capture/restore selectedDestination only
            // (columnVisibility is presentation, not navigation). Registering
            // folds the current selection into the active entry; restore
            // reconciles without writing history back or firing an actionID.
            if (historyEnabled) {
                historyHandle = registerNavigationHistory(element.id, {
                    capture: () => selectedDestination,
                    restore: (saved) => restoreSelection(saved),
                });
                node._auiDestroy = () => historyHandle.release();
            }
        }

        // Adaptive collapse: watch the split's own width and toggle compact when it
        // crosses COMPACT_WIDTH. Guarded so the headless test DOM (which lacks
        // ResizeObserver) stays expanded; composed with any existing teardown
        // (history release). contentRect.width is the content-box width.
        if (typeof ResizeObserver !== "undefined") {
            const observer = new ResizeObserver((entries) => {
                const width = entries[0]?.contentRect?.width;
                if (typeof width === "number") setCompact(width < COMPACT_WIDTH);
            });
            observer.observe(node);
            const prevDestroy = node._auiDestroy;
            node._auiDestroy = () => { observer.disconnect(); if (prevDestroy) prevDestroy(); };
        }

        applySelection();
        return node;
    },
});

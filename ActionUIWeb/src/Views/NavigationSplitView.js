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
// reads. The adaptive width-class collapse (iPad-expand / iPhone-collapse) is the
// deferred responsive part — element/structure parity ships now.

import { register } from "../Common/ActionUIRegistry.js";
import { registerNavigationHistory } from "../Helpers/NavigationHistory.js";

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
            sidebarPane.setAttribute("role", "listbox");
            for (const child of sidebarChildren) {
                const row = document.createElement("div");
                row.className = "aui-nav-split-row";
                row.appendChild(ctx.build(child));
                const destId = Number.isInteger(child.properties?.destinationViewId) ? child.properties.destinationViewId : null;
                if (destId !== null) {
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
                        }
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

        applySelection();
        return node;
    },
});

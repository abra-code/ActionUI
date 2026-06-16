// NavigationStack.js — NavigationStack element.
// Web analog of ActionUI/Views/NavigationStack.swift (and ActionUIAndroid
// Views/NavigationStack.kt).
//
// Push navigation: a root `content` view plus an addressable set of push
// targets. SwiftUI wraps SwiftUI.NavigationStack; Android backs it with a
// Jetpack NavHost. The web has no native nav primitive, so — like TabView and
// NavigationSplitView's detail switching — the root and every destination are
// built **once** and toggled with `display`, keyed by the current path. That
// keeps every pane's state across pushes/pops and makes destination ids
// host-addressable up front.
//
// Named containers:
//   * `content` — the root view shown at the bottom of the stack (required).
//   * `destinations` — the array of push targets, each addressed by its `id`.
// Inline NavigationLink destinations (Form 1) are **hoisted** into the same
// id-keyed registry by scanning the content subtree (buildDestinationMap),
// mirroring Android's NavHost (which also has no inline-destination concept).
//
// Two Apple forms, one renderer:
//   * NavigationLink-based — links inside `content` push a target (by
//     `destinationViewId` → `destinations[]`, or an inline `destination`).
//   * Selectable List — `content` is a List with an `actionID` whose children
//     carry `destinationViewId`; selecting a row fires the List's actionID and
//     pushes. Mirrors NavigationSplitView's sidebar: the rows are built here
//     directly (not the List through the registry, which would nest a List).
//
// Push signaling is a bubbling `aui-nav-push` CustomEvent (NavigationLink.js).
// This element listens on its node and stops propagation, so the event scopes
// to the nearest enclosing NavigationStack (nested stacks each catch their own).
//
// State (`navigationPath`, valueType "none"): a [Int] of the destination ids on
// the stack, root-to-top (empty at root). Seeded empty; the binding's getState
// returns the live path (so a host read always reflects the UI), and a host
// setState reconciles the panes (programmatic push/pop). `navigationTitle` and
// `toolbar` on the content/destination render as chrome (ToolbarHelper) since
// each is built through the registry; the stack adds only a `‹ Back` affordance
// above a destination (the selectable-List root, whose rows are built directly,
// still gets a navTitleHeader here).

import { register } from "../Common/ActionUIRegistry.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { NAV_PUSH_EVENT } from "./NavigationLink.js";

const NAV_PATH_KEY = "navigationPath";

register("NavigationStack", {
    valueType: "none",

    // `destinations` is a runtime-insertable flat container (Apple's
    // NavigationStack.insertableContainers["destinations"]): a host can add push
    // targets at runtime. Each inserted destination is built into a hidden pane,
    // addressable by id like the authored ones.
    insertableContainers: { destinations: ContainerShape.FLAT },

    validateProperties: (properties) => ({ ...properties }),

    initialStates: () => ({ [NAV_PATH_KEY]: [] }),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-nav-stack";

        const content = element.content();
        if (!content) {
            ctx.logger.log("NavigationStack requires a 'content'; nothing rendered", "warning");
            return node;
        }
        const destinations = element.destinations();

        // Destination registry: destinations[] (authoritative) + inline link
        // destinations hoisted from the content subtree, keyed by id.
        const destMap = buildDestinationMap(content, destinations);

        let path = []; // dest ids, root-to-top; empty = root

        // --- root pane ---
        const rootPane = document.createElement("div");
        rootPane.className = "aui-nav-stack-pane";
        const rowsByDest = new Map(); // selectable-List form: destId → row node

        const push = (id) => {
            if (!destMap.has(id)) {
                ctx.logger.log(`NavigationLink target id ${id} is not in this stack's destinations`, "warning");
                return;
            }
            path = [...path, id];
            showTop();
        };
        const pop = () => {
            if (path.length === 0) return;
            path = path.slice(0, -1);
            showTop();
        };
        const setPath = (newPath) => {
            path = Array.isArray(newPath) ? newPath.filter((id) => destMap.has(id)) : [];
            showTop();
        };

        const selectableChildren = selectableListChildren(content);
        if (selectableChildren) {
            const listActionID = content.properties?.actionID;
            const listID = content.id;
            const header = navTitleHeader(content);
            if (header) rootPane.appendChild(header);
            const listBox = document.createElement("div");
            listBox.className = "aui-list";
            listBox.setAttribute("role", "listbox");
            for (const child of selectableChildren) {
                const row = document.createElement("div");
                row.className = "aui-list-row";
                row.appendChild(ctx.build(child));
                const destId = Number.isInteger(child.properties?.destinationViewId) ? child.properties.destinationViewId : null;
                if (destId !== null) {
                    rowsByDest.set(destId, row);
                    row.setAttribute("role", "option");
                    row.setAttribute("aria-selected", "false");
                    row.tabIndex = 0;
                    const activate = () => {
                        // Fire the List's actionID (viewID = list id, the selected
                        // child id as context), then push — Apple's order.
                        if (typeof listActionID === "string") {
                            ctx.model.dispatchAction(listActionID, listID, 0, [String(child.id)]);
                        }
                        push(destId);
                    };
                    row.addEventListener("click", activate);
                    row.addEventListener("keydown", (event) => {
                        if (event.key === "Enter" || event.key === " ") {
                            event.preventDefault();
                            activate();
                        }
                    });
                }
                listBox.appendChild(row);
            }
            rootPane.appendChild(listBox);
        } else {
            // Normal form: the content is built through the registry, so its own
            // `navigationTitle`/`toolbar` renders as chrome (ToolbarHelper) — the
            // stack adds no title of its own here.
            const body = document.createElement("div");
            body.className = "aui-nav-stack-body";
            body.appendChild(ctx.build(content));
            rootPane.appendChild(body);
        }
        node.appendChild(rootPane);

        // --- destination panes (built once, toggled by display) ---
        const destPanes = new Map();
        const destOrder = []; // dest ids in container order (for insertion positioning)

        // Wraps a built destination body in a hidden pane with a back affordance;
        // the destination's own navigationTitle/toolbar renders as chrome below it
        // (ToolbarHelper), the iOS back-chevron-over-title pattern. Reused by the
        // initial build and by runtime insertElement.
        const makeDestPane = (bodyContentNode) => {
            const pane = document.createElement("div");
            pane.className = "aui-nav-stack-pane";
            pane.style.display = "none";
            const bar = document.createElement("div");
            bar.className = "aui-nav-stack-bar";
            const back = document.createElement("button");
            back.type = "button";
            back.className = "aui-nav-stack-back";
            back.textContent = "‹ Back";
            back.addEventListener("click", () => pop());
            bar.appendChild(back);
            pane.appendChild(bar);
            const body = document.createElement("div");
            body.className = "aui-nav-stack-body";
            body.appendChild(bodyContentNode);
            pane.appendChild(body);
            return pane;
        };

        for (const [id, destEl] of destMap) {
            const pane = makeDestPane(ctx.build(destEl));
            destPanes.set(id, pane);
            destOrder.push(id);
            node.appendChild(pane);
        }

        const showTop = () => {
            const top = path.length ? path[path.length - 1] : null;
            rootPane.style.display = top === null ? "" : "none";
            destPanes.forEach((pane, id) => { pane.style.display = id === top ? "" : "none"; });
            // Selectable-List form: highlight the pushed row, cleared at root.
            rowsByDest.forEach((row, destId) => {
                const on = path.includes(destId);
                row.classList.toggle("aui-list-row-selected", on);
                row.setAttribute("aria-selected", on ? "true" : "false");
            });
        };

        // Push events bubble up from NavigationLinks (and selectable rows reach
        // push() directly). Stop here so an outer stack does not also navigate.
        node.addEventListener(NAV_PUSH_EVENT, (event) => {
            event.stopPropagation();
            push(event.detail);
        });

        // State binding: getState returns the live path; a host setState
        // reconciles the panes (programmatic push/pop). valueType "none".
        if (element.id > 0) {
            ctx.model.bindState(element.id, {
                getState: (key) => (key === NAV_PATH_KEY ? [...path] : undefined),
                setState: (key, value) => { if (key === NAV_PATH_KEY) setPath(value); },
            });

            // `destinations` insertion: the model builds the destination content
            // (the 4th arg `destEl` is its parsed element, registered into destMap
            // so push() accepts it); we wrap it in a hidden pane like the authored
            // ones. The built content carries data-aui-id, so removeElement finds it
            // and remove() tears down the whole pane (dropping it from the path if on it).
            ctx.model.bindContainer(element.id, "destinations", {
                shape: ContainerShape.FLAT,
                childIds: () => [...destOrder],
                insert: (contentNode, id, index, destEl) => {
                    const pane = makeDestPane(contentNode);
                    destMap.set(id, destEl);
                    destPanes.set(id, pane);
                    destOrder.splice(index, 0, id);
                    node.appendChild(pane); // hidden; order among panes is display-toggled, not visual
                },
                remove: (id) => {
                    const i = destOrder.indexOf(id);
                    if (i < 0) return false;
                    destPanes.get(id)?.remove();
                    destPanes.delete(id);
                    destMap.delete(id);
                    destOrder.splice(i, 1);
                    if (path.includes(id)) { path = path.filter((p) => p !== id); showTop(); }
                    return true;
                },
            });
        }

        showTop();
        return node;
    },
});

// The id-keyed push-target registry: every destinations[] entry (authoritative,
// wins on a shared id) plus every inline `destination` hoisted from the content
// subtree (Apple's inline-link form). Entries without a positive id are skipped
// — the web addresses panes by id, like Android's NavHost routes.
function buildDestinationMap(content, destinations) {
    const map = new Map();
    collectInlineDestinations(content, map);
    for (const dest of destinations) {
        if (Number.isInteger(dest.id) && dest.id > 0) map.set(dest.id, dest);
    }
    return map;
}

function collectInlineDestinations(element, into) {
    const dest = element.destination?.() ?? null;
    if (dest) {
        if (dest.id > 0 && !into.has(dest.id)) into.set(dest.id, dest);
        collectInlineDestinations(dest, into);
    }
    for (const child of element.children?.() ?? []) collectInlineDestinations(child, into);
    const inner = element.content?.() ?? null;
    if (inner) collectInlineDestinations(inner, into);
}

// The selectable-List form's children, or null: content is a List with an
// actionID whose children carry at least one destinationViewId (mirrors
// NavigationStack.swift's isSelectableListPattern).
function selectableListChildren(content) {
    if (content.type !== "List") return null;
    if (typeof content.properties?.actionID !== "string") return null;
    const children = content.children();
    if (children.length === 0) return null;
    const hasDestination = children.some((c) => Number.isInteger(c.properties?.destinationViewId));
    return hasDestination ? children : null;
}

function navTitleOf(element) {
    const title = element.properties?.navigationTitle;
    return typeof title === "string" ? title : null;
}

// A simple title header for the root pane (no back button). Destination panes
// get their title inline in the back bar.
function navTitleHeader(element) {
    const title = navTitleOf(element);
    if (!title) return null;
    const bar = document.createElement("div");
    bar.className = "aui-nav-stack-bar";
    const t = document.createElement("span");
    t.className = "aui-nav-stack-title";
    t.textContent = title;
    bar.appendChild(t);
    return bar;
}

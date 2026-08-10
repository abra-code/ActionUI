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
//
// Browser back/forward (opt-in, web-only): `browserHistory:web: true` makes a
// user push add a browser-history entry, routes the in-app Back through
// history.back(), and restores the path on popstate (Helpers/NavigationHistory.js
// owns the single global history). Off by default - Back keeps its page behavior
// unless the author opts in. Programmatic setState syncs the current entry rather
// than adding a Back target (see the helper's header for the rule).

import { register } from "../Common/ActionUIRegistry.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { NAV_PUSH_EVENT } from "./NavigationLink.js";
import { registerNavigationHistory } from "../Helpers/NavigationHistory.js";
import { prefersReducedMotion } from "../Helpers/Modality.js";
import { attachEdgeBackSwipe } from "../Helpers/EdgeSwipe.js";
import {
    persistentToolbarItems,
    buildPersistentToolbar,
    attachPersistentToolbarMounts,
    movePersistentToolbar,
} from "../Helpers/ToolbarHelper.js";

const NAV_PATH_KEY = "navigationPath";

register("NavigationStack", {
    valueType: "none",

    // `destinations` is a runtime-insertable flat container (Apple's
    // NavigationStack.insertableContainers["destinations"]): a host can add push
    // targets at runtime. Each inserted destination is built into a hidden pane,
    // addressable by id like the authored ones.
    insertableContainers: { destinations: ContainerShape.FLAT },

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        // Web-only opt-in (authored `browserHistory:web`): no Swift/Kotlin
        // counterpart, so this is validated here rather than mirrored.
        if (validated.browserHistory !== undefined && typeof validated.browserHistory !== "boolean") {
            logger.log("NavigationStack browserHistory (web) must be a Boolean; ignoring", "warning");
            delete validated.browserHistory;
        }
        return validated;
    },

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

        // This stack's persistent items: built ONCE here, then moved into whichever pane
        // is visible (see showTop). Every pane gets a mount point per occupied slot, even
        // one that declares no toolbar of its own - that pane still shows the container's
        // items, which is the whole point of the key.
        const persistentGroups = buildPersistentToolbar(persistentToolbarItems(element), ctx);
        const persistentSlots = persistentGroups === null ? [] : Object.keys(persistentGroups);
        const destMounts = new Map(); // dest id -> { slot: mountNode }
        let rootMounts = {};

        let path = []; // dest ids, root-to-top; empty = root

        // Opt-in browser back/forward (authored `browserHistory:web`, off by
        // default). When on: a user push adds a history entry, the in-app Back
        // routes through history.back() (so in-app and browser Back agree), and a
        // popstate restores the path. See Helpers/NavigationHistory.js.
        const historyEnabled = properties.browserHistory === true;
        let historyHandle = null; // set after the state binding, when enabled
        const commitHistory = (mode) => { if (historyHandle) historyHandle.commit(mode); };

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
            commitHistory("push"); // user-initiated forward navigation
        };
        // Reached only from the in-app Back button when history is OFF (when ON
        // the button calls history.back() and popstate drives the pop).
        const pop = () => {
            if (path.length === 0) return;
            path = path.slice(0, -1);
            showTop();
        };
        // Programmatic / reconciling path set. `fromHistory` true = a popstate
        // restore (do not write history back); otherwise a host setState, which
        // syncs the current entry (replace), never adding a Back target.
        const setPath = (newPath, fromHistory = false) => {
            path = Array.isArray(newPath) ? newPath.filter((id) => destMap.has(id)) : [];
            showTop();
            if (!fromHistory) commitHistory("replace");
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
            // The selectable-List form builds its rows directly rather than through the
            // registry, so it has no chrome host of its own; the mount call makes one when
            // there are persistent items, and is a pass-through when there are none.
            const mountedList = attachPersistentToolbarMounts(listBox, persistentSlots);
            rootMounts = mountedList.mounts;
            rootPane.appendChild(mountedList.node);
        } else {
            // Normal form: the content is built through the registry, so its own
            // `navigationTitle`/`toolbar` renders as chrome (ToolbarHelper) — the
            // stack adds no title of its own here.
            const body = document.createElement("div");
            body.className = "aui-nav-stack-body";
            const mountedRoot = attachPersistentToolbarMounts(ctx.build(content), persistentSlots);
            rootMounts = mountedRoot.mounts;
            body.appendChild(mountedRoot.node);
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
            back.addEventListener("click", () => {
                if (historyEnabled) window.history.back();
                else pop();
            });
            bar.appendChild(back);
            pane.appendChild(bar);
            const body = document.createElement("div");
            body.className = "aui-nav-stack-body";
            const mounted = attachPersistentToolbarMounts(bodyContentNode, persistentSlots);
            body.appendChild(mounted.node);
            pane.appendChild(body);
            return { pane, mounts: mounted.mounts };
        };

        for (const [id, destEl] of destMap) {
            const { pane, mounts } = makeDestPane(ctx.build(destEl));
            destPanes.set(id, pane);
            destMounts.set(id, mounts);
            destOrder.push(id);
            node.appendChild(pane);
        }

        // Push/pop transition. The stack swaps panes by display; a short
        // directional slide + fade on the incoming pane gives the push/pop the
        // native feel. lastPathLen tracks depth so we animate only on a real
        // depth change - push (deeper) enters from the right, pop (shallower)
        // from the left - never on the first render or a same-depth reconcile.
        // Guarded for the headless test DOM (no element.animate) and reduced
        // motion; the 24px slide is small and clipped where an ancestor clips
        // overflow-x (the NavigationSplitView detail pane does).
        let lastPathLen = null;
        const animatePaneIn = (pane, fromRight) => {
            if (!pane || typeof pane.animate !== "function" || prefersReducedMotion()) return;
            pane.animate(
                [{ transform: `translateX(${fromRight ? 24 : -24}px)`, opacity: 0 },
                 { transform: "translateX(0)", opacity: 1 }],
                { duration: 220, easing: "ease-out" },
            );
        };

        const showTop = () => {
            const top = path.length ? path[path.length - 1] : null;
            rootPane.style.display = top === null ? "" : "none";
            destPanes.forEach((pane, id) => { pane.style.display = id === top ? "" : "none"; });
            // Move the ONE persistent node into the pane that just became visible. Runs
            // here, synchronously with the display toggle, so it lands before paint and
            // the incoming bar is never seen without its items.
            movePersistentToolbar(persistentGroups, top === null ? rootMounts : destMounts.get(top), ctx.logger);
            // Selectable-List form: highlight the pushed row, cleared at root.
            rowsByDest.forEach((row, destId) => {
                const on = path.includes(destId);
                row.classList.toggle("aui-list-row-selected", on);
                row.setAttribute("aria-selected", on ? "true" : "false");
            });
            if (lastPathLen !== null && path.length !== lastPathLen) {
                animatePaneIn(top === null ? rootPane : destPanes.get(top), path.length > lastPathLen);
            }
            lastPathLen = path.length;
        };

        // Push events bubble up from NavigationLinks (and selectable rows reach
        // push() directly). Stop here so an outer stack does not also navigate.
        node.addEventListener(NAV_PUSH_EVENT, (event) => {
            event.stopPropagation();
            push(event.detail);
        });

        // Left-edge swipe-back (the iOS interactive-pop idiom): pop the top pane,
        // the same action as the Back button. Only when there is something to pop;
        // routes through history.back() when browserHistory is on, so a swipe, the
        // button, and the browser Back all agree.
        attachEdgeBackSwipe(node, () => path.length > 0, () => {
            if (historyEnabled) window.history.back();
            else pop();
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
                    const { pane, mounts } = makeDestPane(contentNode);
                    destMap.set(id, destEl);
                    destPanes.set(id, pane);
                    destMounts.set(id, mounts);
                    destOrder.splice(index, 0, id);
                    node.appendChild(pane); // hidden; order among panes is display-toggled, not visual
                },
                remove: (id) => {
                    const i = destOrder.indexOf(id);
                    if (i < 0) return false;
                    destPanes.get(id)?.remove();
                    destPanes.delete(id);
                    destMounts.delete(id);
                    destMap.delete(id);
                    destOrder.splice(i, 1);
                    if (path.includes(id)) { path = path.filter((p) => p !== id); showTop(); commitHistory("replace"); }
                    return true;
                },
            });

            // Opt-in browser history: capture/restore the path. Registering folds
            // the current path into the active entry; restore reconciles without
            // writing history back (fromHistory).
            if (historyEnabled) {
                historyHandle = registerNavigationHistory(element.id, {
                    capture: () => [...path],
                    restore: (saved) => setPath(Array.isArray(saved) ? saved : [], true),
                });
                node._auiDestroy = () => historyHandle.release();
            }
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

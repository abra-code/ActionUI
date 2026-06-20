// MenuBar.js - the application menu bar, rendered as a modern web app shell.
//
// Canonical model (Documentation/ActionUI-MenuBar-JSON-Guide.md): the app menu
// bar is NOT a view - it is a separate ARRAY-root document (MainMenu.json) built
// by the ActionUIMenuBar library as "standard macOS bar + deltas". A `CommandMenu`
// adds a top-level menu; a `CommandGroup` inserts / replaces / deletes within the
// standard bar (App / File / Edit / Format / Window / Help). The only leaf items
// are `Button` (title, actionID, systemImage, keyboardShortcut) and
// `Divider`/`Separator`; the host wires each actionID.
//
// Web reinterpretation. There is no desktop-style menu strip on the web, and no
// standard bar to replicate: Cut / Copy / Paste / Quit / Hide / Minimize are
// OS- or browser-native and carry no actionID, so they are meaningless here. The
// modern web/mobile shape is a single hamburger (top-left) plus an optional
// account menu (top-right). So this module renders:
//   * a thin top app bar - a hamburger button (left) and, when declared, an
//     account button (right);
//   * a slide-in left drawer holding the app's own commands, each `CommandMenu`
//     as a titled section, `CommandGroup` additions grouped under the standard
//     menu their target resolves to;
//   * the account menu as a top-layer popover (the shared PopoverPlacement infra)
//     anchored to the account button.
// Only host commands that carry an `actionID` are clickable; an item without one
// is shown disabled (it exists on the bar but has no web action), and standard
// CommandGroup edits with no children (deletions of native items) have no web
// surface and are dropped. An account menu is any `CommandMenu` tagged with the
// web-only role key `"role:web": "account"` (resolved to `role` by PlatformFilter).
//
// See Private/Web_Porting_Notes.md (Menu bar / app shell).

import { makeFloatingPanel } from "../Helpers/PopoverPlacement.js";
import { PlatformFilter } from "../Common/PlatformFilter.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";

// Standard-bar maps from the JSON guide (sections 4.1 item ids, 4.2 group placements):
// resolve a CommandGroup's `placementTarget` to the top-level menu it belongs to,
// so its added items land under the right drawer section. Item ids resolve before
// group names (the guide's order of specificity); an unknown target is shown
// verbatim as its own section.
const ITEM_ID_TO_MENU = {
    about: "App", services: "App", hide: "App", hideOthers: "App", showAll: "App", quit: "App",
    new: "File", open: "File", close: "File",
    undo: "Edit", redo: "Edit", cut: "Edit", copy: "Edit", paste: "Edit", delete: "Edit", selectAll: "Edit",
    minimize: "Window", zoom: "Window", bringAllToFront: "Window",
    help: "Help",
};
const GROUP_TO_MENU = {
    appInfo: "App", appSettings: "App", systemServices: "App", appVisibility: "App", appTermination: "App",
    newItem: "File", saveItem: "File", importExport: "File", printItem: "File",
    undoRedo: "Edit", pasteboard: "Edit", textEditing: "Edit", textFormatting: "Edit",
    windowSize: "Window", windowArrangement: "Window", windowList: "Window", singleWindowList: "Window",
    toolbar: "View", sidebar: "View", help: "Help",
};
// Drawer order for the standard-menu sections (custom CommandMenus come first, in
// document order, since they are the app's own commands).
const STANDARD_MENU_ORDER = ["File", "Edit", "Format", "View", "Window", "App", "Help"];
const DEFAULT_ACCOUNT_ICON = "person.crop.circle";

// Parses a raw MainMenu.json (a JS array or already-parsed value) into the shell
// model { sections: [{ title, items }], account: { title, systemImage, items } | null }.
// Runs the web PlatformFilter first so `<key>:web` overrides resolve (notably
// `role:web` -> `role`) and other platforms' keys drop. Warnings mirror the
// canonical guide (only CommandMenu / CommandGroup at top level; only Button /
// Divider as children; a CommandMenu needs a non-empty name).
export function parseMenuBar(raw, logger) {
    const filtered = PlatformFilter.WEB.withLogger(logger).filter(raw);
    if (!Array.isArray(filtered)) {
        logger.log("Menu bar JSON must be a JSON array of CommandMenu / CommandGroup elements; ignoring", "warning");
        return { sections: [], account: null };
    }

    // name -> { items, standard } (insertion order preserved; standard sections
    // are reordered to STANDARD_MENU_ORDER at the end).
    const sections = new Map();
    const sectionFor = (name, standard) => {
        if (!sections.has(name)) sections.set(name, { items: [], standard });
        return sections.get(name);
    };
    let account = null;

    for (const element of filtered) {
        if (!element || typeof element !== "object") continue;
        const props = element.properties ?? {};
        const children = Array.isArray(element.children) ? element.children : [];

        if (element.type === "CommandMenu") {
            const name = typeof props.name === "string" ? props.name.trim() : "";
            if (!name) {
                logger.log("CommandMenu requires a non-empty 'name'; skipping", "warning");
                continue;
            }
            const items = parseItems(children, logger);
            if (props.role === "account") {
                if (account) {
                    logger.log(`Multiple account menus declared (role:web "account"); using the first, ignoring '${name}'`, "warning");
                    continue;
                }
                account = { title: name, systemImage: typeof props.systemImage === "string" ? props.systemImage : DEFAULT_ACCOUNT_ICON, items };
                continue;
            }
            sectionFor(name, false).items.push(...items);
        } else if (element.type === "CommandGroup") {
            // Standard-bar editing (replace / delete native items) has no web
            // surface; only ADDED commands that carry an actionID are meaningful.
            const items = parseItems(children, logger).filter((it) => it.kind !== "item" || it.actionID);
            if (items.length === 0) continue; // a deletion or selector-only group: nothing to show
            sectionFor(resolveTargetMenu(props.placementTarget), true).items.push(...items);
        } else {
            logger.log(`Menu bar element '${element.type}' is not a CommandMenu or CommandGroup; skipping`, "warning");
        }
    }

    // Custom sections (document order) first, then standard sections by bar order.
    const entries = [...sections.entries()].filter(([, s]) => s.items.length > 0);
    const custom = entries.filter(([, s]) => !s.standard);
    const standard = entries.filter(([, s]) => s.standard)
        .sort(([a], [b]) => indexOrLast(STANDARD_MENU_ORDER, a) - indexOrLast(STANDARD_MENU_ORDER, b));
    const ordered = [...custom, ...standard].map(([title, s]) => ({ title, items: s.items }));
    return { sections: ordered, account };
}

function indexOrLast(list, value) {
    const i = list.indexOf(value);
    return i < 0 ? list.length : i;
}

// Interprets a CommandMenu / CommandGroup child list into menu items. A Button is
// an action declaration (title / icon / actionID), a Divider/Separator a rule;
// anything else warns and is skipped (the guide allows only these two).
function parseItems(children, logger) {
    const items = [];
    for (const child of children) {
        if (!child || typeof child !== "object") continue;
        if (child.type === "Button") {
            const props = child.properties ?? {};
            const title = typeof props.title === "string" ? props.title : "";
            if (!title) {
                logger.log("Menu bar Button requires a 'title'; skipping", "warning");
                continue;
            }
            items.push({ kind: "item", title, actionID: typeof props.actionID === "string" ? props.actionID : null, props });
        } else if (child.type === "Divider" || child.type === "Separator") {
            items.push({ kind: "divider" });
        } else {
            logger.log(`Menu bar item '${child.type}' is not a Button or Divider; skipping`, "warning");
        }
    }
    return items;
}

// Resolves a CommandGroup placementTarget to a drawer section name: an item id, then
// a group name, then a literal title. Default target is "help" (the guide's default).
function resolveTargetMenu(placementTarget) {
    const target = typeof placementTarget === "string" && placementTarget ? placementTarget : "help";
    return ITEM_ID_TO_MENU[target] ?? GROUP_TO_MENU[target] ?? capitalize(target);
}

function capitalize(s) {
    return s.length ? s[0].toUpperCase() + s.slice(1) : s;
}

// Builds the app shell DOM for a parsed menu model. Returns { shell, stage }: the
// caller mounts `shell` in the host container and presents the window INTO `stage`
// (a centering, definite-height region below the app bar - so the window's own
// frame clamp still resolves, per the layout-engine notes). `dispatch(actionID)`
// routes a chosen command to the host (the window model, app-level viewID 0).
export function buildAppShell(model, appName, dispatch, logger) {
    const shell = document.createElement("div");
    shell.className = "aui-app-shell";

    const bar = document.createElement("header");
    bar.className = "aui-appbar";

    const closeDrawer = () => shell.classList.remove("is-drawer-open");

    // Hamburger: three CSS bars (font-independent, so the core chrome never relies
    // on the SF->Material glyph map).
    const hamburger = document.createElement("button");
    hamburger.type = "button";
    hamburger.className = "aui-hamburger";
    hamburger.setAttribute("aria-label", "Menu");
    for (let i = 0; i < 3; i += 1) {
        const line = document.createElement("span");
        line.className = "aui-hamburger-bar";
        hamburger.appendChild(line);
    }
    hamburger.addEventListener("click", () => shell.classList.toggle("is-drawer-open"));
    bar.appendChild(hamburger);

    const title = document.createElement("span");
    title.className = "aui-appbar-title";
    title.textContent = appName || "";
    bar.appendChild(title);

    const spacer = document.createElement("span");
    spacer.className = "aui-appbar-spacer";
    bar.appendChild(spacer);

    const stage = document.createElement("div");
    stage.className = "aui-app-stage";

    const backdrop = document.createElement("div");
    backdrop.className = "aui-drawer-backdrop";
    backdrop.addEventListener("click", closeDrawer);

    const drawer = document.createElement("nav");
    drawer.className = "aui-drawer";
    drawer.setAttribute("aria-label", "Application menu");
    const drawerHead = document.createElement("div");
    drawerHead.className = "aui-drawer-head";
    drawerHead.textContent = appName || "Menu";
    drawer.appendChild(drawerHead);
    if (model.sections.length === 0) {
        const empty = document.createElement("div");
        empty.className = "aui-drawer-empty";
        empty.textContent = "No commands";
        drawer.appendChild(empty);
    }
    for (const section of model.sections) {
        drawer.appendChild(buildSectionNode(section, dispatch, closeDrawer, logger));
    }
    // Escape closes the drawer (the account popover owns its own Escape handling).
    document.addEventListener("keydown", (event) => { if (event.key === "Escape") closeDrawer(); });

    // Swipe-left to close on touch (the mobile drawer idiom, alongside the backdrop
    // tap and Escape): a clearly horizontal leftward drag past a small threshold
    // dismisses the open drawer. Passive listeners, so vertical scrolling of the
    // drawer is never blocked; a no-op when the drawer is already closed.
    let swipeStartX = null;
    let swipeStartY = null;
    drawer.addEventListener("touchstart", (event) => {
        const touch = event.touches && event.touches[0];
        swipeStartX = touch ? touch.clientX : null;
        swipeStartY = touch ? touch.clientY : null;
    }, { passive: true });
    drawer.addEventListener("touchend", (event) => {
        if (swipeStartX === null) return;
        const touch = event.changedTouches && event.changedTouches[0];
        if (touch) {
            const dx = touch.clientX - swipeStartX;
            const dy = touch.clientY - swipeStartY;
            if (dx <= -40 && Math.abs(dx) > Math.abs(dy)) closeDrawer(); // leftward, horizontal-dominant
        }
        swipeStartX = null;
        swipeStartY = null;
    }, { passive: true });

    shell.append(bar, stage, backdrop, drawer);

    if (model.account) {
        const accountBtn = document.createElement("button");
        accountBtn.type = "button";
        accountBtn.className = "aui-account-button";
        accountBtn.setAttribute("aria-label", model.account.title || "Account");
        const iconProps = { systemImage: model.account.systemImage };
        const icon = labelIcon(selectLabelIcon(iconProps, "assetImage", "Account menu", logger), iconProps, "Account menu", logger);
        if (icon) accountBtn.appendChild(icon);
        else accountBtn.textContent = (model.account.title || "?").slice(0, 1).toUpperCase();
        bar.appendChild(accountBtn);

        const accountPanel = document.createElement("div");
        accountPanel.className = "aui-account-menu";
        accountPanel.setAttribute("role", "menu");
        shell.appendChild(accountPanel);
        const panel = makeFloatingPanel(accountPanel, accountBtn, { containmentRoots: [accountBtn] });
        if (model.account.items.length === 0) {
            const empty = document.createElement("div");
            empty.className = "aui-drawer-empty";
            empty.textContent = "No commands";
            accountPanel.appendChild(empty);
        }
        for (const item of model.account.items) {
            accountPanel.appendChild(buildItemNode(item, dispatch, () => panel.close(), logger));
        }
        accountBtn.addEventListener("click", () => { if (panel.open) panel.close(); else panel.show(); });
    }

    return { shell, stage };
}

function buildSectionNode(section, dispatch, onActivate, logger) {
    const node = document.createElement("div");
    node.className = "aui-drawer-section";
    const heading = document.createElement("div");
    heading.className = "aui-drawer-section-title";
    heading.textContent = section.title;
    node.appendChild(heading);
    for (const item of section.items) node.appendChild(buildItemNode(item, dispatch, onActivate, logger));
    return node;
}

// One menu item (or a divider). A clickable item dispatches its actionID after
// activating the close callback; an item with no actionID is shown disabled (it
// exists on the canonical bar but has no web action).
function buildItemNode(item, dispatch, onActivate, logger) {
    if (item.kind === "divider") {
        const rule = document.createElement("hr");
        rule.className = "aui-menubar-divider";
        return rule;
    }
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "aui-menubar-item";
    btn.setAttribute("role", "menuitem");
    const icon = labelIcon(selectLabelIcon(item.props, "assetImage", "Menu bar item", logger), item.props, "Menu bar item", logger);
    if (icon) btn.appendChild(icon);
    const text = document.createElement("span");
    text.textContent = item.title;
    btn.appendChild(text);
    if (item.actionID) {
        btn.addEventListener("click", () => { onActivate(); dispatch(item.actionID); });
    } else {
        btn.disabled = true;
        btn.classList.add("is-disabled");
    }
    return btn;
}

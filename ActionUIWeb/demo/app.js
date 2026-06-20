// app.js — demo application logic.
// Exercises the value bridge (get/setString, get/setInt, getBool), the action
// system, and — new — the LoadableView split: the UI is a NavigationSplitView
// shell (ui.json) whose sidebar rows load each section from a separate JSON file
// under demo/sections/. Elements live in those loaded files, so a section's data
// is pushed once it loads (viewDidLoadActionID) rather than up front.

import { Application, Window, InsertPosition, ModalStyle } from "../src/ActionUI.js";
import { ConsoleLogger } from "../src/Common/ConsoleLogger.js";
import { setDebugMode } from "../src/Common/Debug.js";

// ---- Diagnostics: debug mode + a log panel under the demo ----
// Debug mode (`?debug` / the panel checkbox) must be set before building so it
// reaches every glyph (sections preload on load).
const debugOn = new URLSearchParams(location.search).has("debug");
setDebugMode(debugOn);

const diagEl = document.getElementById("aui-diag");
const logListEl = document.getElementById("aui-diag-log");
const countEl = document.getElementById("aui-diag-count");
let issueCount = 0;

function appendLogEntry(level, message) {
    const li = document.createElement("li");
    li.className = `aui-diag-entry aui-diag-${level}`;
    const time = document.createElement("span");
    time.className = "aui-diag-time";
    time.textContent = new Date().toLocaleTimeString();
    const lvl = document.createElement("span");
    lvl.className = "aui-diag-level";
    lvl.textContent = level;
    const msg = document.createElement("span");
    msg.className = "aui-diag-msg";
    msg.textContent = message; // textContent, never innerHTML — messages are untrusted
    li.append(time, lvl, msg);
    logListEl.appendChild(li);
    logListEl.scrollTop = logListEl.scrollHeight;
    if (level === "warning" || level === "error") {
        issueCount += 1;
        countEl.textContent = String(issueCount);
        countEl.classList.add("has-issues");
    }
}

// A logger that mirrors to the browser console (the default ConsoleLogger) and
// to the on-page panel, so renderer warnings/errors are visible without devtools.
const consoleLogger = new ConsoleLogger();
const logger = {
    log(message, level = "info") {
        consoleLogger.log(message, level);
        appendLogEntry(level, message);
    },
};

// Panel controls.
const debugBox = document.getElementById("aui-diag-debug");
debugBox.checked = debugOn;
debugBox.addEventListener("change", () => {
    // Glyphs are built once at load, so toggling reloads with the param set/cleared.
    const url = new URL(location.href);
    if (debugBox.checked) url.searchParams.set("debug", "1");
    else url.searchParams.delete("debug");
    location.href = url.toString();
});
const toggleBtn = document.getElementById("aui-diag-toggle");
toggleBtn.addEventListener("click", () => {
    const expanded = diagEl.classList.toggle("expanded");
    toggleBtn.setAttribute("aria-expanded", String(expanded));
});
document.getElementById("aui-diag-clear").addEventListener("click", () => {
    logListEl.replaceChildren();
    issueCount = 0;
    countEl.textContent = "";
    countEl.classList.remove("has-issues");
});

const app = new Application({ name: "ActionUIWeb Demo" });
const win = await Window.fromURL("./ui.json", undefined, logger);

// Map provider: by default Map uses the built-in dependency-free embed
// (Views/MapEmbed.js). LINK a richer provider to override it - it registers "Map"
// last and wins (the pluggable-provider model). ?maplibre loads the key-free
// MapLibre provider; ?google=YOUR_KEY loads the Google provider; ?mapkit=YOUR_JWT
// loads the Apple MapKit JS provider (Google/Apple need the host's own key/token,
// passed here via the globals the providers fall back to). Must run before present()
// so the override is registered before the tree is built.
const mapParams = new URLSearchParams(location.search);
if (mapParams.has("maplibre")) {
    await import("../providers/map-maplibre.js");
} else if (mapParams.has("google")) {
    const key = mapParams.get("google");
    if (key) window.AUI_GOOGLE_MAPS_API_KEY = key;
    await import("../providers/map-google.js");
} else if (mapParams.has("mapkit")) {
    const token = mapParams.get("mapkit");
    if (token) window.AUI_MAPKIT_JS_TOKEN = token;
    await import("../providers/map-apple.js");
}

// Application menu bar (MainMenu.json): on web this renders as the top app bar -
// a hamburger drawer (the "Go"/"Tools" command menus + the File "Import" group)
// and a top-right account menu (the role:web "account" command menu). Loaded
// before present() so the shell wraps the window.
await app.setMenuBarFromURL("./MainMenu.json", logger);

app.presentWindow(win, document.getElementById("root"));

// Open on the Overview section (the LoadableViews all preload as the split's
// destinations; this just selects which one is shown first) - but ONLY on a
// regular (wide) layout. In a compact layout the split shows one column at a
// time, so a preselected destination would skip past the sidebar and land the
// user inside Overview with no visible section list. Leaving it unselected (0)
// lands on the sidebar - the section list - which is the right small-screen
// landing. The split compacts below 640px of its own width (NavigationSplitView
// COMPACT_WIDTH); the window content width is the viewport minus the root's two
// 20px side paddings, so a viewport >= 680px means the split renders regular.
// Generic, not device-specific: a phone in portrait lands on the list, while a
// wide layout (landscape phone, tablet, desktop) preselects Overview.
if (window.matchMedia("(min-width: 680px)").matches) {
    win.setState(1000, "selectedDestination", 1100);
}

// NavigationSplitView sidebar selection: the sidebar List's actionID fires with no
// context — read the selected destination id from the split view's state. The demo
// is split into many small, feature-focused sections (one JSON file each) rather
// than a few crammed ones; this maps each destination id to its label.
const SECTION_NAMES = {
    1100: "Overview", 1101: "Shapes & Layout", 1102: "Scrolling", 1103: "Text Input",
    1104: "Controls", 1105: "Pickers", 1106: "Forms", 1107: "Lists", 1108: "Table",
    1109: "Insertion", 1110: "Navigation", 1111: "Media & Web", 1112: "Presentation",
    1113: "Properties", 1114: "Animation", 1115: "Upload", 1116: "Windows",
};
app.action("sectionSelect", () => {
    const dest = win.getState(1000, "selectedDestination");
    win.setString(20, 0, dest ? `Section: ${SECTION_NAMES[dest] ?? dest}.` : "No section selected.");
});

// Page lifecycle hooks (ui.json root, :web). onBackground fires when the tab is
// hidden (switch tab/app, or close) — the reliable point to persist; onForeground
// when it returns to view; onTerminate on pagehide. The demo records when it was
// hidden and reports it on return (switch tabs and come back to see it).
let lastHiddenAt = null;
app.action("appBackground", () => {
    lastHiddenAt = new Date();
    logger.log("Lifecycle: backgrounded — a host would persist state here.", "info");
});
app.action("appForeground", () => {
    win.setString(20, 0, lastHiddenAt ? `Resumed (was hidden at ${lastHiddenAt.toLocaleTimeString()}).` : "Active.");
});
app.action("appTerminate", () => {
    logger.log("Lifecycle: page unloading (pagehide).", "info");
});

// setproperty.json — host-driven runtime visual mutation via win.setElementProperty.
// Each handler changes one visual property on the live target node (id 1200), in
// place (no rebuild); the disabled pair toggles a real control (id 1201).
const PROP_TARGET = 1200;
app.action("propFade",        () => win.setElementProperty(PROP_TARGET, "opacity", 0.3));
app.action("propRestore",     () => win.setElementProperty(PROP_TARGET, "opacity", 1));
app.action("propHide",        () => win.setElementProperty(PROP_TARGET, "hidden", true));
app.action("propShow",        () => win.setElementProperty(PROP_TARGET, "hidden", false));
app.action("propRedText",     () => win.setElementProperty(PROP_TARGET, "foregroundColor", "red"));
app.action("propDefaultText", () => win.setElementProperty(PROP_TARGET, "foregroundColor", "primary"));
app.action("propBlueBg",      () => win.setElementProperty(PROP_TARGET, "background", "#3b82f6"));
app.action("propGrayBg",      () => win.setElementProperty(PROP_TARGET, "background", "#e5e7eb"));
app.action("propRound",       () => win.setElementProperty(PROP_TARGET, "cornerRadius", 24));
app.action("propSquare",      () => win.setElementProperty(PROP_TARGET, "cornerRadius", 0));
app.action("propTargetTapped", () => win.setString(20, 0, "Target button (1201) tapped."));
app.action("propDisable",     () => win.setElementProperty(1201, "disabled", true));
app.action("propEnable",      () => win.setElementProperty(1201, "disabled", false));

// animation.json — the same shapes/curves as Swift's View.animation.json. Each button
// mutates a property via win.setElementProperty; the shape's animation modifier eases
// the change (web animates by CSS property, not by a watched value key, so e.g. shape
// 102's Scale also animates - a documented divergence).
// `a` is the shape's rest value (its initial JSON value), `b` the changed one. Compare
// against `b` so the FIRST click goes to `b` (a visible change) - comparing against `a`
// would make the first click resolve to `a`, which already matches the initial value,
// so nothing would move until the second click.
const animPrev = {};
const toggleProp = (key, id, name, a, b) => {
    const next = animPrev[key] === b ? a : b;
    animPrev[key] = next;
    win.setElementProperty(id, name, next);
};
app.action("anim.demo.101.opacity", () => toggleProp("101op", 101, "opacity", 1, 0.3));
app.action("anim.demo.101.scale",   () => toggleProp("101sc", 101, "scaleEffect", 1, 1.5));
app.action("anim.demo.102.opacity", () => toggleProp("102op", 102, "opacity", 1, 0.3));
app.action("anim.demo.102.scale",   () => toggleProp("102sc", 102, "scaleEffect", 1, 1.5));
app.action("anim.demo.103.scale",   () => toggleProp("103sc", 103, "scaleEffect", 1, 1.4));
const ANIM_COLORS = ["purple", "orange", "blue", "green", "pink"];
let animColorIdx = 0;
app.action("anim.demo.104.color", () => {
    animColorIdx = (animColorIdx + 1) % ANIM_COLORS.length;
    win.setElementProperty(104, "foregroundColor", ANIM_COLORS[animColorIdx]);
});
let animRotation = 0;
app.action("anim.demo.105.rotate", () => {
    animRotation += 90;
    win.setElementProperty(105, "rotationEffect", animRotation);
});

// windows.json - presentWindow with multiple in-document surfaces. Each panel is a
// full, independent Window (own uuid + own model) presented by the SAME Application
// into a placeholder host node from the section (1300 / 1301). They share the app's
// action registry, so a panel's button routes here; ctx.windowUUID disambiguates
// which surface fired (app.getWindow(uuid) recovers it). app.closeWindow tears a
// panel down (unmount + dispose its model) and drops it from app.windows. Auxiliary
// surfaces pass { appShell: false } so the menu-bar app shell stays on the main
// window only. Note each panel addresses viewID 1 / 10 in its OWN model, independent
// of the main window's ids - that is the point of separate surfaces.
const panelADescription = {
    type: "VStack",
    properties: { alignment: "leading", spacing: 6, padding: 12, background: "#eff6ff", cornerRadius: 8, frame: { maxWidth: "infinity" } },
    children: [
        { type: "Text", properties: { text: "Panel A", font: "headline" } },
        { type: "Text", id: 1, properties: { text: "Independent surface. Set my text from the host.", foregroundColor: "secondary", font: "callout" } },
        { type: "Button", properties: { title: "Ping from inside A", buttonStyle: "bordered", actionID: "panelPing" } },
    ],
};
const panelBDescription = {
    type: "VStack",
    properties: { alignment: "leading", spacing: 6, padding: 12, background: "#f0fdf4", cornerRadius: 8, frame: { maxWidth: "infinity" } },
    children: [
        { type: "Text", properties: { text: "Panel B", font: "headline" } },
        { type: "Text", id: 10, properties: { text: "Count: 0", font: "callout" } },
        { type: "Button", properties: { title: "Ping from inside B", buttonStyle: "bordered", actionID: "panelPing" } },
    ],
};
const panels = {};   // hostId -> Window
const panelLabels = {}; // uuid -> "A" | "B" (so panelPing can name its source)
let panelBCount = 0;

function restoreHost(hostId, label) {
    const host = win.model.findNode(hostId);
    if (!host) return;
    const note = document.createElement("div");
    note.style.color = "var(--aui-secondary, #6b7280)";
    note.style.font = "var(--aui-font-callout, inherit)";
    note.textContent = label;
    host.replaceChildren(note);
}

function openPanel(hostId, description, label) {
    if (panels[hostId]) { win.setString(20, 0, `Panel ${label} already open.`); return; }
    const host = win.model.findNode(hostId);
    if (!host) { win.setString(20, 0, `Host ${hostId} not found.`); return; }
    const panel = Window.fromJSON(description, undefined, logger);
    app.presentWindow(panel, host, { appShell: false }); // auxiliary surface: no menu-bar shell
    panels[hostId] = panel;
    panelLabels[panel.uuid] = label;
    win.setString(20, 0, `Opened panel ${label} (uuid ${panel.uuid.slice(0, 8)}); ${app.windowList.length} windows total.`);
}

function closePanel(hostId, label) {
    const panel = panels[hostId];
    if (!panel) { win.setString(20, 0, `Panel ${label} is not open.`); return; }
    delete panelLabels[panel.uuid];
    app.closeWindow(panel);          // unmounts the panel + disposes its model
    delete panels[hostId];
    restoreHost(hostId, `Panel ${label} not open.`);
    if (hostId === 1301) panelBCount = 0;
    win.setString(20, 0, `Closed panel ${label}; ${app.windowList.length} windows total.`);
}

app.action("winOpenA", () => openPanel(1300, panelADescription, "A"));
app.action("winOpenB", () => openPanel(1301, panelBDescription, "B"));
app.action("winCloseA", () => closePanel(1300, "A"));
app.action("winCloseB", () => closePanel(1301, "B"));
app.action("winCloseAll", () => { closePanel(1300, "A"); closePanel(1301, "B"); });
app.action("winDriveA", () => {
    const panel = panels[1300];
    if (!panel) { win.setString(20, 0, "Open panel A first."); return; }
    panel.setString(1, 0, `Set by the host at ${new Date().toLocaleTimeString()}.`);
    win.setString(20, 0, "Drove panel A's own model (its viewID 1).");
});
app.action("winDriveB", () => {
    const panel = panels[1301];
    if (!panel) { win.setString(20, 0, "Open panel B first."); return; }
    panelBCount += 1;
    panel.setString(10, 0, `Count: ${panelBCount}`);
    win.setString(20, 0, `Drove panel B's own model (its viewID 10) -> ${panelBCount}.`);
});
// Shared handler for both panels' inner button: identify the source surface from the
// dispatched windowUUID (the surface a sub-window action carries), not a per-panel id.
app.action("panelPing", (ctx) => {
    const which = panelLabels[ctx.windowUUID] ?? "?";
    win.setString(20, 0, `Ping from panel ${which} (window ${ctx.windowUUID.slice(0, 8)}).`);
});

// Menu bar (MainMenu.json) commands. The "Go" menu drives the split's selected
// destination (same state the sidebar selection writes); the rest set status or
// reuse existing demo behavior. All dispatch at the app level (viewID 0).
function goSection(dest) {
    win.setState(1000, "selectedDestination", dest);
    win.setString(20, 0, `Section: ${SECTION_NAMES[dest]}.`);
}
app.action("go.overview", () => goSection(1100));
app.action("go.controls", () => goSection(1104));
app.action("go.lists", () => goSection(1107));
app.action("go.navigation", () => goSection(1110));
app.action("tools.report", () => win.setString(20, 0, "Running report..."));
app.action("tools.clearLog", () => document.getElementById("aui-diag-clear").click());
app.action("file.import", () => pick({ allowsMultiple: true }));
app.action("account.profile", () => win.setString(20, 0, "Account: Profile."));
app.action("account.settings", () => win.setString(20, 0, "Account: Settings."));
app.action("account.signOut", () => win.setString(20, 0, "Account: signed out."));

// The Lists section is data-driven: once its JSON loads, its List/LazyVGrid
// bindings exist, so push their rows through the rows API (states["content"]).
app.action("listsLoaded", () => {
    win.setElementRows(45, [["Low"], ["Medium"], ["High"]]);
    win.setElementRows(55, [["Inbox", "tray"], ["Drafts", "text.document"], ["Sent", "paperplane"]]);
    // LazyVGrid template mode: one substituted instance per row, flowing into the grid.
    win.setElementRows(56, [
        ["Inbox", "tray"], ["Drafts", "text.document"], ["Sent", "paperplane"],
        ["Flagged", "flag"], ["Trash", "trash"], ["Archive", "archivebox"],
    ]);
});

// The Table section: a base dataset (enough rows to overflow the table's bounded
// frame and show the vertical scroller), pushed once the section loads and reloaded
// by "Load Data". "Append Row" grows it past the frame; "Clear" empties it. Mirrors
// the Apple ActionUISwiftTestApp Table.json demo (load / append / clear).
const TABLE_BASE_ROWS = [
    ["Budget.xlsx", "tablecells", "Open"],
    ["Photo.jpg", "photo", "Open"],
    ["Notes.txt", "text.document", "Open"],
    ["Slides.key", "rectangle.on.rectangle", "Open"],
    ["Archive.zip", "archivebox", "Open"],
    ["Soundtrack.m4a", "music.note", "Open"],
    ["Trailer.mp4", "film", "Open"],
    ["Projects", "folder", "Open"],
];
let tableAppendSeq = 0;
app.action("tableLoaded", () => {
    win.setElementRows(100, TABLE_BASE_ROWS);
    // The static headerless table (id 108) - a design-time columnHeadersVisibility
    // "hidden", so it just needs its rows pushed once.
    win.setElementRows(108, [["Renderer", "DOM + CSS"], ["Rows", "data-driven"], ["Header", "hidden"]]);
});
app.action("tableLoad", () => {
    tableAppendSeq = 0;
    win.setElementRows(100, TABLE_BASE_ROWS);
    win.setString(20, 0, `Loaded ${TABLE_BASE_ROWS.length} rows (scroll the table to see them all).`);
});
app.action("tableAppend", () => {
    tableAppendSeq += 1;
    win.appendElementRows(100, [[`Item ${tableAppendSeq}.dat`, "text.document", "Open"]]);
    win.setString(20, 0, `Appended a row - ${win.getElementRows(100).length} total (the table grows and scrolls).`);
});
app.action("tableClear", () => {
    tableAppendSeq = 0;
    win.clearElementRows(100);
    win.setString(20, 0, "Table cleared.");
});

// The Upload section: drag-and-drop + file panels, both feeding a (mock) upload.
// The renderer only fires the actions; targeting visuals are host policy, so the
// demo decorates its drop element (501) with the .aui-drop-zone class once the
// section loads and toggles .is-targeted from onDropTargetedActionID.
app.action("filesLoaded", () => {
    win.model.findNode(501)?.classList.add("aui-drop-zone");
});
app.action("dropTargeted", (ctx) => {
    win.model.findNode(501)?.classList.toggle("is-targeted", !!ctx.context?.isTargeted);
});
app.action("zoneHovered", (ctx) => {
    win.setString(20, 0, ctx.context?.isHovering ? "Drop zone: drop files to upload." : "Ready.");
});
app.action("filesDropped", (ctx) => {
    // items = file names (or dragged text); files = the real File objects (web-only).
    const items = ctx.context?.items ?? [];
    const files = ctx.context?.files ?? [];
    win.model.findNode(501)?.classList.remove("is-targeted");
    win.setString(510, 0, items.length ? `Dropped ${files.length || items.length}: ${items.join(", ")}` : "Dropped (no readable items).");
    // A real host would upload here, e.g.:
    //   for (const f of files) await fetch("/upload", { method: "POST", body: f });
});

// File panel (app.openPanel) - async on web, resolving to File[] (or null on cancel).
async function pick(opts) {
    const files = await app.openPanel(opts);
    if (!files) { win.setString(510, 0, "File panel cancelled."); return; }
    win.setString(510, 0, `Picked ${files.length}: ${files.map((f) => f.name).join(", ")}`);
    // Upload the same way: for (const f of files) await fetch("/upload", { method:"POST", body:f });
}
app.action("pickFiles", () => pick({ allowsMultiple: true }));
app.action("pickImages", () => pick({ allowsMultiple: true, allowedTypes: ["public.image"] }));

app.action("greet", () => {
    const name = win.getString(1).trim();
    let greeting = name ? `Hello, ${name}!` : "Hello, anonymous!";
    if (win.getBool(3)) greeting = greeting.toUpperCase();
    win.setString(20, 0, greeting);
});

app.action("shoutChanged", (ctx) => {
    win.setString(20, 0, `Shout mode: ${ctx.context.isOn ? "on" : "off"}`);
});

app.action("volumeChanged", () => {
    win.setString(31, 0, String(win.getInt(30)));
    win.setDouble(70, 0, win.getInt(30) / 100); // drive the progress bar from the slider
    win.setDouble(96, 0, win.getInt(30));       // …and both gauges
    win.setDouble(97, 0, win.getInt(30));
});

app.action("quantityChanged", () => win.setString(20, 0, `Quantity is now ${win.getInt(40)}.`));

app.action("passwordSubmit", () => {
    const len = win.getString(50).length;
    win.setString(20, 0, len ? `Password received (${len} characters).` : "No password entered.");
});

app.action("formatChanged", (ctx) => win.setString(20, 0, `Format set to "${ctx.context}".`));

app.action("alignChanged", (ctx) => win.setString(20, 0, `Alignment: ${ctx.context}.`));

app.action("viewChanged", (ctx) => win.setString(20, 0, `View: ${ctx.context}.`));

app.action("dateChanged", () => win.setString(20, 0, `Date: ${win.getString(80)}.`));

app.action("colorChanged", () => win.setString(20, 0, `Color: ${win.getString(81)}.`));

app.action("notesChanged", () => {
    win.setString(20, 0, `Notes: ${win.getString(95).length} characters.`);
});

// Exercises the state bridge: DisclosureGroup's expanded flag is a named
// state ("isExpanded"), not a value.
app.action("advancedToggled", () => {
    win.setString(20, 0, `Advanced ${win.getState(91, "isExpanded") ? "expanded" : "collapsed"}.`);
});

// Table: the selection-change action carries no context — read the value (the
// selected row, tab-joined); the per-row Button column fires with the row index.
app.action("tableSelect", () => {
    const row = win.getString(100).split("\t");
    win.setString(20, 0, win.getString(100) ? `Selected "${row[0]}".` : "Nothing selected.");
});
app.action("tableRowAction", (ctx) => win.setString(20, 0, `Open row ${ctx.context}.`));

// searchable List (id 47): the query arrives as the action context on each change.
// Apple/Android echo it into an in-document Text; the web demo echoes to the shared
// status line (id 20), matching how the other collections actions report.
app.action("collectionsSearch", (ctx) => {
    const query = ctx.context ?? "";
    win.setString(20, 0, query ? `Search: "${query}".` : "Search cleared.");
});

// Homogeneous List selection: no context — read the value (the selected row,
// tab-joined; a single column here).
app.action("homListSelect", () => {
    win.setString(20, 0, win.getString(45) ? `Priority: ${win.getString(45)}.` : "No priority selected.");
});

// Template List selection: the value is the selected row tab-joined (label, symbol).
app.action("tmplListSelect", () => {
    const row = win.getString(55).split("\t");
    win.setString(20, 0, win.getString(55) ? `Folder: ${row[0]}.` : "No folder selected.");
});

// Programmatic selection (Table 100 / homogeneous List 45). It is silent — no
// selection action fires — so each handler updates the status itself from the
// method's return: selectElementRow returns the selected row's columns (or null
// when the index is out of range, which clears); selectElementRowWithContent
// returns the 0-based match index (or -1).
app.action("listSelectIndex", () => {
    const row = win.selectElementRow(45, 2); // index 2 -> "High"
    win.setString(20, 0, row ? `List selected #3: ${row.join(" / ")}.` : "List: index out of range (cleared).");
});
app.action("listSelectContent", () => {
    const index = win.selectElementRowWithContent(45, "Medium"); // any column
    win.setString(20, 0, index >= 0 ? `List found "Medium" at row ${index}.` : `List: "Medium" not found.`);
});
app.action("listDeselect", () => {
    win.clearElementSelection(45);
    win.setString(20, 0, "List selection cleared.");
});
app.action("tableSelectIndex", () => {
    const row = win.selectElementRow(100, 1); // index 1 -> "Photo.jpg"
    win.setString(20, 0, row ? `Table selected #2: ${row[0]}.` : "Table: index out of range (cleared).");
});
app.action("tableSelectContent", () => {
    const index = win.selectElementRowWithContent(100, "Notes.txt", 0); // Name column
    win.setString(20, 0, index >= 0 ? `Table found "Notes.txt" at row ${index}.` : `Table: "Notes.txt" not found.`);
});
app.action("tableDeselect", () => {
    win.clearElementSelection(100);
    win.setString(20, 0, "Table selection cleared.");
});

// ScrollViewReader: the scroll target is the reader's Int value (the web's
// runtime proxy.scrollTo), so a button scroll is just setInt(readerID, rowID).
// Re-sending the same id re-scrolls, so each press works after scrolling away.
app.action("svrTop", () => win.setInt(140, 0, 141));
app.action("svrMiddle", () => win.setInt(140, 0, 146));
app.action("svrBottom", () => win.setInt(140, 0, 152));

// Insertion API: structural mutations against the Collections demo containers.
// Inserted views need positive ids to stay host-addressable (negative ids get no
// data-aui-id), so the demo mints them from a counter and tracks the stack for
// "remove last". insertElement/removeElement/insertRow throw InsertError on a bad
// request; the panel logger surfaces the renderer's own info lines.
let insSeq = 600;
const insertedIds = [];
const insStatus = () => win.setString(210, 0, insertedIds.length
    ? `${insertedIds.length} inserted (last id ${insertedIds[insertedIds.length - 1]}).`
    : "No insertions yet.");

app.action("insAppend", () => {
    const id = insSeq++;
    win.insertElement(200, { type: "Label", id, properties: { title: `Appended item ${id}`, systemImage: "list.bullet" } });
    insertedIds.push(id);
    insStatus();
});
app.action("insPrepend", () => {
    const id = insSeq++;
    win.insertElement(200, { type: "Label", id, properties: { title: `Prepended item ${id}`, systemImage: "arrow.up" } },
        null, InsertPosition.PREPEND);
    insertedIds.push(id);
    insStatus();
});
app.action("insRemoveLast", () => {
    const id = insertedIds.pop();
    if (id === undefined) { win.setString(210, 0, "Nothing inserted to remove (seed rows stay)."); return; }
    win.removeElement(id);
    insStatus();
});
app.action("insAddRow", () => {
    const id = insSeq++;
    win.insertRow(220, [
        { type: "Text", id, properties: { text: `Row ${id}` } },
        { type: "Text", properties: { text: "added at runtime", foregroundColor: "secondary" } },
    ]);
});

// Insertion into the exotic containers (Navigation section): TabView 130 children,
// Menu 170 children, NavigationStack 160 destinations - Apple declares all three
// insertable. Inserted ids are minted from a separate counter.
let navInsSeq = 700;
app.action("insertTab", () => {
    const id = navInsSeq++;
    win.insertElement(130, { type: "Tab", id, properties: { title: `Tab ${id}`, systemImage: "star" },
        content: { type: "Text", properties: { text: `Inserted tab ${id}. Click it in the rail.` } } });
    win.setString(20, 0, `Inserted tab ${id} into the TabView.`);
});
app.action("insertMenuItem", () => {
    const id = navInsSeq++;
    win.insertElement(170, { type: "Button", id, properties: { title: `Item ${id}`, systemImage: "sparkles", actionID: "menuInserted" } });
    win.setString(20, 0, `Inserted menu item ${id} - re-open the Menu to see it.`);
});
app.action("menuInserted", () => win.setString(20, 0, "Menu: inserted item clicked."));
app.action("insertDestination", () => {
    const destId = navInsSeq++;
    const linkId = navInsSeq++;
    // 1) Register the push target in the stack's `destinations` (addressable by id).
    win.insertElement(160, { type: "VStack", id: destId,
        properties: { alignment: "leading", spacing: 6, navigationTitle: `Inserted ${destId}` },
        children: [{ type: "Text", properties: { text: `Destination ${destId} was inserted at runtime, then pushed.`, font: "headline" } }] },
        "destinations");
    // 2) Add a visible Library row that points at it (content VStack id 164), so the
    // destination is reachable after Back - inserting into `destinations` alone only
    // makes a target pushable, it adds no navigation affordance.
    win.insertElement(164, { type: "NavigationLink", id: linkId,
        properties: { title: `Inserted ${destId}`, systemImage: "sparkles", destinationViewId: destId } });
    // 3) Push to the freshly-inserted destination.
    win.setState(160, "navigationPath", [destId]);
    win.setString(20, 0, `Inserted destination ${destId} (Library row + push target) and pushed to it.`);
});

// Toolbar chrome actions: a toolbar Button fires its actionID with { title }.
// The secondaryAction items (Archive / Move / Duplicate) arrive via the overflow menu.
["toolbarEdit", "toolbarCancel", "toolbarDone", "toolbarAdd", "toolbarShare", "toolbarFilter",
 "toolbarArchive", "toolbarMove", "toolbarDuplicate"].forEach((id) => {
    app.action(id, (ctx) => win.setString(20, 0, `Toolbar: ${ctx.context?.title ?? id}.`));
});

// Window-level dialogs: a native top-layer <dialog>. A button with no actionID
// dismisses only; one with an actionID fires it (viewID 0, no context) after the
// dialog closes - the Apple/Android dialog-button convention.
app.action("showAlert", () => {
    win.presentAlert("Saved", "Your changes have been saved.");
});
app.action("showConfirm", () => {
    win.presentConfirmationDialog("Delete file?", "This cannot be undone.", [
        { title: "Delete", role: "destructive", actionID: "confirmDelete" },
        { title: "Cancel", role: "cancel" },
    ]);
});
app.action("confirmDelete", () => win.setString(20, 0, "File deleted."));

// Window-level toast: a transient non-modal snackbar (Scenes/ToastHost.js). The
// signature mirrors the Node adapter: presentToast(message, duration, actionTitle,
// actionId). Pass actionTitle + actionId together for one inline action button that
// fires its actionID (then dismisses); rapid posts queue and show one at a time.
app.action("showToast", () => win.presentToast("All tasks complete"));
app.action("showToastUndo", () => win.presentToast("Completed evening tasks", 5.0, "Undo", "toastUndo"));
app.action("toastUndo", () => win.setString(20, 0, "Undo tapped."));

// Element-level presentation modifiers (Overview): a 'popover'/'sheet'/
// 'fullScreenCover' subview opens off the carrier's state. The dismiss actions
// fire on any close; the "Done"/"Close" buttons close programmatically via
// setElementState, demonstrating host-driven dismissal.
app.action("demoPopoverShown", () => win.setString(20, 0, "Popover shown."));
app.action("demoSheetClose", () => win.setState(301, "sheetVisible", false));
app.action("demoSheetDismissed", () => win.setString(20, 0, "Sheet dismissed."));
app.action("demoCoverClose", () => win.setState(302, "fullScreenCoverVisible", false));
app.action("demoCoverDismissed", () => win.setString(20, 0, "Full screen cover dismissed."));

// Canvas: a tap on a Canvas with an actionID fires it (viewID = canvas id).
app.action("canvasTapped", () => win.setString(20, 0, "Canvas tapped."));

// Map: the value is the center as a JSON coordinate string. setString re-centers
// (the host->view direction works on every provider, including the embed default);
// the embed is display-only, so user pans do NOT report back - load ?maplibre (or
// ?google=YOUR_KEY) to get the full map where a user pan fires `mapMoved`.
app.action("mapRecenter", () => {
    const onApplePark = win.getString(420).includes("37.33");
    const next = onApplePark
        ? '{"latitude":51.5074,"longitude":-0.1278}' // London
        : '{"latitude":37.3349,"longitude":-122.0090}'; // Apple Park
    win.setString(420, 0, next);
    win.setString(20, 0, `Map recentered to ${onApplePark ? "London" : "Apple Park"}.`);
});
app.action("mapMoved", () => win.setString(20, 0, `Map center: ${win.getString(420)}.`));

// GeometryReader: the host reads the container's measured size on demand from
// states["size"] ([width, height], CSS px) - the same getElementState call on
// Apple, Android, and the web. Round for display.
app.action("readGeometrySize", () => {
    const size = win.getState(410, "size");
    if (Array.isArray(size) && size.length === 2) {
        win.setString(20, 0, `GeometryReader size: ${Math.round(size[0])} x ${Math.round(size[1])} px.`);
    } else {
        win.setString(20, 0, "GeometryReader size unavailable.");
    }
});

// Window-level modals (Controls): presentModal loads a JSON sub-document into a
// native <dialog>; its controls bind into the window model by id. The modal's
// Close button routes an actionID the host maps to dismissModal() - the
// Modal.json / cross-platform contract. onDismissActionID fires on any close.
const sheetModal = {
    type: "VStack",
    properties: { alignment: "leading", spacing: 14, padding: "default", frame: { width: 380 } },
    children: [
        { type: "Text", properties: { text: "Sheet Modal", font: "title2" } },
        { type: "Text", properties: { text: "Loaded from a JSON description via presentModal. This field binds into the window model by id.", foregroundColor: "secondary" } },
        { type: "TextField", id: 500, properties: { title: "Note", prompt: "Type something" } },
        { type: "Button", properties: { title: "Close", buttonStyle: "borderedProminent", actionID: "dismissThisModal" } },
    ],
};
const coverModal = {
    type: "VStack",
    properties: { alignment: "center", spacing: 16, padding: "default", frame: { maxWidth: "infinity", maxHeight: "infinity" } },
    children: [
        { type: "Text", properties: { text: "Cover Modal", font: "largeTitle" } },
        { type: "Text", properties: { text: "A full-viewport modal. Press Escape or use the button to dismiss.", foregroundColor: "secondary" } },
        { type: "Button", properties: { title: "Close", systemImage: "xmark", buttonStyle: "borderedProminent", actionID: "dismissThisModal" } },
    ],
};
app.action("showSheetModal", () => win.presentModal(sheetModal, "json", ModalStyle.SHEET, "sheetModalDismissed"));
app.action("showCoverModal", () => win.presentModal(coverModal, "json", ModalStyle.FULL_SCREEN_COVER, "coverModalDismissed"));
app.action("dismissThisModal", () => win.dismissModal());
app.action("sheetModalDismissed", () => win.setString(20, 0, "Sheet modal dismissed."));
app.action("coverModalDismissed", () => win.setString(20, 0, "Cover modal dismissed."));

app.action("increment", () => win.setInt(10, 0, win.getInt(10) + 1));
app.action("decrement", () => win.setInt(10, 0, win.getInt(10) - 1));
app.action("reset", () => {
    win.setInt(10, 0, 0);
    win.setString(20, 0, "Counter reset.");
});

// Log any action that has no dedicated handler.
app.setDefaultHandler((ctx) => {
    console.log(`Unhandled action "${ctx.actionID}" from view ${ctx.viewID}`);
});

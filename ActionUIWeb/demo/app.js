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
// (Views/MapEmbed.js). Add ?maplibre to the URL to LINK the full MapLibre provider
// instead - it registers "Map" last and wins (the pluggable-provider model). Must
// run before present() so the override is registered before the tree is built.
if (new URLSearchParams(location.search).has("maplibre")) {
    await import("../providers/map-maplibre.js");
}

app.presentWindow(win, document.getElementById("root"));

// Open on the Overview section (the LoadableViews all preload as the split's
// destinations; this just selects which one is shown first).
win.setState(1000, "selectedDestination", 1100);

// NavigationSplitView sidebar selection: the sidebar List's actionID fires with no
// context — read the selected destination id from the split view's state.
const SECTION_NAMES = { 1100: "Overview", 1101: "Controls", 1102: "Collections", 1103: "Navigation" };
app.action("sectionSelect", () => {
    const dest = win.getState(1000, "selectedDestination");
    win.setString(20, 0, dest ? `Section: ${SECTION_NAMES[dest] ?? dest}.` : "No section selected.");
});

// The Collections section is data-driven: once its JSON loads, its List/Table
// bindings exist, so push their rows through the rows API (states["content"]).
app.action("collectionsLoaded", () => {
    win.setElementRows(100, [
        ["Budget.xlsx", "tablecells", "Open"],
        ["Photo.jpg", "photo", "Open"],
        ["Notes.txt", "text.document", "Open"],
    ]);
    win.setElementRows(45, [["Low"], ["Medium"], ["High"]]);
    win.setElementRows(55, [["Inbox", "tray"], ["Drafts", "text.document"], ["Sent", "paperplane"]]);
    // LazyVGrid template mode: one substituted instance per row, flowing into the grid.
    win.setElementRows(56, [
        ["Inbox", "tray"], ["Drafts", "text.document"], ["Sent", "paperplane"],
        ["Flagged", "flag"], ["Trash", "trash"], ["Archive", "archivebox"],
    ]);
});

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
["toolbarEdit", "toolbarCancel", "toolbarDone", "toolbarAdd", "toolbarShare", "toolbarFilter"].forEach((id) => {
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
// the embed is display-only, so user pans do NOT report back - load ?maplibre to
// get the full map where a user pan fires `mapMoved` and updates the value.
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

// app.js — demo application logic.
// Exercises the value bridge (get/setString, get/setInt, getBool), the action
// system, and — new — the LoadableView split: the UI is a NavigationSplitView
// shell (ui.json) whose sidebar rows load each section from a separate JSON file
// under demo/sections/. Elements live in those loaded files, so a section's data
// is pushed once it loads (viewDidLoadActionID) rather than up front.

import { Application, Window } from "../src/ActionUI.js";

const app = new Application({ name: "ActionUIWeb Demo" });
const win = await Window.fromURL("./ui.json");
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
    win.setElementRows(55, [["Inbox", "tray"], ["Drafts", "doc"], ["Sent", "paperplane"]]);
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

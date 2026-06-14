// app.js — demo application logic.
// Exercises the value bridge (get/setString, get/setInt, getBool) and the
// action system from JS, mirroring the Node.js/Python adapter examples.

import { Application, Window } from "../src/ActionUI.js";

const app = new Application({ name: "ActionUIWeb Demo" });
const win = await Window.fromURL("./ui.json");
app.presentWindow(win, document.getElementById("root"));

// The Table is data-driven: populate it through the rows API (states["content"]).
win.setElementRows(100, [
    ["Budget.xlsx", "tablecells", "Open"],
    ["Photo.jpg", "photo", "Open"],
    ["Notes.txt", "text.document", "Open"],
]);

// The homogeneous List (itemType Text) is data-driven too — its rows come through
// the same rows API; each row shows its first column.
win.setElementRows(45, [["Low"], ["Medium"], ["High"]]);

// The template List repeats its HStack(Image $2, Text $1) per row: column 1 is the
// label, column 2 the SF Symbol name.
win.setElementRows(55, [["Inbox", "tray"], ["Drafts", "doc"], ["Sent", "paperplane"]]);

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

// NavigationSplitView sidebar selection: the sidebar List's actionID fires with no
// context — read the selected destination id from the split view's state.
app.action("navSelect", () => {
    const dest = win.getState(200, "selectedDestination");
    const names = { 220: "Inbox", 221: "Drafts", 222: "Sent" };
    win.setString(20, 0, dest ? `Section: ${names[dest] ?? dest}.` : "No section selected.");
});

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

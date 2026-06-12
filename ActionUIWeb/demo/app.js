// app.js — demo application logic.
// Exercises the value bridge (get/setString, get/setInt, getBool) and the
// action system from JS, mirroring the Node.js/Python adapter examples.

import { Application, Window } from "../src/ActionUI.js";

const app = new Application({ name: "ActionUIWeb Demo" });
const win = await Window.fromURL("./ui.json");
app.presentWindow(win, document.getElementById("root"));

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

//  TemperatureConverter - ActionUI Example, Level 1 (Web host)
//
//  ActionUIWeb is pure ES modules - no build step, no dependencies. The host
//  does the same three jobs as the Apple/Android hosts: (1) load + present the
//  shared JSON, (2) register handlers, (3) read inputs by id, compute, write
//  the result back by id.
//
//  Paths here are local on purpose: `actionui/` and `TemperatureConverter.json`
//  are symlinks (to ../../../ActionUIWeb and ../shared/...). That keeps this
//  folder self-contained, so package_web_app.sh can resolve the links and emit a
//  standalone copy.

import { Application, Window } from "./actionui/src/ActionUI.js";

const app = new Application({ name: "Temperature Converter" });

// (1) Load the shared JSON and mount it into #root.
const win = await Window.fromURL("./TemperatureConverter.json");
app.presentWindow(win, document.getElementById("root"));

// (2) One handler for the whole screen - the field's valueChangeActionID and
// both Pickers' actionID all fire "temp.recompute".
app.action("temp.recompute", recompute);

// (3) Read the field text and each Picker's selected tag ("C"/"F"/"K"), convert, write result.
function recompute() {
  const raw  = win.getString(10);          // TextField
  const from = win.getString(20) || "C";   // Picker -> selected tag
  const to   = win.getString(30) || "F";

  const n = parseFloat(String(raw).trim());
  if (Number.isNaN(n)) {                    // blank / not a number -> blank result
    win.setString(40, 0, "");
    return;
  }
  // The result shows just the number; its unit is the adjacent "To" picker.
  win.setString(40, 0, convert(n, from, to).toFixed(2));
}

// Convert through Celsius as the common pivot.
function convert(value, from, to) {
  const celsius =
    from === "F" ? (value - 32) * 5 / 9 :
    from === "K" ? value - 273.15 :
    value;                                  // "C"
  return (
    to === "F" ? celsius * 9 / 5 + 32 :
    to === "K" ? celsius + 273.15 :
    celsius                                 // "C"
  );
}

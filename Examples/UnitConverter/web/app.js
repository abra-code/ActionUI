//  UnitConverter - ActionUI Example, Web host (shared-C edition).
//
//  ActionUIWeb is pure ES modules - no build step. The host does the same three
//  jobs as the Apple/Android hosts: (1) load + present the shared JSON, (2)
//  register handlers, (3) read inputs by id, compute, write the result by id.
//
//  The conversion math is NOT inline here: it comes from convert.js, a faithful
//  JS port of shared/c/convert.c (the same file Apple/Android compile natively).
//  Keeping the math in its own module mirrors the native "one shared brain" shape
//  and keeps this host as thin as the others.
//
//  Paths here are local on purpose: `actionui/` and `UnitConverter.json` are
//  symlinks (to ../../../ActionUIWeb and ../shared/...), so package_web_app.sh can
//  resolve them into a standalone copy. convert.js is a real local file.

import { Application, Window } from "./actionui/src/ActionUI.js";
import { auiConvert } from "./convert.js";

const app = new Application({ name: "Unit Converter" });

// (2) Two actionIDs: "unit.recompute" (amount field + both unit pickers) and
// "unit.category" (the segmented category picker; also repopulates the unit menus
// and applies the category's default from/to pair). Registered before present so
// the category picker's onAppearActionID (which fires unit.category once on mount
// to seed the initial category's defaults) finds its handler.
app.action("unit.recompute", recompute);
app.action("unit.category", categoryChanged);

// (1) Load the shared JSON and mount it into #root.
const win = await Window.fromURL("./UnitConverter.json");
app.presentWindow(win, document.getElementById("root"));

// MARK: - Tag <-> C-enum mapping
//
// from/to tags are "L0".."L5" (length), "M0".."M3" (mass), "T0".."T2" (temp).
// Leading letter = category, trailing integer = unit index within the category,
// exactly the enum values in shared/c/convert.h.

function categoryIndex(tag) {
  switch (tag[0]) {
    case "L": return 0; // AUI_CAT_LENGTH
    case "M": return 1; // AUI_CAT_MASS
    case "T": return 2; // AUI_CAT_TEMPERATURE
    default:  return null;
  }
}

function unitIndex(tag) {
  if (!tag || tag.length < 2) return null;
  const n = parseInt(tag.slice(1), 10);
  return Number.isNaN(n) ? null : n;
}

// Each category opens on a sensible, non-trivial conversion rather than unit->same
// unit: meter->foot, kilogram->pound, Celsius->Fahrenheit. categoryChanged applies
// this pair on every switch, and the category picker's onAppearActionID fires
// categoryChanged once on mount to apply the initial (length) pair too.
function defaultTags(category) {
  switch (category) {
    case "mass":        return { from: "M0", to: "M2" }; // kilogram -> pound
    case "temperature": return { from: "T0", to: "T1" }; // Celsius -> Fahrenheit
    default:            return { from: "L0", to: "L4" }; // meter -> foot ("length")
  }
}

// The from/to unit menus are populated per category, so a conversion is always
// within one category (no nonsensical length->temperature). Tags mirror the enum
// indices in shared/c/convert.h. categoryChanged swaps both menus to this list.
function unitOptions(category) {
  switch (category) {
    case "mass":
      return [
        { title: "kilogram", tag: "M0" },
        { title: "gram", tag: "M1" },
        { title: "pound", tag: "M2" },
        { title: "ounce", tag: "M3" },
      ];
    case "temperature":
      return [
        { title: "Celsius", tag: "T0" },
        { title: "Fahrenheit", tag: "T1" },
        { title: "Kelvin", tag: "T2" },
      ];
    default: // "length"
      return [
        { title: "meter", tag: "L0" },
        { title: "centimeter", tag: "L1" },
        { title: "kilometer", tag: "L2" },
        { title: "inch", tag: "L3" },
        { title: "foot", tag: "L4" },
        { title: "mile", tag: "L5" },
      ];
  }
}

// (3) Read inputs, call the shared-math port, write the result.
function recompute() {
  const raw = win.getString(10);          // TextField
  const fromTag = win.getString(20) || "L0";
  const toTag = win.getString(30) || "L0";

  const n = parseFloat(String(raw).trim());
  if (Number.isNaN(n)) {                    // blank / not a number -> blank result
    win.setString(40, 0, "");
    return;
  }
  const cat = categoryIndex(fromTag);
  if (cat === null || categoryIndex(toTag) !== cat) {
    win.setString(40, 0, "-");             // cross-category: not convertible
    return;
  }
  const out = auiConvert(cat, unitIndex(fromTag), unitIndex(toTag), n);
  win.setString(40, 0, trimmed(out));
}

// On category change (and once on mount, via the picker's onAppearActionID):
// repopulate both unit menus with only that category's units (setElementProperty
// "options"), then select the category's default from/to pair, then recompute.
// Setting options before the values keeps the new selection inside the fresh list.
// Writing a Picker's options/tag is portable across hosts.
function categoryChanged() {
  const category = win.getString(5) || "length";
  const options = unitOptions(category);
  win.setElementProperty(20, "options", options);
  win.setElementProperty(30, "options", options);
  const { from, to } = defaultTags(category);
  win.setString(20, 0, from);
  win.setString(30, 0, to);
  recompute();
}

// Tidy number: integers print whole; otherwise cap at 2 decimals (enough for a
// readable result, and short enough that the result field never wraps and grows).
function trimmed(value) {
  if (value === Math.round(value) && Math.abs(value) < 1e15) {
    return String(value);
  }
  let s = value.toFixed(2);
  s = s.replace(/0+$/, "").replace(/\.$/, "");
  return s;
}

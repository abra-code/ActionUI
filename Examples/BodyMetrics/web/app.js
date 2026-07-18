//  BodyMetrics (BMI) - ActionUI Example, Level 1 (Web host)
//
//  ActionUIWeb is pure ES modules - no build step, no dependencies. The host
//  does the same three jobs as the Apple/Android hosts: (1) load + present the
//  shared JSON, (2) register the one actionID the inputs fire ("bmi.recompute"),
//  (3) read inputs by integer id, compute, write outputs (values + colors) by id.
//
//  Slider values are always stored in metric (cm, kg) regardless of the toggle;
//  the toggle only changes how the read-out labels are formatted (ft/in, lb).
//  BMI is unit-agnostic, computed from the metric values. The category color is
//  pushed with setElementProperty(id, "foregroundStyle", colorName) onto the
//  Gauge and the category Text.
//
//  id map (keep in sync with shared/BodyMetrics.json):
//    10  Toggle  imperial units on/off (fires actionID)
//    20  Slider  height, 100-220 cm    (fires valueChangeActionID)
//    21  Text    height read-out
//    30  Slider  weight, 30-200 kg     (fires valueChangeActionID)
//    31  Text    weight read-out
//    40  Gauge   BMI 10-40 (value + foregroundStyle set at runtime)
//    50  Text    BMI numeric
//    60  Text    category (foregroundStyle set at runtime)
//
//  Paths here are local on purpose: `actionui/` and `BodyMetrics.json` are
//  symlinks (to ../../../ActionUIWeb and ../shared/...). That keeps this folder
//  self-contained, so package_web_app.sh can resolve the links and emit a
//  standalone copy.

import { Application, Window } from "./actionui/src/ActionUI.js";

const app = new Application({ name: "Body Metrics" });

// (1) Load the shared JSON and mount it into #root.
const win = await Window.fromURL("./BodyMetrics.json");
app.presentWindow(win, document.getElementById("root"));

// Element ids (keep in sync with shared/BodyMetrics.json).
const IMPERIAL = 10;
const HEIGHT_SLIDER = 20;
const HEIGHT_LABEL = 21;
const WEIGHT_SLIDER = 30;
const WEIGHT_LABEL = 31;
const GAUGE = 40;
const BMI_TEXT = 50;
const CATEGORY = 60;

function clamp(v, lo, hi) {
  return Math.min(Math.max(v, lo), hi);
}

// Map BMI to a [label, color-name] pair. Named colors resolve on all platforms.
function category(bmi) {
  if (bmi < 18.5) return ["Underweight", "cyan"];
  if (bmi < 25.0) return ["Normal", "green"];
  if (bmi < 30.0) return ["Overweight", "orange"];
  return ["Obese", "red"];
}

function formatHeight(cm, imperial) {
  if (!imperial) return Math.round(cm) + " cm";
  const totalInches = cm / 2.54;
  let feet = Math.floor(totalInches / 12);
  let inches = Math.round(totalInches - feet * 12);
  if (inches === 12) { feet += 1; inches = 0; }
  return feet + " ft " + inches + " in";
}

function formatWeight(kg, imperial) {
  if (!imperial) return Math.round(kg) + " kg";
  return Math.round(kg * 2.2046226218) + " lb";
}

// (3) Read inputs by id, compute, write outputs by id.
function recompute() {
  // Toggle returns a bool string; Sliders return their numeric value as a string.
  const imperial = String(win.getString(IMPERIAL)).trim().toLowerCase() === "true";
  const cm = parseFloat(win.getString(HEIGHT_SLIDER)) || 170;
  const kg = parseFloat(win.getString(WEIGHT_SLIDER)) || 70;

  // BMI = kg / m^2 (unit-agnostic; always from the metric slider values).
  const meters = cm / 100;
  const bmi = meters > 0 ? kg / (meters * meters) : 0;

  // Unit-aware read-out labels.
  win.setString(HEIGHT_LABEL, 0, formatHeight(cm, imperial));
  win.setString(WEIGHT_LABEL, 0, formatWeight(kg, imperial));

  // Gauge value tracks BMI; clamp into the gauge's 10-40 range.
  win.setString(GAUGE, 0, String(clamp(bmi, 10, 40)));

  // BMI numeric text.
  win.setString(BMI_TEXT, 0, bmi.toFixed(1));

  // Category name + matching color, applied to both the Gauge and the category Text.
  // Gauge capacity styles also honor `tint`; set both so the ring tracks the zone color.
  const [name, color] = category(bmi);
  win.setString(CATEGORY, 0, name);
  win.setElementProperty(CATEGORY, "foregroundStyle", color);
  win.setElementProperty(GAUGE, "foregroundStyle", color);
  win.setElementProperty(GAUGE, "tint", color);
}

// (2) One handler for every input (Toggle fires actionID, both Sliders fire
// valueChangeActionID; all share "bmi.recompute"). Web handlers take no args;
// read state off `win` inside.
app.action("bmi.recompute", recompute);

// Seed the outputs from the JSON's initial input values.
recompute();

//  TipBillSplitter - ActionUI Example (Web host)
//
//  ActionUIWeb is pure ES modules - no build step, no dependencies. The host
//  does the same three jobs as the Apple/Android hosts: (1) load + present the
//  shared JSON, (2) register a handler for the one actionID the inputs fire
//  ("tip.recompute"), (3) read inputs by integer id, compute, and write the
//  three result Texts back by id.
//
//  The id map matches shared/TipBillSplitter.json exactly:
//    10  TextField  bill amount (currency-formatted, fires valueChangeActionID)
//    20  Slider     tip %, 0-30 step 1 (fires valueChangeActionID)
//    30  Stepper    party size, 1-20 step 1 (fires actionID)
//    40  Text       tip amount   (output)
//    50  Text       total        (output)
//    60  Text       per person   (output)
//    80  Text       "Tip: N%"    (output, slider read-out)
//
//  Paths here are local on purpose: `actionui/` and `TipBillSplitter.json` are
//  symlinks (to ../../../ActionUIWeb and ../shared/...). That keeps this folder
//  self-contained, so package_web_app.sh can resolve the links and emit a
//  standalone copy.

import { Application, Window } from "./actionui/src/ActionUI.js";

const app = new Application({ name: "Tip & Bill Splitter" });

// (1) Load the shared JSON and mount it into #root.
const win = await Window.fromURL("./TipBillSplitter.json");
app.presentWindow(win, document.getElementById("root"));

// Element ids (keep in sync with shared/TipBillSplitter.json).
const BILL_FIELD = 10;
const TIP_SLIDER = 20;
const PARTY_STEPPER = 30;
const TIP_OUT = 40;
const TOTAL_OUT = 50;
const PER_PERSON_OUT = 60;
const TIP_LABEL = 80;

// Pull a Number out of whatever string the currency field hands back ("$", commas).
function parseAmount(raw) {
  const filtered = String(raw).replace(/[^0-9.]/g, "");
  const n = parseFloat(filtered);
  return Number.isNaN(n) ? 0 : n;
}

function currency(value) {
  const v = Number.isFinite(value) ? value : 0;
  return "$" + v.toFixed(2);
}

// (3) The recompute. Identical to the Apple/Android hosts. Read inputs by id,
// compute, write the result Texts by id.
function recompute() {
  const bill = parseAmount(win.getString(BILL_FIELD));
  const pct = parseFloat(win.getString(TIP_SLIDER)) || 0;
  const peopleRaw = parseFloat(win.getString(PARTY_STEPPER)) || 1;
  const people = Math.max(1, Math.round(peopleRaw));

  const tip = (bill * pct) / 100;
  const total = bill + tip;
  const perPerson = total / people;

  win.setString(TIP_OUT, 0, currency(tip));
  win.setString(TOTAL_OUT, 0, currency(total));
  win.setString(PER_PERSON_OUT, 0, currency(perPerson));

  // Mirror the tip % into the read-out label.
  win.setString(TIP_LABEL, 0, "Tip: " + Math.round(pct) + "%");
}

// (2) One handler for every input (TextField + Slider fire valueChangeActionID,
// Stepper fires actionID; all share "tip.recompute"). Web handlers take no args;
// read state off `win` inside.
app.action("tip.recompute", recompute);

// Seed the outputs from the JSON's initial input values.
recompute();

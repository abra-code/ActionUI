// Tests for DatePicker `displayedComponents` value-format conversions
// (src/Views/DatePicker.js __test__ helpers). Pins the wire-format rule:
//   "date"          -> "YYYY-MM-DD"
//   "hourAndMinute" -> full ISO datetime "YYYY-MM-DDTHH:mm:ss" (today + time)
//   "dateAndTime"   -> full ISO datetime "YYYY-MM-DDTHH:mm:ss"
// and the native <input> value <-> wire conversions in both directions.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom } from "./dom-stub.mjs";

installDom();
const { __test__ } = await import("../src/Views/DatePicker.js");
const { resolveComponents, inputTypeFor, toWireValue, wireToInput, inputToWire } = __test__;

const todayDate = () => {
    const n = new Date();
    const p = (x) => String(x).padStart(2, "0");
    return `${n.getFullYear()}-${p(n.getMonth() + 1)}-${p(n.getDate())}`;
};

test("resolveComponents maps known modes and defaults unknown/absent to date", () => {
    assert.equal(resolveComponents("date"), "date");
    assert.equal(resolveComponents("hourAndMinute"), "hourAndMinute");
    assert.equal(resolveComponents("dateAndTime"), "dateAndTime");
    assert.equal(resolveComponents(undefined), "date");
    assert.equal(resolveComponents("wheel"), "date");
});

test("inputTypeFor maps each mode to a native input type", () => {
    assert.equal(inputTypeFor("date"), "date");
    assert.equal(inputTypeFor("hourAndMinute"), "time");
    assert.equal(inputTypeFor("dateAndTime"), "datetime-local");
});

test("date mode keeps the wire value as YYYY-MM-DD", () => {
    assert.equal(toWireValue("2024-07-16", "date"), "2024-07-16");
    // A full datetime input is reduced to its date.
    assert.equal(toWireValue("2024-07-16T14:30:00", "date"), "2024-07-16");
    assert.equal(wireToInput("2024-07-16", "date"), "2024-07-16");
    assert.equal(inputToWire("2024-07-16", "date"), "2024-07-16");
});

test("hourAndMinute mode emits a full ISO datetime with today's date", () => {
    // A time-only input gets today's date and seconds zero-filled.
    assert.equal(toWireValue("14:30", "hourAndMinute"), `${todayDate()}T14:30:00`);
    // A full datetime input keeps its time, full ISO out.
    assert.equal(toWireValue("2024-07-16T09:05:00", "hourAndMinute"), "2024-07-16T09:05:00");
    // wire -> native time input is HH:mm.
    assert.equal(wireToInput("2024-07-16T09:05:00", "hourAndMinute"), "09:05");
    // native time input -> wire seeds today's date.
    assert.equal(inputToWire("09:05", "hourAndMinute"), `${todayDate()}T09:05:00`);
});

test("dateAndTime mode emits a full ISO datetime", () => {
    assert.equal(toWireValue("2024-07-16T14:30:00", "dateAndTime"), "2024-07-16T14:30:00");
    // A date-only input gets midnight.
    assert.equal(toWireValue("2024-07-16", "dateAndTime"), "2024-07-16T00:00:00");
    // wire -> native datetime-local is YYYY-MM-DDTHH:mm (no seconds).
    assert.equal(wireToInput("2024-07-16T14:30:00", "dateAndTime"), "2024-07-16T14:30");
    // native datetime-local -> full ISO wire with seconds.
    assert.equal(inputToWire("2024-07-16T14:30", "dateAndTime"), "2024-07-16T14:30:00");
});

test("unparseable input yields empty string", () => {
    assert.equal(toWireValue("not-a-date", "date"), "");
    assert.equal(toWireValue("", "dateAndTime"), "");
    assert.equal(wireToInput("nope", "hourAndMinute"), "");
});

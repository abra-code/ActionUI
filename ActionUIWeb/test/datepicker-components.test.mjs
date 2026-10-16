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

// Zone designators: a zoned datetime is an instant, shown in the browser's zone;
// an offset-less one is wall-clock time. Expected values are computed from the
// instant's local fields, so the assertions hold in any zone; run the suite under
// a non-UTC TZ (e.g. TZ=Asia/Tokyo) for them to tell the two rules apart.
const localWire = (ms) => {
    const n = new Date(ms);
    const p = (x) => String(x).padStart(2, "0");
    return `${n.getFullYear()}-${p(n.getMonth() + 1)}-${p(n.getDate())}T${p(n.getHours())}:${p(n.getMinutes())}:${p(n.getSeconds())}`;
};
const instant1430Z = Date.UTC(2024, 6, 16, 14, 30, 0);

test("a zoned datetime is an instant converted to the local zone", () => {
    assert.equal(toWireValue("2024-07-16T14:30:00Z", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T16:30:00+02:00", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T09:30:00-05:00", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T16:30:00+0200", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T14:30:00.250z", "dateAndTime"), localWire(instant1430Z));
    // The other forms Apple and Android accept: "+hh", no seconds, other fraction lengths.
    assert.equal(toWireValue("2024-07-16T16:30:00+02", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T14:30Z", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T14:30:00.123456Z", "dateAndTime"), localWire(instant1430Z));
    assert.equal(toWireValue("2024-07-16T14:30:00+02:00 junk", "dateAndTime"), "");
});

test("date mode shows the local day of a zoned instant", () => {
    const midnightZ = Date.UTC(2024, 6, 16, 0, 0, 0);
    assert.equal(toWireValue("2024-07-16T00:00:00Z", "date"), localWire(midnightZ).slice(0, 10));
});

test("an offset-less datetime stays wall-clock time", () => {
    assert.equal(toWireValue("2024-07-16T09:05:00", "dateAndTime"), "2024-07-16T09:05:00");
    assert.equal(toWireValue("2024-07-16T09:05", "dateAndTime"), "2024-07-16T09:05:00");
    assert.equal(toWireValue("2024-07-16T09:05:00.5", "dateAndTime"), "2024-07-16T09:05:00");
});

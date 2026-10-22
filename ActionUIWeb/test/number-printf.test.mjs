// Tests for NumberPrintf (src/Helpers/NumberPrintf.js) against the labelFormat parity cases every
// renderer checks (FormatParity/labelformat-cases.json at the repository root, recorded from the C
// library on a Mac), and for the Stepper label built on it (src/Views/Stepper.js).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { installDom, makeLogger } from "./dom-stub.mjs";
import { formatNumber, plainNumber } from "../src/Helpers/NumberPrintf.js";

const cases = JSON.parse(readFileSync(new URL("../../FormatParity/labelformat-cases.json", import.meta.url), "utf8"));

// A number, or one JSON cannot write: "inf", "-inf", "nan", "-0".
function value(item) {
    if (typeof item.value === "number") return item.value;
    return { "inf": Infinity, "-inf": -Infinity, "-0": -0 }[item.value] ?? NaN;
}

test("every case gives its expected text", () => {
    for (const item of cases.cases) {
        assert.equal(formatNumber(item.format, value(item), item.decimalSeparator ?? "."), item.expected,
            `${item.format} with ${item.value}`);
    }
});

test("the plain value is %g with the separator", () => {
    for (const item of cases.plain) {
        assert.equal(plainNumber(value(item), item.decimalSeparator ?? "."), item.expected, `plain ${item.value}`);
    }
});

let stepperLabel;

before(async () => {
    installDom();
    ({ stepperLabel } = await import("../src/Views/Stepper.js"));
});

test("Stepper label: one number format, else the plain value, logged once per format", () => {
    const logger = makeLogger();
    assert.equal(stepperLabel("Count: %d", 5.9, logger, "."), "Count: 5");
    assert.equal(stepperLabel("Rating: %.1f", 2.5, logger, ","), "Rating: 2,5", "with the system's decimal separator");
    assert.equal(stepperLabel("%f of %f (number-printf test)", 2.5, logger, "."), "2.5");
    assert.equal(stepperLabel("%f of %f (number-printf test)", 2.5, logger, "."), "2.5");
    assert.equal(logger.messages.filter((m) => m.level === "warning" && m.message.includes("labelFormat")).length, 1);
});

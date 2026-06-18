// Tests for the View constructions' validateProperties (src/Views/*.js).
// A smoke sweep over every registered type, plus targeted rule checks for the
// validators with real normalization/warning logic.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const ALL_TYPES = [
    "AsyncImage", "Button", "Canvas", "Capsule", "Circle", "ColorPicker", "ContentUnavailableView",
    "DatePicker", "DisclosureGroup", "Divider", "Ellipse", "EmptyView", "Form", "Gauge",
    "GeometryReader", "Grid", "Group", "GroupBox", "HStack", "Image", "Label", "LabeledContent",
    "LazyHGrid", "LazyHStack", "LazyVGrid", "LazyVStack", "Link", "List", "LoadableView", "Map",
    "Menu", "NavigationLink", "NavigationSplitView", "NavigationStack", "Picker", "ProgressView",
    "Rectangle", "RoundedRectangle", "ScrollView", "ScrollViewReader", "Section", "SecureField",
    "ShareLink", "Slider", "Spacer", "Stepper", "Tab", "Table", "TabView", "Text", "TextEditor",
    "TextField", "Toggle", "VideoPlayer", "VStack", "WebView", "ZStack",
];

const validate = (type, props) => getConstruction(type).validateProperties(props, makeLogger());

test("every type is registered with a callable validateProperties", () => {
    for (const type of ALL_TYPES) {
        const c = getConstruction(type);
        assert.ok(c, `${type} is registered`);
        assert.equal(typeof c.validateProperties, "function", `${type} has validateProperties`);
    }
});

test("validateProperties returns an object and never throws on empty/garbage input", () => {
    for (const type of ALL_TYPES) {
        assert.doesNotThrow(() => validate(type, {}), `${type} validateProperties({}) does not throw`);
        const out = validate(type, {});
        assert.equal(typeof out, "object", `${type} returns an object`);
        assert.doesNotThrow(() => validate(type, { text: 5, value: "x", style: 9, options: 1, range: "z" }),
            `${type} tolerates wrong-typed props`);
    }
});

test("validators pass unknown and base modifier properties through unchanged", () => {
    for (const type of ALL_TYPES) {
        const out = validate(type, { padding: 8, opacity: 0.5, customKey: "keep" });
        assert.equal(out.padding, 8, `${type} keeps padding`);
        assert.equal(out.opacity, 0.5, `${type} keeps opacity`);
        assert.equal(out.customKey, "keep", `${type} keeps unknown keys`);
    }
});

// ---------------- targeted rule checks ----------------

test("Slider: value/range/step normalization", () => {
    assert.equal(validate("Slider", {}).value, 0.0, "absent value -> 0");
    assert.equal(validate("Slider", { value: "x" }).value, 0.0, "non-number value -> 0");
    assert.deepEqual(validate("Slider", { range: { min: 0, max: 10 } }).range, { min: 0, max: 10 });
    assert.deepEqual(validate("Slider", { range: { min: 5, max: 1 } }).range, { min: 0, max: 1 }, "min>max -> default range");
});

test("Toggle: isOn must be boolean; invalid style dropped", () => {
    assert.equal(validate("Toggle", { isOn: "yes" }).isOn, undefined, "non-bool isOn dropped");
    assert.equal(validate("Toggle", { isOn: true }).isOn, true);
    assert.equal(validate("Toggle", { style: "nonsense" }).style, undefined, "invalid style dropped");
});

test("ProgressView: value non-negative, total positive", () => {
    assert.equal(validate("ProgressView", { value: -1 }).value, undefined);
    assert.equal(validate("ProgressView", { value: 0.5 }).value, 0.5);
    assert.equal(validate("ProgressView", { total: 0 }).total, undefined, "non-positive total dropped");
    assert.equal(validate("ProgressView", { title: 5 }).title, undefined);
});

test("Image: invalid contentMode dropped; string image keys enforced", () => {
    assert.equal(validate("Image", { contentMode: "diagonal" }).contentMode, undefined);
    assert.equal(validate("Image", { systemName: 5 }).systemName, undefined, "non-string image name dropped");
});

test("Link: title/url must be strings", () => {
    assert.equal(validate("Link", { title: 5 }).title, undefined);
    assert.equal(validate("Link", { url: 7 }).url, undefined);
    assert.equal(validate("Link", { title: "Site", url: "https://x" }).url, "https://x");
});

test("Stepper: value defaults; invalid range dropped", () => {
    assert.equal(validate("Stepper", { value: "x" }).value, 0.0);
    assert.equal(validate("Stepper", { range: { min: 9, max: 1 } }).range, undefined, "min>max range dropped");
    assert.deepEqual(validate("Stepper", { range: { min: 0, max: 5 } }).range, { min: 0, max: 5 });
});

test("Picker: invalid options/style/title dropped", () => {
    assert.equal(validate("Picker", { options: 5 }).options, undefined);
    assert.deepEqual(validate("Picker", { options: ["a", "b"] }).options, ["a", "b"]);
    assert.equal(validate("Picker", { pickerStyle: "nope" }).pickerStyle, undefined);
    assert.equal(validate("Picker", { title: 5 }).title, undefined);
});

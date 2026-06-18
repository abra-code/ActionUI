// Tests for pure-logic Helpers: LoadableSource, MaterialSymbolResolver,
// SymbolIcon (axes), TemplateHelper (substitution), MapContract (coordinates),
// ShapeStyleHelper (paint).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeElement, makeLogger } from "./dom-stub.mjs";
import { resolveLoadableSource, classifyLoadableSource } from "../src/Helpers/LoadableSource.js";
import { parseSystemSymbolMap, MATERIAL_WEIGHT_MIN, MATERIAL_WEIGHT_MAX } from "../src/Helpers/MaterialSymbolResolver.js";
import { symbolFill, symbolWeight } from "../src/Helpers/SymbolIcon.js";
import { substituteString, substituteElement } from "../src/Helpers/TemplateHelper.js";
import {
    parseCoordinate, coordinateToValueString, parseCoordinateValueString, coordinatesEqual,
} from "../src/Helpers/MapContract.js";
import { resolveShapePaint, applyShapePaint } from "../src/Helpers/ShapeStyleHelper.js";

// ---------------- LoadableSource ----------------

test("resolveLoadableSource: explicit value wins, then url/filePath/name", () => {
    assert.equal(resolveLoadableSource("direct", { url: "u" }), "direct");
    assert.equal(resolveLoadableSource("  ", { url: "u" }), "u");
    assert.equal(resolveLoadableSource(null, { filePath: "/p" }), "/p");
    assert.equal(resolveLoadableSource(null, { name: "n" }), "n");
    assert.equal(resolveLoadableSource(null, {}), null);
});

test("classifyLoadableSource: remote / filePath / bundle, with format", () => {
    assert.deepEqual(classifyLoadableSource("https://x/y.json"), { kind: "remote", fetchURL: "https://x/y.json", format: "json" });
    assert.equal(classifyLoadableSource("file:///a/b.json").kind, "filePath");
    assert.equal(classifyLoadableSource("file:///a/b.json").fetchURL, "/a/b.json");
    assert.equal(classifyLoadableSource("dir/file.json").kind, "filePath");
    const bundle = classifyLoadableSource("Section");
    assert.equal(bundle.kind, "bundle");
    assert.equal(bundle.fetchURL, "Section.json", "a bare name gets .json appended");
    assert.equal(classifyLoadableSource("").kind, "none");
});

// ---------------- MaterialSymbolResolver ----------------

test("parseSystemSymbolMap: codepoints, fill, weight; skips comments/blanks", () => {
    const text = [
        "# comment", "",
        "search e8b6",
        "filled e1bb 1 600",
        "weird e000 9999",     // out-of-range weight ignored
        "bad notHex 1",        // non-hex codepoint skipped
    ].join("\n");
    const map = parseSystemSymbolMap(text);
    assert.equal(map.get("search").codepoint, 0xe8b6);
    assert.equal(map.get("search").fill, false);
    assert.equal(map.get("filled").fill, true);
    assert.equal(map.get("filled").weight, 600);
    assert.equal(map.get("weird").weight, null, "out-of-range weight ignored");
    assert.equal(map.has("bad"), false, "non-hex codepoint row skipped");
});

// ---------------- SymbolIcon axes ----------------

test("symbolFill / symbolWeight honor explicit overrides within range", () => {
    assert.equal(symbolFill({ materialFill: true }, false), true);
    assert.equal(symbolFill({ materialFill: 1 }, false), true);
    assert.equal(symbolFill({ materialFill: 0 }, true), false);
    assert.equal(symbolFill({}, "fb"), "fb", "fallback when absent");
    assert.equal(symbolWeight({ materialWeight: 500 }, 400), 500);
    assert.equal(symbolWeight({ materialWeight: 9999 }, 400), 400, "out-of-range falls back");
    assert.equal(symbolWeight({}, 400), 400);
    assert.ok(MATERIAL_WEIGHT_MIN < MATERIAL_WEIGHT_MAX);
});

// ---------------- TemplateHelper substitution ----------------

test("substituteString: $1-based columns, $0 join, out-of-range kept", () => {
    assert.equal(substituteString("$1", ["a", "b"]), "a");
    assert.equal(substituteString("$2 of $1", ["a", "b"]), "b of a");
    assert.equal(substituteString("$0", ["a", "b"]), "a, b");
    assert.equal(substituteString("$9", ["a"]), "$9", "out-of-range reference left untouched");
});

test("substituteElement substitutes string properties and recurses subviews", () => {
    const proto = {
        type: "HStack",
        subviews: { children: [{ type: "Text", properties: { text: "$1" } }, { type: "Image", properties: { systemName: "$2" } }] },
    };
    const out = substituteElement(proto, ["Inbox", "tray"]);
    assert.equal(out.type, "HStack");
    assert.equal(out.subviews.children[0].properties.text, "Inbox");
    assert.equal(out.subviews.children[1].properties.systemName, "tray");
});

// ---------------- MapContract coordinates ----------------

test("parseCoordinate validates lat/long numbers", () => {
    assert.deepEqual(parseCoordinate({ latitude: 1.5, longitude: -2.5 }), { latitude: 1.5, longitude: -2.5 });
    assert.equal(parseCoordinate({ latitude: "x", longitude: 0 }), null);
    assert.equal(parseCoordinate(null), null);
    assert.equal(parseCoordinate([1, 2]), null);
});

test("coordinate value-string round-trips; equality and bad strings", () => {
    const c = { latitude: 10, longitude: 20 };
    const s = coordinateToValueString(c);
    assert.deepEqual(parseCoordinateValueString(s), c);
    assert.equal(parseCoordinateValueString("not json"), null);
    assert.ok(coordinatesEqual(c, { latitude: 10, longitude: 20 }));
    assert.equal(coordinatesEqual(c, { latitude: 10, longitude: 21 }), false);
    assert.equal(coordinatesEqual(null, null), true);
});

// ---------------- ShapeStyleHelper ----------------

test("resolveShapePaint: fill wins, invalid fill -> stroke, default currentColor", () => {
    const logger = makeLogger();
    assert.deepEqual(resolveShapePaint({ fill: "#ff0000" }, logger), { color: "#ff0000", strokeWidth: null });
    assert.deepEqual(resolveShapePaint({ stroke: "#00ff00", strokeLineWidth: 2 }, logger), { color: "#00ff00", strokeWidth: 2 });
    assert.deepEqual(resolveShapePaint({}, logger), { color: "currentColor", strokeWidth: null });
    // present-but-unresolvable fill falls through to stroke
    const fellThrough = resolveShapePaint({ fill: "notacolor", stroke: "#0000ff" }, makeLogger());
    assert.equal(fellThrough.color, "#0000ff");
});

test("applyShapePaint: fill -> background, stroke -> border", () => {
    const a = makeElement();
    applyShapePaint(a, { color: "#abc", strokeWidth: null });
    assert.equal(a.style.backgroundColor, "#abc");
    const b = makeElement();
    applyShapePaint(b, { color: "#def", strokeWidth: 3 });
    assert.equal(b.style.border, "3px solid #def");
});

// Tests for the engine-core pure logic in src/Common/:
//   PlatformFilter, StackAxis, ActionUIInsertion (resolvers + errors), Debug.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { PlatformFilter } from "../src/Common/PlatformFilter.js";
import { StackAxis, COLUMN_ALIGN, ROW_ALIGN, DEFAULT_SPACING, nearestStackAxis } from "../src/Common/StackAxis.js";
import {
    InsertPosition, ContainerShape, InsertError,
    resolveContainer, resolveFlatIndex, resolveRowIndex, collectElementIds,
} from "../src/Common/ActionUIInsertion.js";
import { setDebugMode, isDebugMode } from "../src/Common/Debug.js";

// ---------------- PlatformFilter ----------------

test("PlatformFilter keeps the web variant and drops other platforms", () => {
    const out = PlatformFilter.WEB.filter({ font: "title", "font:web": "largeTitle", "font:android": "x" });
    assert.equal(out.font, "largeTitle", "web suffix wins over the unsuffixed base");
    assert.equal(Object.keys(out).length, 1);
});

test("PlatformFilter keeps the unsuffixed base when no active variant exists", () => {
    const out = PlatformFilter.WEB.filter({ "color:android": "red", color: "blue" });
    assert.equal(out.color, "blue");
});

test("PlatformFilter recurses into nested objects and arrays", () => {
    const out = PlatformFilter.WEB.filter({ a: { "x:web": 1, "x:ios": 2 }, kids: [{ "y:web": 3 }] });
    assert.equal(out.a.x, 1);
    assert.equal(out.kids[0].y, 3);
});

test("PlatformFilter warns and drops an unknown suffix", () => {
    const logger = makeLogger();
    const out = PlatformFilter.WEB.withLogger(logger).filter({ "tint:Web": "x" });
    assert.equal(Object.keys(out).length, 0, "unknown suffix dropped");
    assert.ok(logger.warned("Unknown platform suffix"));
});

test("PlatformFilter ALL_PLATFORMS includes web and the apple/android tokens", () => {
    for (const p of ["web", "ios", "macos", "apple", "android"]) {
        assert.ok(PlatformFilter.ALL_PLATFORMS.has(p), `${p} is a known platform`);
    }
});

// ---------------- StackAxis ----------------

test("StackAxis vocabulary + alignment maps", () => {
    assert.equal(StackAxis.Vertical, "vertical");
    assert.equal(COLUMN_ALIGN.leading, "flex-start");
    assert.equal(COLUMN_ALIGN.trailing, "flex-end");
    assert.equal(ROW_ALIGN.top, "flex-start");
    assert.equal(ROW_ALIGN.firstTextBaseline, "baseline");
    assert.equal(DEFAULT_SPACING, 8);
});

test("nearestStackAxis reads the nearest ancestor axis, defaulting to vertical", () => {
    assert.equal(nearestStackAxis({}), StackAxis.Vertical, "no closest() -> vertical default");
    const horiz = { closest: () => ({ dataset: { auiAxis: "horizontal" } }) };
    assert.equal(nearestStackAxis(horiz), "horizontal");
    const none = { closest: () => null };
    assert.equal(nearestStackAxis(none), StackAxis.Vertical);
});

// ---------------- ActionUIInsertion ----------------

test("InsertPosition / ContainerShape enums", () => {
    assert.equal(InsertPosition.APPEND, 0);
    assert.equal(InsertPosition.AFTER, 4);
    assert.equal(ContainerShape.FLAT, "flat");
    assert.equal(ContainerShape.ROWS, "rows");
});

test("resolveContainer: explicit name with matching shape", () => {
    const containers = { children: ContainerShape.FLAT, rows: ContainerShape.ROWS };
    assert.equal(resolveContainer(containers, "children", ContainerShape.FLAT), "children");
});

test("resolveContainer: unknown name throws", () => {
    assert.throws(() => resolveContainer({ children: ContainerShape.FLAT }, "nope", ContainerShape.FLAT),
        (e) => e instanceof InsertError && /Unknown container/.test(e.message));
});

test("resolveContainer: shape mismatch throws", () => {
    assert.throws(() => resolveContainer({ rows: ContainerShape.ROWS }, "rows", ContainerShape.FLAT),
        (e) => e instanceof InsertError && /shape rows/.test(e.message));
});

test("resolveContainer: auto-derives the unique matching container", () => {
    assert.equal(resolveContainer({ children: ContainerShape.FLAT }, null, ContainerShape.FLAT), "children");
});

test("resolveContainer: ambiguous auto-derive throws containerRequired", () => {
    const containers = { a: ContainerShape.FLAT, b: ContainerShape.FLAT };
    assert.throws(() => resolveContainer(containers, null, ContainerShape.FLAT),
        (e) => e instanceof InsertError && /container is required/.test(e.message));
});

test("resolveFlatIndex: append / prepend / at / before / after", () => {
    const ids = [10, 20, 30];
    assert.equal(resolveFlatIndex(ids, InsertPosition.APPEND, 0, "children"), 3);
    assert.equal(resolveFlatIndex(ids, InsertPosition.PREPEND, 0, "children"), 0);
    assert.equal(resolveFlatIndex(ids, InsertPosition.AT, 1, "children"), 1);
    assert.equal(resolveFlatIndex(ids, InsertPosition.BEFORE, 20, "children"), 1);
    assert.equal(resolveFlatIndex(ids, InsertPosition.AFTER, 20, "children"), 2);
});

test("resolveFlatIndex: out-of-bounds AT and missing sibling throw", () => {
    assert.throws(() => resolveFlatIndex([1, 2], InsertPosition.AT, 5, "c"),
        (e) => e instanceof InsertError && /out of bounds/.test(e.message));
    assert.throws(() => resolveFlatIndex([1, 2], InsertPosition.BEFORE, 99, "c"),
        (e) => e instanceof InsertError && /No element with id 99/.test(e.message));
});

test("resolveRowIndex: append/prepend/at, and before/after rejected", () => {
    assert.equal(resolveRowIndex(3, InsertPosition.APPEND, 0, "rows"), 3);
    assert.equal(resolveRowIndex(3, InsertPosition.PREPEND, 0, "rows"), 0);
    assert.equal(resolveRowIndex(3, InsertPosition.AT, 2, "rows"), 2);
    assert.throws(() => resolveRowIndex(3, InsertPosition.BEFORE, 1, "rows"),
        (e) => e instanceof InsertError && /addressable identity/.test(e.message));
});

test("collectElementIds gathers positive ids across nested subviews", () => {
    const el = {
        id: 1,
        subviews: {
            children: [{ id: 2 }, { id: 0 }, { id: 3, subviews: { children: [{ id: 4 }] } }],
            rows: [[{ id: 5 }, { id: 6 }]],
        },
    };
    const ids = collectElementIds(el);
    assert.deepEqual([...ids].sort((a, b) => a - b), [1, 2, 3, 4, 5, 6], "id 0 excluded, nested + rows included");
});

// ---------------- Debug ----------------

test("Debug mode toggles", () => {
    setDebugMode(true);
    assert.equal(isDebugMode(), true);
    setDebugMode(false);
    assert.equal(isDebugMode(), false);
});

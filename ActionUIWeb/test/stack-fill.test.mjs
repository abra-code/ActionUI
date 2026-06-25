// The Web column of the cross-platform stack-fill contract - the mirror of
// Android's StackFillTest (ActionUIAndroid/.../Common/StackFillTest.kt) and of
// canonical SwiftUI:
//
//   A stack child's `.frame(maxWidth/maxHeight: .infinity)` GROWS along the
//   parent stack's MAIN axis (SwiftUI takes the remaining space and splits it
//   equally among such children) and merely STRETCHES across the CROSS axis.
//
// On Web that is the `.aui-fill-width` / `.aui-fill-height` class the modifier
// resolver tags onto the node (covered in modifier-resolver.test.mjs), given its
// SwiftUI meaning by theme.css per parent-stack direction:
//
//   .aui-hstack > .aui-fill-width  -> flex: 1 1 0       (main: share remainder)
//   .aui-vstack > .aui-fill-height -> flex: 1 1 0       (main: share remainder)
//   .aui-hstack > .aui-fill-height -> align-self: stretch (cross: stretch)
//   .aui-vstack > .aui-fill-width  -> align-self: stretch (cross: stretch)
//
// These assertions pin that CSS so the contract cannot silently regress (the
// headless DOM stub has no layout engine, so the class->flex mapping is the
// strongest cross-platform-faithful seam the suite can assert).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Whitespace-insensitive view of the stylesheet.
const css = readFileSync(fileURLToPath(new URL("../theme.css", import.meta.url)), "utf8")
    .replace(/\s+/g, " ");

test("HStack main axis: a fill-width child shares the remainder (flex: 1 1 0)", () => {
    assert.match(css, /\.aui-hstack > \.aui-fill-width\s*\{[^}]*flex:\s*1 1 0/);
});

test("VStack main axis: a fill-height child shares the remainder (flex: 1 1 0)", () => {
    assert.match(css, /\.aui-vstack > \.aui-fill-height\s*\{[^}]*flex:\s*1 1 0/);
});

test("HStack cross axis: a fill-height child stretches (align-self: stretch)", () => {
    assert.match(css, /\.aui-hstack > \.aui-fill-height\s*\{[^}]*align-self:\s*stretch/);
});

test("VStack cross axis: a fill-width child stretches (align-self: stretch)", () => {
    assert.match(css, /\.aui-vstack > \.aui-fill-width\s*\{[^}]*align-self:\s*stretch/);
});

// A FINITE maxWidth/maxHeight uses the CAP class instead, which grows to the cap
// while respecting the parent's alignment - so a centered max-width card centers
// rather than anchoring left (the .aui-fill-* stretch case). Cross axis grows via
// width/height:100% (no align-self override), main axis via flex.
test("VStack cross axis: a cap-width child grows to its cap via width:100% (NOT stretch)", () => {
    assert.match(css, /\.aui-vstack > \.aui-cap-width\s*\{[^}]*width:\s*100%/);
    assert.doesNotMatch(css, /\.aui-vstack > \.aui-cap-width\s*\{[^}]*align-self:\s*stretch/);
});

test("HStack main axis: a cap-width child grows into the remainder (flex: 1 1 0)", () => {
    assert.match(css, /\.aui-hstack > \.aui-cap-width\s*\{[^}]*flex:\s*1 1 0/);
});

test("HStack cross axis: a cap-height child grows to its cap via height:100% (NOT stretch)", () => {
    assert.match(css, /\.aui-hstack > \.aui-cap-height\s*\{[^}]*height:\s*100%/);
});

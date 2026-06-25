// Pins two Web text-rendering parity fixes (2026-06-24), asserted at the CSS
// level since the headless DOM stub has no style cascade:
//   1. A styled TextField honors an explicit `.aui-font-*` class (the input was
//      rendering at the inherited 13px while a sibling Text at the same
//      `font: title2` rendered at 17px - `.aui-textfield { font: inherit }` beat
//      the font class by source order; the inherit now lives in a :where() at
//      zero specificity so the class wins).
//   2. An empty Text reserves one line's height like SwiftUI's Text(""), so a
//      styled result box does not collapse before content arrives.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const css = readFileSync(fileURLToPath(new URL("../theme.css", import.meta.url)), "utf8")
    .replace(/\s+/g, " ");

test("TextField font inherit is zero-specificity so an explicit font class wins", () => {
    assert.match(css, /:where\(\.aui-textfield, \.aui-securefield\) \{ font: inherit;? \}/);
    const block = css.match(/\.aui-textfield, \.aui-securefield \{[^}]*\}/);
    assert.ok(block, "found the base .aui-textfield rule");
    assert.ok(!/font:/.test(block[0]), ".aui-textfield must not set `font` (it would override the font class)");
});

test("an empty Text reserves a line box (matches SwiftUI Text(''))", () => {
    assert.match(css, /\.aui-text:empty::before \{ content: "\\200b"; \}/);
});

// Tests for the Canvas operation parser (src/Helpers/CanvasRenderer.js). Parsing is pure;
// the drawing pass needs a real 2D canvas and is out of scope (see README.md).

import { test } from "node:test";
import assert from "node:assert/strict";
import { parseCanvasOperations } from "../src/Helpers/CanvasRenderer.js";

test("a shadow with no color gets SwiftUI's, black at a third opacity", () => {
    const [shadow] = parseCanvasOperations([{ type: "shadow" }]);
    assert.equal(shadow.type, "shadow");
    assert.equal(shadow.color, "rgba(0,0,0,0.33)");
    assert.equal(shadow.radius, 0.005);
});

test("a shadow keeps the color it names", () => {
    const [shadow] = parseCanvasOperations([{ type: "shadow", color: "#00000060" }]);
    assert.equal(shadow.color, "#00000060");
});

// Tests for toolbar placement bucketing (src/Helpers/ToolbarHelper.js resolveToolbar).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLogger } from "./dom-stub.mjs";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";
import { resolveToolbar } from "../src/Helpers/ToolbarHelper.js";

function withToolbar(items) {
    return ActionUIElement.fromObject({ type: "NavigationStack", toolbar: items }, makeLogger());
}
const item = (placement, title) => ({
    type: "ToolbarItem", properties: { placement }, content: { type: "Button", properties: { title } },
});

test("placements map to leading / principal / trailing / bottom buckets", () => {
    const el = withToolbar([
        item("navigation", "Back"),
        item("principal", "Title"),
        item("primaryAction", "Add"),
        item("bottomBar", "Status"),
    ]);
    const b = resolveToolbar(el, makeLogger());
    assert.equal(b.leading.length, 1, "navigation -> leading");
    assert.equal(b.principal.length, 1, "principal -> principal");
    assert.equal(b.trailing.length, 1, "primaryAction -> trailing (default)");
    assert.equal(b.bottom.length, 1, "bottomBar -> bottom");
});

test("an unsupported placement (keyboard) is dropped with a warning", () => {
    const logger = makeLogger();
    const b = resolveToolbar(withToolbar([item("keyboard", "X")]), logger);
    assert.equal(b.leading.length + b.principal.length + b.trailing.length + b.bottom.length, 0);
    assert.ok(logger.warned("not supported on the web"));
});

test("ToolbarItemGroup contributes all its children to one slot", () => {
    const group = {
        type: "ToolbarItemGroup",
        properties: { placement: "primaryAction" },
        children: [{ type: "Button", properties: { title: "A" } }, { type: "Button", properties: { title: "B" } }],
    };
    const b = resolveToolbar(withToolbar([group]), makeLogger());
    assert.equal(b.trailing.length, 2, "both group children land in trailing");
});

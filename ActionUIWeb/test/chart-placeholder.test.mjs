// Tests for the Chart placeholder (src/Views/Chart.js): the web draws "Chart
// Unavailable" in a chart's place, keeps the selection value and the rows API, and
// takes a replaced description without a warning.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";

let Window, Application, CHART_PLACEHOLDER;

before(async () => {
    installDom();
    ({ Window, Application } = await import("../src/ActionUI.js"));
    ({ CHART_PLACEHOLDER } = await import("../src/Views/Chart.js"));
});

const document = {
    type: "VStack",
    children: [{
        type: "Chart", id: 10,
        properties: { frame: { width: 320, height: 200 }, chart: { columns: ["day"], data: [["Mon"]], content: [] } },
    }],
};

// The stub's querySelector finds nothing, so the chart's node is found by walking the
// tree, and setElementProperty is pointed at it as the property tests do.
function present(logger) {
    const win = Window.fromJSON(document, undefined, logger);
    const host = makeElement();
    new Application({ name: "T" }).presentWindow(win, host);
    const find = (node) => (node?.dataset?.auiId === "10" ? node : (node?.children ?? []).map(find).find(Boolean) ?? null);
    const node = find(host);
    win.model.findNode = (id) => (id === 10 ? node : null);
    return { win, node };
}

test("a Chart draws the unavailable placeholder, sized by its own frame, with one warning per page", () => {
    const logger = makeLogger();
    const { node } = present(logger);
    assert.ok(node, "the chart's node is registered under its id");
    assert.equal(node.dataset.auiType, "Chart");
    assert.equal(node.className, "aui-content-unavailable");
    const title = node.children.find((child) => child.className === "aui-content-unavailable-title");
    assert.equal(title?.textContent, CHART_PLACEHOLDER.title);
    assert.equal(node.style.width, "320px", "the element's frame applies");
    assert.equal(logger.messages.filter((m) => m.level === "warning").length, 1);
    assert.ok(logger.warned("Chart is not supported on the web"));

    const again = makeLogger();
    present(again);
    assert.equal(again.warningCount(), 0, "the warning is logged once per page");
});

test("the selection value, the rows and a replaced description work without warnings", () => {
    const logger = makeLogger();
    const { win } = present(logger);
    logger.messages.length = 0;

    assert.equal(win.getString(10), "");
    win.setString(10, 0, "{\"x\":\"Tue\"}");
    assert.equal(win.getString(10), "{\"x\":\"Tue\"}");

    assert.deepEqual(win.getElementRows(10), []);
    win.setElementRows(10, [["Mon", "3"]]);
    win.appendElementRows(10, [["Tue", "5"]]);
    assert.deepEqual(win.getElementRows(10), [["Mon", "3"], ["Tue", "5"]]);
    win.clearElementRows(10);
    assert.deepEqual(win.getElementRows(10), []);

    win.setElementProperty(10, "chart", { content: [] });
    assert.equal(logger.warningCount(), 0, logger.messages.map((m) => m.message).join("\n"));
});

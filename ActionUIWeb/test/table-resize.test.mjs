// Tests for Table column resizing + the scroll wrapper (src/Views/Table.js).
// The table is wrapped in a bounded scroll container (`.aui-table-scroll`) so it
// can grow past its frame instead of clipping. It is `table-layout: fixed`: the
// widest-ideal column auto-sizes to fill the frame (a ResizeObserver re-fills it),
// the others take their ideal width, and every column carries a header drag handle
// whose pointer drag rewrites the matching <col>'s width (floored at the resolved
// minimum). These assert the DOM the build produces and the width math a drag runs;
// pixel layout, ResizeObserver, and pointer capture are browser concerns the
// headless stub does not model (so it never auto-fills - widths stay at the ideals -
// and the move/up listeners are driven directly; see dom-stub.mjs).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, ActionUIModel, ActionUIElement;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});

// Builds a Table to its DOM through the full registry path, returning the scroll
// wrapper (the node the renderer returns) plus the inner <table>/<colgroup>/<thead>.
function buildTable(properties) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const element = ActionUIElement.fromObject({ type: "Table", id: 100, properties }, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const scroll = buildElementView(element, ctx);
    const table = scroll.children.find((c) => c.tagName === "TABLE");
    const colgroup = table?.children.find((c) => c.tagName === "COLGROUP");
    const thead = table?.children.find((c) => c.tagName === "THEAD");
    const headRow = thead?.children[0];
    return { scroll, table, colgroup, thead, headRow, logger };
}

const handleOf = (headRow, i) => headRow.children[i].children.find((c) => c.className === "aui-table-resizer");

// Drives a header handle's pointer drag: pointerdown then a single pointermove to
// `toX` (the handle captures move/up, so they fire on the handle itself).
function dragHandle(handle, fromX, toX) {
    handle.fire("pointerdown", { clientX: fromX, pointerId: 1, preventDefault() {}, stopPropagation() {} });
    handle.fire("pointermove", { clientX: toX });
}

const COLS = { columns: ["Name", "Kind", "Action"], widths: [150, 60, 80] };

test("the table is wrapped in a bounded scroll container", () => {
    const { scroll, table } = buildTable(COLS);
    assert.equal(scroll.className, "aui-table-scroll");
    assert.ok(table, "the <table> lives inside the scroll wrapper");
});

test("every column gets an explicit width (headless: each at its ideal)", () => {
    const { colgroup } = buildTable(COLS);
    assert.equal(colgroup.children.length, 3);
    assert.equal(colgroup.children[0].style.width, "150px", "the widest-ideal column starts at its ideal");
    assert.equal(colgroup.children[1].style.width, "60px");
    assert.equal(colgroup.children[2].style.width, "80px");
});

test("every column carries a resize handle (the widest one included)", () => {
    const { headRow } = buildTable(COLS);
    assert.ok(handleOf(headRow, 0) && handleOf(headRow, 1) && handleOf(headRow, 2),
        "all three columns are resizable");
});

test("dragging a column's handle right widens that column from its current width", () => {
    const { colgroup, headRow } = buildTable(COLS);
    dragHandle(handleOf(headRow, 1), 100, 130); // +30 from Kind's 60
    assert.equal(colgroup.children[1].style.width, "90px");
});

test("dragging the widest (flex) column resizes it directly", () => {
    const { colgroup, headRow } = buildTable(COLS);
    dragHandle(handleOf(headRow, 0), 100, 140); // +40 from Name's 150
    assert.equal(colgroup.children[0].style.width, "190px");
});

test("a drag is floored at the resolved minimum (explicit minWidths)", () => {
    const { colgroup, headRow } = buildTable({ ...COLS, minWidths: [120, 50, 40] });
    dragHandle(handleOf(headRow, 1), 100, 0); // -100 would take Kind well below its min 50
    assert.equal(colgroup.children[1].style.width, "50px", "clamped to minWidths[1]");
});

test("the resizing class toggles on the scroll wrapper (pointerdown / pointerup)", () => {
    const { scroll, headRow } = buildTable(COLS);
    const handle = handleOf(headRow, 1);
    handle.fire("pointerdown", { clientX: 0, pointerId: 1, preventDefault() {}, stopPropagation() {} });
    assert.ok(scroll.classList.contains("aui-table-resizing"));
    handle.fire("pointerup", { pointerId: 1 });
    assert.equal(scroll.classList.contains("aui-table-resizing"), false);
});

test("columnHeadersVisibility:hidden suppresses the header (no thead, so not resizable)", () => {
    const { thead } = buildTable({ ...COLS, columnHeadersVisibility: "hidden" });
    assert.equal(thead, undefined, "no <thead> built when columnHeadersVisibility is 'hidden'");
});

// Table.js — Table element.
// Web analog of ActionUI/Views/Table.swift (and ActionUIAndroid Views/Table.kt).
//
// A multi-column data table. Apple's Table is macOS-only (SwiftUI.Table lives on
// AppKit; every other Apple platform returns EmptyView), and Android — the "every
// other platform" case — renders nothing. The web is a desktop target like macOS,
// so it renders a real <table>, following the macOS reference rather than the
// Android no-op.
//
// Table is purely data-driven: it has no static (children) mode. Rows come from
// states["content"] ([[String]]) via the rows API on Window
// (set/append/clearElementRows, getElementColumnCount) — landed alongside this
// element, since Table is the first consumer that needs it. The Table binds its
// "content" state so a set/append/clear re-renders the body in place.
//
// Selection (value bridge). Like List, the selected row is carried as a String:
// its columns tab-joined ("" = nothing selected), read/written with
// get/setString(tableID) — Android's string transport for the Apple [String]
// value. A row can also be selected programmatically (without replacing the rows,
// firing no actionID) via the model selection API — selectElementRow(index) /
// selectElementRowWithContent(text, column) / clearElementSelection.
// The table-level actionID fires on selection change (no context; the host
// reads the value, matching Apple). doubleClickActionID fires on a double-click of
// the selected row with the row index as context. A Button cell fires its own
// columnTypes[c].actionID and consumes the click, so per-cell actions and row
// selection coexist.
//
// Properties (mirroring Table.swift):
//   columns          Required [String] of header titles.
//   columnHeadersVisibility  "automatic"|"hidden"|"visible".
//   columnTypes      Per-column { viewType, actionContext, actionID,
//                    dataInterpretation }; padded to columns with Text.
//   widths / minWidths  [Int] ideal / minimum column widths; the widest-ideal
//                    column auto-sizes to fill the frame (macOS), the rest take
//                    their ideal. Every column is user-resizable by dragging its
//                    header border (down to the resolved minimum); the table is
//                    wrapped in a scroller, so resizing past the frame (or adding
//                    rows) scrolls rather than clips. Resizing needs visible headers.
//   actionID / doubleClickActionID  selection / double-click actions.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { buildDataImageCell } from "../Helpers/DataImageCell.js";
import { commonRowPrefix } from "../Helpers/RowDiff.js";

const CELL_VIEW_TYPES = ["Text", "Button", "Image", "AsyncImage"];
const DATA_INTERPRETATIONS = ["path", "systemName", "assetName", "resourceName", "mixed"];
const CELL_ACTION_CONTEXTS = ["title", "rowIndex", "columnIndex", "rowColumnIndex"];
const HEADER_VISIBILITIES = ["visible", "hidden", "automatic"];

register("Table", {
    // The selected row, columns tab-joined, as a String ("" = none). See header.
    valueType: "string",

    // Mirrors Table.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // columns — an array of strings, else []. (Apple writes back [] when nil
        // or wrong-typed; only the wrong-typed case warns.)
        if (validated.columns === undefined) {
            validated.columns = [];
        } else if (!isStringArray(validated.columns)) {
            logger.log("Table columns must be an array of strings; defaulting to []", "warning");
            validated.columns = [];
        }

        // columnTypes — pad to columns.length with Text, then validate each entry.
        const columnTypes = Array.isArray(properties.columnTypes)
            ? properties.columnTypes.map((entry) => ({ ...entry })) : [];
        while (columnTypes.length < validated.columns.length) {
            columnTypes.push({ viewType: "Text" });
        }
        columnTypes.forEach((ct, i) => {
            const vt = typeof ct.viewType === "string" ? ct.viewType : "Text";
            if (!CELL_VIEW_TYPES.includes(vt)) {
                logger.log(`Table columnTypes[${i}].viewType must be 'Text', 'Button', 'Image', or 'AsyncImage'; defaulting to Text`, "warning");
                ct.viewType = "Text";
            }
            if (vt === "Image" && !DATA_INTERPRETATIONS.includes(ct.dataInterpretation)) {
                logger.log(`Table columnTypes[${i}].dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for Image; defaulting to systemName`, "warning");
                ct.dataInterpretation = "systemName";
            }
            if (vt === "Button") {
                if (!CELL_ACTION_CONTEXTS.includes(ct.actionContext)) {
                    logger.log(`Table columnTypes[${i}].actionContext must be 'title', 'rowIndex', 'columnIndex', or 'rowColumnIndex' for Button; defaulting to title`, "warning");
                    ct.actionContext = "title";
                }
                if (ct.dataInterpretation !== undefined && !DATA_INTERPRETATIONS.includes(ct.dataInterpretation)) {
                    logger.log(`Table columnTypes[${i}].dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for Button; ignoring`, "warning");
                    delete ct.dataInterpretation;
                }
            }
        });
        validated.columnTypes = columnTypes;

        // widths / minWidths — arrays of integers, else dropped.
        if (validated.widths !== undefined && !isIntArray(validated.widths)) {
            logger.log("Table widths must be an array of integers; ignoring", "warning");
            delete validated.widths;
        }
        if (validated.minWidths !== undefined && !isIntArray(validated.minWidths)) {
            logger.log("Table minWidths must be an array of integers; ignoring", "warning");
            delete validated.minWidths;
        }

        // columnHeadersVisibility — a String in the valid set, else dropped.
        if (validated.columnHeadersVisibility !== undefined) {
            const chv = validated.columnHeadersVisibility;
            if (typeof chv === "string") {
                if (!HEADER_VISIBILITIES.includes(chv)) {
                    logger.log(`Invalid columnHeadersVisibility '${chv}'; expected one of ["visible", "hidden", "automatic"], ignoring`, "warning");
                    delete validated.columnHeadersVisibility;
                }
            } else {
                logger.log(`Invalid type for columnHeadersVisibility: expected String, got ${typeof chv}, ignoring`, "warning");
                delete validated.columnHeadersVisibility;
            }
        }

        // doubleClickActionID — must be a string, else dropped.
        if (validated.doubleClickActionID !== undefined && typeof validated.doubleClickActionID !== "string") {
            logger.log("Table doubleClickActionID must be a string; ignoring", "warning");
            delete validated.doubleClickActionID;
        }

        return validated;
    },

    initialValue: () => "",
    initialStates: () => ({ content: [] }),

    buildView: (element, properties, ctx) => {
        const columns = Array.isArray(properties.columns) ? properties.columns : [];
        const columnTypes = Array.isArray(properties.columnTypes) ? properties.columnTypes : [];
        const widths = Array.isArray(properties.widths) ? properties.widths : null;
        const minWidths = Array.isArray(properties.minWidths) ? properties.minWidths : null;
        // columnHeadersVisibility: "hidden" suppresses the header row entirely;
        // "visible" / "automatic" show it. A static (build-time) choice, matching
        // Apple/Android - there is no runtime toggle.
        const headersHidden = properties.columnHeadersVisibility === "hidden";

        // A scroll container wraps the table so it can grow past its frame: when the
        // columns are wider, or the rows taller, than the bounded frame, the wrapper
        // scrolls (horizontally / vertically) instead of clipping. The frame and the
        // data-aui-id land on this wrapper (it is the returned node); the header is
        // sticky so it stays visible while the rows scroll. (macOS SwiftUI.Table is
        // itself scroll-backed; this is the web equivalent.)
        const scroll = document.createElement("div");
        scroll.className = "aui-table-scroll";
        markHandlesAction(scroll); // selection owns the table's actionID (opt out of the generic click handler)

        const table = document.createElement("table");
        table.className = "aui-table";
        scroll.appendChild(table);

        // Column sizing. The widest-ideal column auto-sizes to fill the frame width
        // (matching macOS SwiftUI.Table); the others take their ideal width. Every
        // column is user-resizable by dragging its right-edge header handle.
        // `.aui-table` is `table-layout: fixed`, so the <col> widths are authoritative
        // and a drag is honored exactly.
        //
        // Widths are JS-managed (colWidths) rather than left to CSS so we can have BOTH
        // an auto-filling widest column AND a resize that pushes the table past the
        // frame (CSS alone gives one or the other: a width:100% table absorbs into its
        // auto column and never overflows). A ResizeObserver re-fills the widest column
        // when the frame changes; a drag sets the dragged column's width and the
        // wrapper scrolls once the total exceeds the frame. Dragging during a frame
        // that has room does not shrink other columns (the divider tracks the cursor) -
        // a deliberate, more predictable divergence from macOS' live column absorb.
        const idealWidths = columns.map((_, i) => (widths && Number.isInteger(widths[i])) ? widths[i] : 100);
        // Resolved minimum per column: an explicit minWidths entry, else min(ideal, 10)
        // (the Table.swift default). The floor a drag cannot cross.
        const resolvedMins = columns.map((_, i) =>
            (minWidths && Number.isInteger(minWidths[i])) ? minWidths[i] : Math.min(idealWidths[i], 10));
        // The widest-ideal column flexes (auto-fills the frame); first wins a tie.
        const maxIdeal = idealWidths.length ? Math.max(...idealWidths) : 0;
        const flexIndex = idealWidths.indexOf(maxIdeal);
        // Live width per column. Starts at the ideal (floored at the resolved minimum);
        // relayout() widens the flex column to fill once the frame is measured.
        const colWidths = idealWidths.map((w, i) => Math.max(w, resolvedMins[i]));
        // Set true when the user drags the flex column itself: it then keeps that manual
        // width and stops auto-filling (the host took control of the widest column).
        let flexPinned = false;

        const colEls = [];
        const colgroup = document.createElement("colgroup");
        columns.forEach((_, i) => {
            const col = document.createElement("col");
            if (minWidths && Number.isInteger(minWidths[i])) col.style.minWidth = `${minWidths[i]}px`;
            colgroup.appendChild(col);
            colEls.push(col);
        });
        table.appendChild(colgroup);

        // Push the live widths to the <col>s and size the table to their sum, so the
        // table is exactly as wide as its columns - the wrapper scrolls when that sum
        // exceeds the frame.
        const applyWidths = () => {
            let sum = 0;
            colWidths.forEach((w, i) => { colEls[i].style.width = `${w}px`; sum += w; });
            table.style.width = `${sum}px`;
        };

        // Re-fill the flex (widest) column so the table fills the frame width. `shrink`
        // lets it shrink back toward its ideal (used on a frame resize); without it the
        // flex column only grows to fill freed space (used on drag release), so
        // widening another column scrolls rather than silently shrinking the widest.
        const relayout = ({ shrink } = {}) => {
            const avail = scroll.clientWidth;
            if (flexIndex >= 0 && !flexPinned && avail > 0) {
                const othersSum = colWidths.reduce((s, w, i) => (i === flexIndex ? s : s + w), 0);
                const fill = Math.max(idealWidths[flexIndex], resolvedMins[flexIndex], avail - othersSum);
                colWidths[flexIndex] = shrink ? fill : Math.max(colWidths[flexIndex], fill);
            }
            applyWidths();
        };

        // Drag a column's right-edge handle to resize it. Pointer capture keeps the
        // drag tracking even when the pointer leaves the thin handle. The dragged
        // column tracks the cursor and the wrapper scrolls when the table outgrows the
        // frame; dragging the flex column pins it, and on release the flex column grows
        // to fill any freed space. (setPointerCapture / releasePointerCapture are
        // guarded so the headless test DOM still drives the move/up path.)
        const startResize = (colIndex, handle, event) => {
            event.preventDefault?.();
            event.stopPropagation?.(); // a header drag, never a row selection
            const startX = event.clientX;
            const startWidth = colWidths[colIndex];
            if (colIndex === flexIndex) flexPinned = true;
            handle.setPointerCapture?.(event.pointerId);
            scroll.classList.add("aui-table-resizing");
            const onMove = (moveEvent) => {
                colWidths[colIndex] = Math.max(resolvedMins[colIndex], startWidth + (moveEvent.clientX - startX));
                applyWidths();
            };
            const onUp = (upEvent) => {
                handle.releasePointerCapture?.(upEvent.pointerId);
                scroll.classList.remove("aui-table-resizing");
                handle.removeEventListener("pointermove", onMove);
                handle.removeEventListener("pointerup", onUp);
                relayout(); // grow the widest column to fill any freed space
            };
            handle.addEventListener("pointermove", onMove);
            handle.addEventListener("pointerup", onUp);
        };

        // The header row (suppressed entirely when columnHeadersVisibility is
        // "hidden"). Every column gets a drag handle on its right edge (the widest
        // column too - dragging it pins its width). Resizing needs a visible header to
        // grab, so a hidden-header table is not resizable.
        if (!headersHidden) {
            const thead = document.createElement("thead");
            const headRow = document.createElement("tr");
            columns.forEach((name, i) => {
                const th = document.createElement("th");
                th.textContent = String(name);
                const handle = document.createElement("div");
                handle.className = "aui-table-resizer";
                handle.setAttribute("aria-hidden", "true");
                handle.addEventListener("pointerdown", (event) => startResize(i, handle, event));
                th.appendChild(handle);
                headRow.appendChild(th);
            });
            thead.appendChild(headRow);
            table.appendChild(thead);
        }

        const tbody = document.createElement("tbody");
        table.appendChild(tbody);

        let rows = [];
        let trNodes = [];
        let selectedIndex = -1;

        const rowValue = () =>
            (selectedIndex >= 0 && selectedIndex < rows.length) ? rows[selectedIndex].join("\t") : "";

        const applySelectionStyles = () => {
            trNodes.forEach((tr, i) => {
                const selected = i === selectedIndex;
                tr.classList.toggle("aui-table-row-selected", selected);
                tr.setAttribute("aria-selected", selected ? "true" : "false");
            });
        };

        const selectIndex = (index, fromUser) => {
            if (index === selectedIndex) return;
            selectedIndex = index;
            applySelectionStyles();
            // Apple fires the selection action with no context and reads
            // model.value; the web matches — the selection is the element value.
            if (fromUser && typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, null);
            }
        };

        const buildCell = (value, colIndex, rowIndexRef) => {
            const td = document.createElement("td");
            const colType = columnTypes[colIndex] ?? { viewType: "Text" };
            const viewType = colType.viewType ?? "Text";
            if (viewType === "Button") {
                const button = document.createElement("button");
                button.className = "aui-table-button";
                if (colType.dataInterpretation) {
                    button.appendChild(buildDataImageCell(value, colType.dataInterpretation, ctx.logger, "Table"));
                } else {
                    button.textContent = value;
                }
                button.addEventListener("click", (event) => {
                    event.stopPropagation(); // the cell's own tap, not row selection
                    if (typeof colType.actionID === "string") {
                        ctx.model.dispatchAction(colType.actionID, element.id, colIndex, cellContext(colType.actionContext, value, rowIndexRef(), colIndex));
                    }
                });
                td.appendChild(button);
            } else if (viewType === "Image") {
                td.appendChild(buildDataImageCell(value, colType.dataInterpretation ?? "mixed", ctx.logger, "Table"));
            } else if (viewType === "AsyncImage") {
                const img = document.createElement("img");
                img.className = "aui-data-image";
                img.loading = "lazy";
                img.src = value;
                img.alt = "";
                td.appendChild(img);
            } else { // Text and fallback
                td.textContent = value;
            }
            return td;
        };

        const buildRow = (row, rowIndex) => {
            const tr = document.createElement("tr");
            tr.setAttribute("role", "row");
            const rowIndexRef = () => rowIndex;
            columns.forEach((_, colIndex) => {
                tr.appendChild(buildCell(row[colIndex] ?? "", colIndex, rowIndexRef));
            });
            tr.addEventListener("click", () => selectIndex(rowIndex, true));
            tr.addEventListener("dblclick", () => {
                if (typeof properties.doubleClickActionID === "string" && rowIndex === selectedIndex) {
                    ctx.model.dispatchAction(properties.doubleClickActionID, element.id, 0, rowIndex);
                }
            });
            return tr;
        };

        // Apply a new rows array with a common-prefix diff (Helpers/RowDiff.js)
        // instead of rebuilding the whole <tbody>: an append (the rows API re-sends
        // the whole array) keeps every unchanged prefix <tr> - its cells, selection
        // styling and baked row index - in place and builds only the new tail; a
        // prepend / mid-list edit rebuilds from the first change. Column auto-fill is
        // width-based (row-count independent), so an append needs no relayout.
        const applyRows = (next) => {
            next = Array.isArray(next) ? next : [];
            const keep = commonRowPrefix(rows, next);
            while (trNodes.length > keep) { trNodes[trNodes.length - 1].remove(); trNodes.pop(); }
            for (let rowIndex = keep; rowIndex < next.length; rowIndex++) {
                const tr = buildRow(next[rowIndex], rowIndex);
                trNodes.push(tr);
                tbody.appendChild(tr);
            }
            rows = next;
            // A re-render drops the prior selection if its row no longer exists.
            if (selectedIndex >= rows.length) selectedIndex = -1;
            applySelectionStyles();
        };

        if (element.id > 0) {
            // The rows store: set/append/clearElementRows route through here and
            // re-render the body in place (incrementally - see applyRows).
            ctx.model.bindState(element.id, {
                getState: (key) => (key === "content" ? rows : undefined),
                setState: (key, value) => { if (key === "content") applyRows(value); },
            });
            // The selection value: tab-joined selected row; set by value match.
            ctx.model.bind(element.id, {
                getValue: () => rowValue(),
                setValue: (value) => { // programmatic: silent
                    const target = String(value ?? "");
                    selectedIndex = target === "" ? -1 : rows.findIndex((row) => row.join("\t") === target);
                    applySelectionStyles();
                },
            });
        }

        applyWidths(); // seed the <col> widths before the frame is measured
        applyRows([]);
        // Keep the widest column filling the frame as the frame / window resizes
        // (also performs the first fill once the wrapper has a measured width).
        if (typeof ResizeObserver !== "undefined") {
            const observer = new ResizeObserver(() => relayout({ shrink: true }));
            observer.observe(scroll);
        }
        return scroll;
    },
});

// The Button cell's action context, per columnTypes[c].actionContext.
function cellContext(actionContext, value, rowIndex, colIndex) {
    switch (actionContext) {
        case "rowIndex":       return rowIndex;
        case "columnIndex":    return colIndex;
        case "rowColumnIndex": return { row: rowIndex, column: colIndex };
        default:               return value; // "title"
    }
}

function isStringArray(value) {
    return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function isIntArray(value) {
    return Array.isArray(value) && value.every((entry) => Number.isInteger(entry));
}

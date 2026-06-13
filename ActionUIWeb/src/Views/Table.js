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
// value. The table-level actionID fires on selection change (no context; the host
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
//                    column fills remaining space.
//   actionID / doubleClickActionID  selection / double-click actions.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

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
        const headersHidden = properties.columnHeadersVisibility === "hidden";

        const table = document.createElement("table");
        table.className = "aui-table";
        markHandlesAction(table); // selection owns the table's actionID

        // Column sizing: the widest ideal width fills remaining space; others get
        // a fixed width. min-widths floor each column. (Approximate; resizing is
        // skin work, deferred.)
        const idealWidths = columns.map((_, i) => (widths && Number.isInteger(widths[i])) ? widths[i] : 100);
        const maxIdeal = idealWidths.length ? Math.max(...idealWidths) : 100;
        const colgroup = document.createElement("colgroup");
        columns.forEach((_, i) => {
            const col = document.createElement("col");
            const isFill = idealWidths[i] === maxIdeal;
            if (!isFill) col.style.width = `${idealWidths[i]}px`;
            const min = (minWidths && Number.isInteger(minWidths[i])) ? minWidths[i] : null;
            if (min !== null) col.style.minWidth = `${min}px`;
            colgroup.appendChild(col);
        });
        table.appendChild(colgroup);

        if (!headersHidden) {
            const thead = document.createElement("thead");
            const headRow = document.createElement("tr");
            for (const name of columns) {
                const th = document.createElement("th");
                th.textContent = String(name);
                headRow.appendChild(th);
            }
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
                    button.appendChild(buildCellImage(value, colType.dataInterpretation, ctx.logger));
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
                td.appendChild(buildCellImage(value, colType.dataInterpretation ?? "mixed", ctx.logger));
            } else if (viewType === "AsyncImage") {
                const img = document.createElement("img");
                img.className = "aui-table-image";
                img.loading = "lazy";
                img.src = value;
                img.alt = "";
                td.appendChild(img);
            } else { // Text and fallback
                td.textContent = value;
            }
            return td;
        };

        const renderBody = () => {
            const trs = rows.map((row, rowIndex) => {
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
            });
            trNodes = trs;
            tbody.replaceChildren(...trs);
            // A re-render drops the prior selection if its row no longer exists.
            if (selectedIndex >= rows.length) selectedIndex = -1;
            applySelectionStyles();
        };

        if (element.id > 0) {
            // The rows store: set/append/clearElementRows route through here and
            // re-render the body in place.
            ctx.model.bindState(element.id, {
                getState: (key) => (key === "content" ? rows : undefined),
                setState: (key, value) => {
                    if (key !== "content") return;
                    rows = Array.isArray(value) ? value : [];
                    renderBody();
                },
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

        renderBody();
        return table;
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

// Renders a Table image cell from a raw data string + interpretation, reusing the
// shared glyph helper for SF Symbols and a plain <img> for raster paths. asset/
// resource catalog sources warn-and-skip on web (no name→URL contract yet), as in
// Image.js/SymbolIcon.js. "mixed" sniffs a path-looking string.
function buildCellImage(value, interpretation, logger) {
    const resolved = interpretation === "mixed"
        ? (looksLikePath(value) ? "path" : "systemName")
        : interpretation;

    if (resolved === "systemName") {
        return systemSymbolGlyph(value, {}, logger, (name) =>
            `Table image cell systemName '${name}' has no SF→Material mapping; icon omitted. ` +
            `Use 'materialName:web' for an explicit Material glyph.`);
    }
    if (resolved === "path") {
        const img = document.createElement("img");
        img.className = "aui-table-image";
        img.src = value;
        img.alt = "";
        return img;
    }
    // assetName / resourceName: asset-catalog images aren't supported on web yet.
    logger.log(
        `Table image cell '${value}' uses '${resolved}', an asset-catalog source not ` +
        `supported on web yet (pending a name→URL contract). No image rendered.`,
        "warning",
    );
    const empty = document.createElement("span");
    empty.className = "aui-image aui-image-empty";
    return empty;
}

function looksLikePath(value) {
    return /^(https?:|\.{0,2}\/|data:)/.test(value) || /\.(png|jpe?g|gif|webp|svg|bmp|pdf)$/i.test(value);
}

function isStringArray(value) {
    return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function isIntArray(value) {
    return Array.isArray(value) && value.every((entry) => Number.isInteger(entry));
}

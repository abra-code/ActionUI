// Grid.js — Grid element.
// Web analog of ActionUI/Views/Grid.swift (and ActionUIAndroid Views/Grid.kt).
//
// A two-dimensional grid laid out from explicit `rows` — each entry is one
// GridRow (an array of cell elements), supplied under the top-level `rows` key
// (the array-of-arrays named container, routed by ActionUIElement). Rendered as
// CSS `display:grid`; every cell is placed by explicit `grid-row`/`grid-column`
// so cells line up into columns the way SwiftUI's Grid aligns GridRows, even
// when rows have different lengths (the column count is the longest row).
//
// Properties (mirroring Grid.swift):
//   alignment          9-way (topLeading … bottomTrailing) → place-items, the
//                      default cell anchor. Default center.
//   horizontalSpacing  Number → column-gap (default 8 ≈ SwiftUI's adaptive default).
//   verticalSpacing    Number → row-gap (default 8).

import { register } from "../Common/ActionUIRegistry.js";
import { DEFAULT_SPACING } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { gridRowsBinding } from "../Helpers/InsertionHelper.js";

// 9-way alignment → [align-items (block/vertical), justify-items (inline/horizontal)].
const PLACE_ITEMS = {
    topLeading: ["start", "start"], top: ["start", "center"], topTrailing: ["start", "end"],
    leading: ["center", "start"], center: ["center", "center"], trailing: ["center", "end"],
    bottomLeading: ["end", "start"], bottom: ["end", "center"], bottomTrailing: ["end", "end"],
};

register("Grid", {
    valueType: "none",
    insertableContainers: { rows: ContainerShape.ROWS },

    // Mirrors Grid.swift validateProperties
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (typeof validated.alignment === "string") {
            if (!Object.keys(PLACE_ITEMS).includes(validated.alignment)) {
                logger.log(`Grid alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
                delete validated.alignment;
            }
        } else if (validated.alignment !== undefined) {
            logger.log("Grid alignment must be one of 'topLeading', 'top', 'topTrailing', 'leading', 'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'; ignoring", "warning");
            delete validated.alignment;
        }

        if (validated.horizontalSpacing !== undefined && typeof validated.horizontalSpacing !== "number") {
            logger.log("Grid horizontalSpacing must be a number; ignoring", "warning");
            delete validated.horizontalSpacing;
        }
        if (validated.verticalSpacing !== undefined && typeof validated.verticalSpacing !== "number") {
            logger.log("Grid verticalSpacing must be a number; ignoring", "warning");
            delete validated.verticalSpacing;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const rows = element.subviews?.rows ?? [];
        const columnCount = rows.reduce((max, row) => Math.max(max, row.length), 0);

        const node = document.createElement("div");
        node.className = "aui-grid aui-grid-explicit";
        node.style.gridTemplateColumns = `repeat(${Math.max(columnCount, 1)}, auto)`;
        node.style.columnGap = `${properties.horizontalSpacing ?? DEFAULT_SPACING}px`;
        node.style.rowGap = `${properties.verticalSpacing ?? DEFAULT_SPACING}px`;
        const [alignItems, justifyItems] = PLACE_ITEMS[properties.alignment] ?? PLACE_ITEMS.center;
        node.style.alignItems = alignItems;
        node.style.justifyItems = justifyItems;

        const cellRows = rows.map((row, rowIndex) => row.map((cell, columnIndex) => {
            const cellNode = ctx.build(cell);
            // Explicit placement keeps columns aligned across uneven rows
            // (CSS auto-placement would backfill short rows into the gaps).
            cellNode.style.gridRow = String(rowIndex + 1);
            cellNode.style.gridColumn = String(columnIndex + 1);
            node.appendChild(cellNode);
            return cellNode;
        }));

        // The rows container for insertRow: a new row's cells are placed and the
        // explicit grid coordinates reflow. A cell wider than the declared column
        // count falls into an implicit auto track (no template change needed).
        if (element.id > 0) {
            ctx.model.bindContainer(element.id, "rows", gridRowsBinding(node, cellRows));
        }
        return node;
    },
});

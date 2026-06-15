// LazyVGrid.js — LazyVGrid element.
// Web analog of ActionUI/Views/LazyVGrid.swift (and ActionUIAndroid Views/LazyVGrid.kt).
//
// A grid that grows vertically: `columns` declares the column tracks and the
// children flow into them row by row. Rendered as CSS `display:grid` with
// `grid-template-columns` — the natural DOM analog of SwiftUI's LazyVGrid; the
// browser's auto-placement is the row-by-row flow. Renders eagerly (no
// virtualization — Phase 4), like the lazy stacks.
//
// Column tracks (mirroring GridItem): `{ minimum: N }` → a fixed `Npx` track
// (Swift maps `minimum` to `GridItem(.fixed)`), `{ flexible: true }` → `1fr`;
// no/empty `columns` → a single `1fr` column. Validation/parsing is the twin of
// LazyHGrid's (key "rows"); kept inline so each file mirrors its Swift file.
//
// Properties (mirroring LazyVGrid.swift):
//   columns    array of { minimum?: Number, flexible?: Boolean } track defs.
//   spacing    Number → CSS gap (default 0, like the lazy stacks).
//   alignment  leading|center|trailing → justify-items (default center).

import { register } from "../Common/ActionUIRegistry.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

// Validated track defs → a CSS track list. `{minimum}` → fixed px, `{flexible}`
// → 1fr; anything else dropped; empty ⇒ a single "1fr" (Swift's [GridItem(.flexible())]).
function trackList(defs) {
    const tracks = (defs ?? [])
        .map((d) => (typeof d.minimum === "number" ? `${d.minimum}px` : (d.flexible === true ? "1fr" : null)))
        .filter((t) => t !== null);
    return tracks.length ? tracks.join(" ") : "1fr";
}

const JUSTIFY = { leading: "start", center: "center", trailing: "end" };

register("LazyVGrid", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },

    // Mirrors LazyVGrid.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (Array.isArray(validated.columns) && validated.columns.every(isPlainObject)) {
            const validatedColumns = [];
            for (const column of validated.columns) {
                const validatedColumn = {};
                if (typeof column.minimum === "number") validatedColumn.minimum = column.minimum;
                if (typeof column.flexible === "boolean") validatedColumn.flexible = column.flexible;
                if (Object.keys(validatedColumn).length > 0) validatedColumns.push(validatedColumn);
            }
            if (validatedColumns.length > 0) {
                validated.columns = validatedColumns;
            } else {
                logger.log("LazyVGrid columns must contain valid minimum or flexible values; ignoring", "warning");
                delete validated.columns;
            }
        } else if (validated.columns !== undefined) {
            logger.log("LazyVGrid columns must be an array of dictionaries; ignoring", "warning");
            delete validated.columns;
        }

        if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
            logger.log("LazyVGrid spacing must be numeric; ignoring", "warning");
            delete validated.spacing;
        }

        if (typeof validated.alignment === "string") {
            if (!["leading", "center", "trailing"].includes(validated.alignment)) {
                logger.log(`LazyVGrid alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
                delete validated.alignment;
            }
        } else if (validated.alignment !== undefined) {
            logger.log("LazyVGrid alignment must be 'leading', 'center', or 'trailing'; ignoring", "warning");
            delete validated.alignment;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-grid aui-lazyvgrid";
        node.style.gridTemplateColumns = trackList(properties.columns);
        node.style.gap = `${properties.spacing ?? 0}px`;
        node.style.justifyItems = JUSTIFY[properties.alignment] ?? "center";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});

function isPlainObject(v) {
    return typeof v === "object" && v !== null && !Array.isArray(v);
}

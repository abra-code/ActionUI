// LazyHGrid.js — LazyHGrid element.
// Web analog of ActionUI/Views/LazyHGrid.swift (and ActionUIAndroid Views/LazyHGrid.kt).
//
// A grid that grows horizontally: `rows` declares the row tracks and the
// children flow into them column by column. Rendered as CSS `display:grid` with
// `grid-template-rows` plus `grid-auto-flow:column` (the column-by-column flow,
// the analog of SwiftUI's LazyHGrid). Renders eagerly (no virtualization — Phase
// 4), like the lazy stacks.
//
// Row tracks (mirroring GridItem): `{ minimum: N }` → a fixed `Npx` track,
// `{ flexible: true }` → `1fr`; no/empty `rows` → a single `1fr` row. The track
// validation/parsing is the twin of LazyVGrid's (key "columns"); kept inline so
// each file mirrors its Swift file.
//
// Properties (mirroring LazyHGrid.swift):
//   rows       array of { minimum?: Number, flexible?: Boolean } track defs.
//   spacing    Number → CSS gap (default 0, like the lazy stacks).
//   alignment  top|center|bottom → align-items (default center).

import { register } from "../Common/ActionUIRegistry.js";

// Validated track defs → a CSS track list. `{minimum}` → fixed px, `{flexible}`
// → 1fr; anything else dropped; empty ⇒ a single "1fr" (Swift's [GridItem(.flexible())]).
function trackList(defs) {
    const tracks = (defs ?? [])
        .map((d) => (typeof d.minimum === "number" ? `${d.minimum}px` : (d.flexible === true ? "1fr" : null)))
        .filter((t) => t !== null);
    return tracks.length ? tracks.join(" ") : "1fr";
}

const ALIGN = { top: "start", center: "center", bottom: "end" };

register("LazyHGrid", {
    valueType: "none",

    // Mirrors LazyHGrid.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (Array.isArray(validated.rows) && validated.rows.every(isPlainObject)) {
            const validatedRows = [];
            for (const row of validated.rows) {
                const validatedRow = {};
                if (typeof row.minimum === "number") validatedRow.minimum = row.minimum;
                if (typeof row.flexible === "boolean") validatedRow.flexible = row.flexible;
                if (Object.keys(validatedRow).length > 0) validatedRows.push(validatedRow);
            }
            if (validatedRows.length > 0) {
                validated.rows = validatedRows;
            } else {
                logger.log("LazyHGrid rows must contain valid minimum or flexible values; ignoring", "warning");
                delete validated.rows;
            }
        } else if (validated.rows !== undefined) {
            logger.log("LazyHGrid rows must be an array of dictionaries; ignoring", "warning");
            delete validated.rows;
        }

        if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
            logger.log("LazyHGrid spacing must be numeric; ignoring", "warning");
            delete validated.spacing;
        }

        if (typeof validated.alignment === "string") {
            if (!["top", "center", "bottom"].includes(validated.alignment)) {
                logger.log(`LazyHGrid alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
                delete validated.alignment;
            }
        } else if (validated.alignment !== undefined) {
            logger.log("LazyHGrid alignment must be 'top', 'center', or 'bottom'; ignoring", "warning");
            delete validated.alignment;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-grid aui-lazyhgrid";
        node.style.gridTemplateRows = trackList(properties.rows);
        node.style.gridAutoFlow = "column";
        node.style.gap = `${properties.spacing ?? 0}px`;
        node.style.alignItems = ALIGN[properties.alignment] ?? "center";
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});

function isPlainObject(v) {
    return typeof v === "object" && v !== null && !Array.isArray(v);
}

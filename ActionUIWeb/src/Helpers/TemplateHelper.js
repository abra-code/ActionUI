// TemplateHelper.js — the data-driven repeater (template) infrastructure.
// Web analog of ActionUI/Helpers/TemplateHelper.swift (and the Android
// Helpers/TemplateHelper.kt).
//
// When a container (List now; later Section) declares a `template` subview
// instead of `children`, it renders one instance of the template per row in
// states["content"] ([[String]], set via the rows API). String properties in the
// template carry 1-based column references substituted per row:
//
//   $0  → all columns joined with ", "
//   $1  → column 0 (first column)
//   $2  → column 1
//   $N  → column N-1
//
// How the per-row view is built. Swift carries a templateContext on a throw-away
// ViewModel and lets containers re-enter the helper for their children; the web
// (like Android) instead substitutes the whole subtree eagerly, then builds the
// substituted copy through the normal registry pipeline — so a substituted
// container already holds substituted children, with no per-container special
// case. The one piece a leaf still needs — which container owns it and at which
// row, for action dispatch — rides on a child build context (`ctx.templateContext`),
// read by Button.
//
// Substitution is single-pass and multi-digit-safe (a regex replaces every $N in
// one sweep): a column value that itself contains "$2" is not re-substituted, and
// "$12" reads as column 12, not $1 then a literal 2. An out-of-range $N is left as
// its literal text (matching Swift / Android).
//
// Template instances are not host-addressable: every cloned element's id is
// forced to 0, so the build pipeline seeds/binds nothing (the web's equivalent of
// Swift's throw-away ViewModel) and per-row copies never collide on id. A nested
// `template` subview is left untouched.

import { ActionUIElement } from "../Common/ActionUIElement.js";
import { buildElementView } from "../Common/ActionUIRegistry.js";

const COLUMN_REF = /\$(\d+)/g;

// Substitutes $0 / $1 / $N column references in `str` against `row`.
export function substituteString(str, row) {
    return str.replace(COLUMN_REF, (match, digits) => {
        const n = Number(digits);
        if (n === 0) return row.join(", ");
        return n - 1 < row.length ? row[n - 1] : match;
    });
}

// Substitutes column references in every string, recursing through arrays and
// objects (numbers / booleans / null pass through).
function substituteValue(value, row) {
    if (typeof value === "string") return substituteString(value, row);
    if (Array.isArray(value)) return value.map((entry) => substituteValue(entry, row));
    if (value !== null && typeof value === "object") return substituteProperties(value, row);
    return value;
}

function substituteProperties(properties, row) {
    const out = {};
    for (const [key, value] of Object.entries(properties)) out[key] = substituteValue(value, row);
    return out;
}

// Returns a copy of `element` with column references substituted across its
// properties and routed subviews (children / content / label / rows), and every
// id forced to 0 (template instances aren't host-addressable). A nested
// `template` subview is left untouched.
export function substituteElement(element, row) {
    const properties = substituteProperties(element.properties ?? {}, row);
    let subviews = null;
    if (element.subviews) {
        subviews = {};
        for (const [key, value] of Object.entries(element.subviews)) {
            if (key === "template") {
                subviews[key] = value; // nested repeater prototype: left untouched
            } else if (Array.isArray(value)) {
                // "children" ([ActionUIElement]) or "rows" ([[ActionUIElement]]).
                subviews[key] = value.map((entry) => Array.isArray(entry)
                    ? entry.map((child) => substituteElement(child, row))
                    : substituteElement(entry, row));
            } else {
                subviews[key] = substituteElement(value, row); // "content" / "label"
            }
        }
    }
    return new ActionUIElement(0, element.type, properties, subviews);
}

// Builds one template instance for `row`: substitutes the subtree, then builds it
// through the registry on a child context carrying the template context so a
// Button inside dispatches with the owning container's id as viewID and `rowIndex`
// as viewPartID (the Swift / Android action convention). Returns the HTMLElement.
export function buildTemplateRow(template, row, rowIndex, parentID, ctx) {
    const substituted = substituteElement(template, row);
    const childCtx = { ...ctx, templateContext: { parentID, rowIndex } };
    childCtx.build = (element) => buildElementView(element, childCtx);
    return childCtx.build(substituted);
}

// Wires a container's `template` data-driven mode: one substituted template
// instance per row in states["content"] (set via the rows API), re-rendered in
// place on every rows change. The container `node` keeps its own layout (flex /
// grid); the instances are its direct children. Used by the Lazy stacks/grids
// (List has its own selectable variant in buildDataRows). valueType stays none -
// the rows live in the "content" state, not the value. Returns `node`.
export function renderTemplateRows(node, element, template, ctx) {
    let rows = [];
    const renderRows = () => {
        node.replaceChildren(...rows.map((row, index) =>
            buildTemplateRow(template, row, index, element.id, ctx)));
    };
    if (element.id > 0) {
        ctx.model.bindState(element.id, {
            getState: (key) => (key === "content" ? rows : undefined),
            setState: (key, value) => {
                if (key !== "content") return;
                rows = Array.isArray(value) ? value : [];
                renderRows();
            },
        });
    }
    renderRows();
    return node;
}

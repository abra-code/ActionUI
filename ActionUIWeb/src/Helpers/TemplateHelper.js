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
// read by Button and Toggle.
//
// Boolean properties from row data. "isOn", "disabled" and "hidden" written as a
// string in a template are read as a Boolean after substitution (rowBool): "true"
// or "1" is on, "false", "0" or an empty string is off, in any letter case; any
// other text is off, with one warning. The same rule as Swift and Android.
//
// Row-bound Toggle. The row data is the source of truth for a Toggle in a template.
// When its "isOn" is exactly one column reference ("$N"), the substituted copy
// carries that column as the internal "$isOnColumn" property (a name no schema
// property can have), and a user toggle writes "true" or "false" into that cell
// through ActionUIModel.writeRowCell before its actionID fires. Any other "isOn"
// leaves the Toggle display-only.
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
import { commonRowPrefix } from "./RowDiff.js";

const COLUMN_REF = /\$(\d+)/g;
const SINGLE_COLUMN_REF = /^\$(\d+)$/;

// The properties a template may give as a string, read as a Boolean after substitution.
const ROW_BOOL_KEYS = ["isOn", "disabled", "hidden"];

// The internal property a substituted Toggle carries when its isOn names one column.
export const IS_ON_COLUMN_KEY = "$isOnColumn";

// Reads row text as a Boolean: "true" or "1" is on, "false", "0" or "" is off, in
// any letter case. Returns null for any other text (the caller treats it as off).
export function rowBool(text) {
    switch (String(text).toLowerCase()) {
        case "true": case "1": return true;
        case "false": case "0": case "": return false;
        default: return null;
    }
}

// The text a toggled cell stores.
export const rowBoolText = (flag) => (flag ? "true" : "false");

// The 0-based column a property names when it is exactly one column reference
// ("$N", N of 1 or more), else null. "$0" (all columns) does not name one column.
export function singleColumnIndex(value) {
    if (typeof value !== "string") return null;
    const match = SINGLE_COLUMN_REF.exec(value);
    if (!match) return null;
    const n = Number(match[1]);
    return n >= 1 ? n - 1 : null;
}

// A warning logged the first time it is seen: a template builds once per row on
// every refresh, so a per-row warning would otherwise repeat without end.
const warned = new Set();
export function warnOnce(message, logger) {
    if (warned.has(message)) return;
    warned.add(message);
    logger?.log(message, "warning");
}

// A copy of `rows` with one cell replaced; a row shorter than `column` is padded
// with empty strings. Shared by the row stores' setCell (List, Table, the template
// repeater), which keep their built row nodes in place after a user edit.
export function rowsWithCell(rows, rowIndex, column, text) {
    return rows.map((row, index) => {
        if (index !== rowIndex) return row;
        const next = [...row];
        while (next.length <= column) next.push("");
        next[column] = text;
        return next;
    });
}

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
export function substituteElement(element, row, logger) {
    const raw = element.properties ?? {};
    const properties = substituteProperties(raw, row);
    // Boolean properties written as a string take their value from the row.
    for (const key of ROW_BOOL_KEYS) {
        if (typeof raw[key] !== "string") continue;
        const flag = rowBool(properties[key]);
        if (flag === null) {
            warnOnce(`${element.type} ${key} '${properties[key]}' in a template row is not a Boolean (true, false, 1, 0 or empty); treating as false`, logger);
        }
        properties[key] = flag ?? false;
    }
    if (element.type === "Toggle") {
        const column = singleColumnIndex(raw.isOn);
        if (column !== null) properties[IS_ON_COLUMN_KEY] = column;
    }
    let subviews = null;
    if (element.subviews) {
        subviews = {};
        for (const [key, value] of Object.entries(element.subviews)) {
            if (key === "template") {
                subviews[key] = value; // nested repeater prototype: left untouched
            } else if (Array.isArray(value)) {
                // "children" ([ActionUIElement]) or "rows" ([[ActionUIElement]]).
                subviews[key] = value.map((entry) => Array.isArray(entry)
                    ? entry.map((child) => substituteElement(child, row, logger))
                    : substituteElement(entry, row, logger));
            } else {
                subviews[key] = substituteElement(value, row, logger); // "content" / "label"
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
    const substituted = substituteElement(template, row, ctx.logger);
    const childCtx = { ...ctx, templateContext: { parentID, rowIndex } };
    childCtx.build = (element) => buildElementView(element, childCtx);
    return childCtx.build(substituted);
}

// Wires a container's `template` data-driven mode: one substituted template
// instance per row in states["content"] (set via the rows API). The container
// `node` keeps its own layout (flex / grid); the instances are its direct children.
// Used by the Lazy stacks/grids (List has its own selectable variant in
// buildDataRows). valueType stays none - the rows live in the "content" state, not
// the value. Returns `node`.
//
// A rows change is applied with a common-prefix diff (Helpers/RowDiff.js), not a
// full rebuild: an append (the streaming hot path, where the rows API re-sends the
// whole array) keeps every unchanged prefix instance in place and builds only the
// new tail; a truncation drops the tail; a prepend / mid-list edit rebuilds from the
// first change.
export function renderTemplateRows(node, element, template, ctx) {
    let rows = [];
    const applyRows = (next) => {
        next = Array.isArray(next) ? next : [];
        const keep = commonRowPrefix(rows, next);
        while (node.children.length > keep) node.children[node.children.length - 1].remove();
        for (let index = keep; index < next.length; index++) {
            node.appendChild(buildTemplateRow(template, next[index], index, element.id, ctx));
        }
        rows = next;
    };
    if (element.id > 0) {
        ctx.model.bindState(element.id, {
            getState: (key) => (key === "content" ? rows : undefined),
            setState: (key, value) => { if (key === "content") applyRows(value); },
            // A user edit of a row-bound control (a Toggle): the control already shows
            // the new state, so the rows are updated and the instances stay in place.
            setCell: (rowIndex, column, text) => {
                if (rowIndex < 0 || rowIndex >= rows.length) return false;
                rows = rowsWithCell(rows, rowIndex, column, text);
                return true;
            },
        });
    }
    applyRows([]);
    return node;
}

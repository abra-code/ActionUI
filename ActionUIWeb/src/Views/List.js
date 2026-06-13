// List.js — List element.
// Web analog of ActionUI/Views/List.swift (and ActionUIAndroid Views/List.kt).
//
// A vertical collection of rows. Apple's List has three modes:
//
//   1. Homogeneous (itemType)  — one cell type per row, rows supplied as data.
//   2. Heterogeneous (children) — arbitrary child views, one per row.
//   3. Template (data-driven)  — one substituted template instance per row.
//
// Web ships **mode 2 (children)** now: the only mode that renders from a static
// document with no host data (Android frames it the same way). Modes 1 and 3 are
// data-driven — they read rows from `states["content"]` — and ride with the rows
// API that lands alongside Table; the `content` state is seeded here so they slot
// in later. `itemType`/`template` properties are still validated verbatim.
//
// Selection (value bridge). Apple exposes the selection as a `[String]`; the web
// value vocabulary is scalar, so — like Android's tab-joined string transport —
// the selection is carried as a **String**: the stringified id of the selected
// child (empty string = nothing selected). A host reads/writes it with
// get/setString(listID). Selection is interactive only when a list-level
// `actionID` is present (Apple's selectable mode): clicking a row selects it,
// highlights it, and fires `actionID` (the host then reads the selection — Apple
// fires with no context and reads model.value, so the web matches and sends none).
// A row whose click lands on an interactive control (a Button cell) lets that
// control consume the tap, so per-row actions and row selection coexist — the web
// can disambiguate by event target, where Apple asks for Label/Text children.
//
// Properties (mirroring List.swift):
//   itemType         { viewType, actionContext, actionID, dataInterpretation } —
//                    homogeneous cell config (validated; rendered with the rows API).
//   actionID         Fires on selection change (enables selectable mode).
//   doubleClickActionID  macOS double-click; row index as context (data modes).
//   listStyle        "automatic"|"plain"|"inset"|"sidebar" (the macOS set).
//   listRowBackground / listRowSeparator / listRowSeparatorTint / listRowInsets
//                    Row styling applied uniformly to every row.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction, resolveColor } from "../Common/ModifierResolver.js";

// The macOS-valid listStyles (the web's default skin is macOS-flavored). The
// other SwiftUI styles ("grouped", "insetGrouped") are iOS/tvOS/visionOS-only and
// warn here exactly as they do on macOS.
const VALID_LIST_STYLES = ["automatic", "plain", "inset", "sidebar"];
const ITEM_VIEW_TYPES = ["Text", "Button", "Image", "AsyncImage"];
const DATA_INTERPRETATIONS = ["path", "systemName", "assetName", "resourceName", "mixed"];
const ITEM_ACTION_CONTEXTS = ["title", "rowIndex"];

// Interactive descendants that should consume their own tap instead of selecting
// the row (so a Button cell fires its action while a Text cell selects the row).
const INTERACTIVE_SELECTOR = "button, input, select, textarea, a";

register("List", {
    // The selected child id, as a String ("" = nothing selected). See header.
    valueType: "string",

    // Mirrors List.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // itemType — normalized to an object with a valid viewType (Apple always
        // writes back a validated itemType, defaulting to Text).
        const itemType = (typeof properties.itemType === "object" && properties.itemType !== null)
            ? { ...properties.itemType } : { viewType: "Text" };
        const viewType = typeof itemType.viewType === "string" ? itemType.viewType : "Text";
        if (!ITEM_VIEW_TYPES.includes(viewType)) {
            logger.log("List itemType.viewType must be 'Text', 'Button', 'Image', or 'AsyncImage'; defaulting to Text", "warning");
            itemType.viewType = "Text";
        }
        if (viewType === "Image" && !DATA_INTERPRETATIONS.includes(itemType.dataInterpretation)) {
            logger.log(`List itemType.dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for ${viewType}; defaulting to systemName`, "warning");
            itemType.dataInterpretation = "systemName";
        }
        if (viewType === "Button" && !ITEM_ACTION_CONTEXTS.includes(itemType.actionContext)) {
            logger.log("List itemType.actionContext must be 'title' or 'rowIndex' for Button; defaulting to title", "warning");
            itemType.actionContext = "title";
        }
        validated.itemType = itemType;

        // doubleClickActionID — must be a string, else dropped.
        if (validated.doubleClickActionID !== undefined && typeof validated.doubleClickActionID !== "string") {
            logger.log("List doubleClickActionID must be a string; ignoring", "warning");
            delete validated.doubleClickActionID;
        }

        // listStyle — must be a String valid on this (macOS-flavored) platform.
        if (typeof validated.listStyle === "string") {
            if (!VALID_LIST_STYLES.includes(validated.listStyle)) {
                logger.log(`List listStyle '${validated.listStyle}' is not available on this platform; ignoring`, "warning");
                delete validated.listStyle;
            }
        } else if (validated.listStyle !== undefined) {
            logger.log("List listStyle must be a String; ignoring", "warning");
            delete validated.listStyle;
        }

        // listRowBackground — must be a color string.
        if (validated.listRowBackground !== undefined && typeof validated.listRowBackground !== "string") {
            logger.log("List listRowBackground must be a color string; ignoring", "warning");
            delete validated.listRowBackground;
        }

        // listRowSeparator — must be one of visible/hidden/automatic.
        if (typeof validated.listRowSeparator === "string") {
            if (!["visible", "hidden", "automatic"].includes(validated.listRowSeparator)) {
                logger.log("List listRowSeparator must be 'visible', 'hidden', or 'automatic'; ignoring", "warning");
                delete validated.listRowSeparator;
            }
        } else if (validated.listRowSeparator !== undefined) {
            logger.log("List listRowSeparator must be a String; ignoring", "warning");
            delete validated.listRowSeparator;
        }

        // listRowSeparatorTint — must be a color string.
        if (validated.listRowSeparatorTint !== undefined && typeof validated.listRowSeparatorTint !== "string") {
            logger.log("List listRowSeparatorTint must be a color string; ignoring", "warning");
            delete validated.listRowSeparatorTint;
        }

        // listRowInsets — must be a number or an edge dictionary.
        if (validated.listRowInsets !== undefined) {
            const insets = validated.listRowInsets;
            const isNumber = typeof insets === "number";
            const isDict = typeof insets === "object" && insets !== null && !Array.isArray(insets);
            if (!isNumber && !isDict) {
                logger.log("List listRowInsets must be a number or dictionary {top, leading, bottom, trailing}; ignoring", "warning");
                delete validated.listRowInsets;
            }
        }

        return validated;
    },

    // Nothing selected initially (Apple's empty [String] → the empty string here).
    initialValue: () => "",

    // The documented row store (states["content"] = [[String]]); empty until a
    // host fills it via the rows API. Seeded so the data modes can read and fill it.
    initialStates: () => ({ content: [] }),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-list";
        if (typeof properties.listStyle === "string") {
            node.dataset.auiListStyle = properties.listStyle;
            node.classList.add(`aui-list-style-${properties.listStyle}`);
        }
        // The list owns its actionID semantics (selection), so it opts out of the
        // generic click→dispatch handler in applyViewModifiers.
        markHandlesAction(node);

        const children = element.children();
        const selectable = typeof properties.actionID === "string";
        const rowStyle = computeRowStyle(properties, ctx.logger);

        if (children.length === 0) {
            // Data-driven modes (itemType / template) read from states["content"],
            // which lands with the rows API; render an empty list for now.
            node.classList.add("aui-list-empty");
            ctx.logger.log("List: data-driven modes (itemType / template) are not yet rendered on web; provide children, or drive rows via the rows API (lands with Table). Rendering an empty list.", "info");
            return node;
        }

        if (selectable) {
            node.setAttribute("role", "listbox");
        }

        const rows = [];
        let selectedId = "";

        const applySelectionStyles = () => {
            for (const row of rows) {
                const isSelected = selectable && row.dataset.auiRowId === selectedId && selectedId !== "";
                row.classList.toggle("aui-list-row-selected", isSelected);
                if (selectable) row.setAttribute("aria-selected", isSelected ? "true" : "false");
            }
        };

        const selectRow = (id, fromUser) => {
            if (!selectable || id === selectedId) return;
            selectedId = id;
            applySelectionStyles();
            // Apple fires the selection-change actionID with no context and lets
            // the host read model.value; the web carries the selection as the
            // element value (getString), so it matches — no context sent.
            if (fromUser) ctx.model.dispatchAction(properties.actionID, element.id, 0, null);
        };

        for (const child of children) {
            const row = document.createElement("div");
            row.className = "aui-list-row";
            applyRowStyle(row, rowStyle);

            const childNode = ctx.build(child);
            row.appendChild(childNode);

            if (selectable) {
                row.dataset.auiRowId = String(child.id);
                row.setAttribute("role", "option");
                row.setAttribute("aria-selected", "false");
                row.tabIndex = 0;
                row.addEventListener("click", (event) => {
                    // A click on an interactive cell (e.g. a Button) is the cell's
                    // own; only a click on inert content selects the row.
                    const control = event.target.closest?.(INTERACTIVE_SELECTOR);
                    if (control && row.contains(control)) return;
                    selectRow(row.dataset.auiRowId, true);
                });
                row.addEventListener("keydown", (event) => {
                    if (event.key === "Enter" || event.key === " ") {
                        event.preventDefault();
                        selectRow(row.dataset.auiRowId, true);
                    }
                });
            }

            rows.push(row);
            node.appendChild(row);
        }

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => selectedId,
                setValue: (value) => { // programmatic: silent (no actionID dispatch)
                    selectedId = String(value ?? "");
                    applySelectionStyles();
                },
            });
        }

        return node;
    },
});

// Resolves the row-styling properties once; the result is applied to every row.
function computeRowStyle(properties, logger) {
    const style = {};
    if (typeof properties.listRowBackground === "string") {
        style.background = resolveColor(properties.listRowBackground, logger);
    }
    if (typeof properties.listRowSeparatorTint === "string") {
        style.separatorColor = resolveColor(properties.listRowSeparatorTint, logger);
    }
    style.separatorHidden = properties.listRowSeparator === "hidden";
    const insets = properties.listRowInsets;
    if (typeof insets === "number") {
        style.padding = `${insets}px`;
    } else if (typeof insets === "object" && insets !== null) {
        const { top = 0, leading = 0, bottom = 0, trailing = 0 } = insets;
        style.padding = `${top}px ${trailing}px ${bottom}px ${leading}px`;
    }
    return style;
}

function applyRowStyle(row, style) {
    if (style.background) row.style.backgroundColor = style.background;
    if (style.padding) row.style.padding = style.padding;
    if (style.separatorHidden) row.classList.add("aui-list-row-no-separator");
    if (style.separatorColor) row.style.borderBottomColor = style.separatorColor;
}

// List.js — List element.
// Web analog of ActionUI/Views/List.swift (and ActionUIAndroid Views/List.kt).
//
// A vertical collection of rows. Apple's List has three modes:
//
//   1. Homogeneous (itemType)  — one cell type per row, rows supplied as data.
//   2. Heterogeneous (children) — arbitrary child views, one per row.
//   3. Template (data-driven)  — one substituted template instance per row.
//
// Web ships all three modes. Mode precedence matches Swift / Android: template
// (when present) → children → homogeneous.
//
// Data-driven rows. Modes 1 and 3 read their rows from `states["content"]`
// ([[String]]) via the rows API on Window (set/append/clearElementRows) — the
// same store Table uses. The List binds its "content" state, so a host
// set/append/clear re-renders the rows in place. Homogeneous mode displays each
// row's **first column** (matching Apple/Android) as the `itemType.viewType`
// cell; the web renders real Image / AsyncImage cells (Android downgrades those
// to text, its B2 deferral). Template mode renders one substituted template
// instance per row ($1/$2/$N column references; see Helpers/TemplateHelper.js).
//
// Selection (value bridge). Apple exposes the selection as a `[String]`; the web
// value vocabulary is scalar, so — like Android's tab-joined string transport —
// the selection is carried as a **String**. In children mode it is the
// stringified id of the selected child; in the data-driven modes it is the
// selected row's columns tab-joined ("" = nothing selected). A host reads/writes
// it with get/setString(listID). A row can also be selected programmatically
// (without replacing the rows, firing no actionID) via the model selection API —
// selectElementRow(index) / selectElementRowWithContent(text, column) /
// clearElementSelection (the data-driven modes only; heterogeneous children select
// by child id). Selection is interactive only when a list-level
// `actionID` is present (Apple's selectable mode): clicking a row selects it,
// highlights it, and fires `actionID` (the host then reads the selection — Apple
// fires with no context and reads model.value, so the web matches and sends none).
// A row whose click lands on an interactive control (a Button cell) lets that
// control consume the tap, so per-row actions and row selection coexist — the web
// can disambiguate by event target, where Apple asks for Label/Text children.
//
// Properties (mirroring List.swift):
//   itemType         { viewType, actionContext, actionID, dataInterpretation } —
//                    homogeneous cell config.
//   actionID         Fires on selection change (enables selectable mode).
//   onRefreshActionID String; when set, enables pull-to-refresh: a downward pull at
//                    the top fires this actionID and an indicator stays up until the
//                    client delivers fresh rows to this list or anything inside it
//                    (the web side of SwiftUI's .refreshable; see PullToRefreshHelper).
//   doubleClickActionID  macOS double-click; row index as context (data modes).
//   listStyle        "automatic"|"plain"|"inset"|"sidebar" (the macOS set).
//   listRowBackground / listRowSeparator / listRowSeparatorTint / listRowInsets
//                    Row styling applied uniformly to every row.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction, resolveColor } from "../Common/ModifierResolver.js";
import { buildDataImageCell } from "../Helpers/DataImageCell.js";
import { buildTemplateRow } from "../Helpers/TemplateHelper.js";
import { commonRowPrefix } from "../Helpers/RowDiff.js";
import { navigateRowsOnKey } from "../Helpers/RowKeyboardNav.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { flatContainerBinding } from "../Helpers/InsertionHelper.js";

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
    // The selected child id / row, as a String ("" = nothing selected). See header.
    valueType: "string",

    // Opts into the pull-to-refresh build wrapper (Helpers/PullToRefreshHelper.js):
    // a no-op unless `onRefreshActionID` is set. Apple parity is `.refreshable`.
    refreshable: true,

    // Children mode accepts runtime insertions (insertElement / removeElement);
    // each inserted child is wrapped in a row and joins selection like the
    // statically authored rows. The data-driven modes mutate via the rows API
    // (set/append/clearElementRows), not this container.
    insertableContainers: { children: ContainerShape.FLAT },

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

        // onRefreshActionID (pull-to-refresh) — must be a string, else dropped.
        if (validated.onRefreshActionID !== undefined && typeof validated.onRefreshActionID !== "string") {
            logger.log("List onRefreshActionID must be a string; ignoring", "warning");
            delete validated.onRefreshActionID;
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
    // host fills it via the rows API. Read by the data-driven modes.
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

        // Mode precedence (matching List.swift / List.kt): template → children →
        // homogeneous.
        const template = element.template();
        if (template) {
            // Template (data-driven repeater): one substituted instance per content
            // row, reusing the shared data-row plumbing.
            return buildDataRows(node, element, properties, ctx, selectable, rowStyle,
                (row, index) => buildTemplateRow(template, row, index, element.id, ctx));
        }

        if (children.length > 0) {
            return buildChildrenRows(node, element, properties, ctx, children, selectable, rowStyle);
        }

        // Homogeneous (itemType) mode: each row renders its first column as a
        // single typed cell. validateProperties has already normalized itemType.
        const itemType = (typeof properties.itemType === "object" && properties.itemType !== null)
            ? properties.itemType : { viewType: "Text" };
        return buildDataRows(node, element, properties, ctx, selectable, rowStyle,
            (row, index) => renderHomogeneousCell(itemType, row[0] ?? "", index, element, ctx));
    },
});

// Heterogeneous children mode: each child is a full ActionUI view built through
// the registry into a row. Selection (when the list has an actionID) is carried
// as the stringified selected child id. Selection styling reads the live rows
// (querySelectorAll), so a runtime-inserted child (insertElement) participates
// without extra bookkeeping.
function buildChildrenRows(node, element, properties, ctx, children, selectable, rowStyle) {
    if (selectable) node.setAttribute("role", "listbox");

    let selectedId = "";

    const applySelectionStyles = () => {
        for (const row of node.querySelectorAll(".aui-list-row")) {
            const isSelected = selectable && row.dataset.auiRowId === selectedId && selectedId !== "";
            row.classList.toggle("aui-list-row-selected", isSelected);
            if (selectable) row.setAttribute("aria-selected", isSelected ? "true" : "false");
        }
    };

    const selectRow = (id, fromUser) => {
        if (!selectable || id === selectedId) return;
        selectedId = id;
        applySelectionStyles();
        // Apple fires the selection-change actionID with no context and lets the
        // host read model.value; the web carries the selection as the element
        // value (getString), so it matches — no context sent.
        if (fromUser) ctx.model.dispatchAction(properties.actionID, element.id, 0, null);
    };

    // Wraps one built child view in a row + selection wiring. Shared by the
    // initial build and runtime insertion (the container binding's `wrap`).
    const wrapRow = (childNode, childId) => {
        const row = document.createElement("div");
        row.className = "aui-list-row";
        applyRowStyle(row, rowStyle);
        row.appendChild(childNode);
        if (selectable) {
            row.dataset.auiRowId = String(childId);
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
                    return;
                }
                // Arrow / Home / End move selection+focus to the adjacent row. The
                // current position is resolved live (insertion can reorder `slots`).
                const i = slots.findIndex((slot) => slot.dom === row);
                navigateRowsOnKey(event, i, slots.length, (target) => {
                    selectRow(slots[target].dom.dataset.auiRowId, true); // string id, like the click path
                    slots[target].dom.focus();
                });
            });
        }
        return row;
    };

    const slots = children.map((child) => {
        const row = wrapRow(ctx.build(child), child.id);
        node.appendChild(row);
        return { id: child.id, dom: row };
    });

    if (element.id > 0) {
        ctx.model.bind(element.id, {
            getValue: () => selectedId,
            setValue: (value) => { // programmatic: silent (no actionID dispatch)
                selectedId = String(value ?? "");
                applySelectionStyles();
            },
        });
        // The insertion container: a new child is wrapped via wrapRow and tracked
        // by its element id (so before/after-sibling positions resolve).
        ctx.model.bindContainer(element.id, "children",
            flatContainerBinding(node, slots, { wrap: (childNode, id) => wrapRow(childNode, id) }));
    }

    return node;
}

// Shared plumbing for the data-driven row modes (homogeneous itemType now, and
// the template repeater next): rows come from states["content"], and the
// selection rides as the tab-joined row String. `renderCell(row, index)` builds
// the mode's row body; everything else (selection, styling, re-render on a rows
// change) is identical across the modes.
function buildDataRows(node, element, properties, ctx, selectable, rowStyle, renderCell) {
    if (selectable) node.setAttribute("role", "listbox");

    let rows = [];
    let rowNodes = [];
    let selectedRow = ""; // the selected row's columns tab-joined ("" = none)

    const rowValue = (row) => row.join("\t");

    const applySelectionStyles = () => {
        rowNodes.forEach((rowNode, i) => {
            const isSelected = selectable && selectedRow !== "" && rowValue(rows[i]) === selectedRow;
            rowNode.classList.toggle("aui-list-row-selected", isSelected);
            if (selectable) rowNode.setAttribute("aria-selected", isSelected ? "true" : "false");
        });
    };

    const selectRow = (index, fromUser) => {
        const value = rowValue(rows[index]);
        if (value === selectedRow) return;
        selectedRow = value;
        applySelectionStyles();
        // Apple fires the selection actionID with no context and reads
        // model.value; the web matches — the selection is the element value.
        if (fromUser) ctx.model.dispatchAction(properties.actionID, element.id, 0, null);
    };

    const buildRowNode = (row, index) => {
        const rowNode = document.createElement("div");
        rowNode.className = "aui-list-row";
        applyRowStyle(rowNode, rowStyle);
        rowNode.appendChild(renderCell(row, index));
        if (selectable) {
            rowNode.setAttribute("role", "option");
            rowNode.setAttribute("aria-selected", "false");
            rowNode.tabIndex = 0;
            rowNode.addEventListener("click", (event) => {
                const control = event.target.closest?.(INTERACTIVE_SELECTOR);
                if (control && rowNode.contains(control)) return;
                selectRow(index, true);
            });
            rowNode.addEventListener("keydown", (event) => {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    selectRow(index, true);
                    return;
                }
                // Arrow / Home / End move the selection (and focus) to the adjacent
                // row, the listbox keyboard pattern - else the key scrolls the parent.
                navigateRowsOnKey(event, index, rowNodes.length, (target) => {
                    selectRow(target, true);
                    rowNodes[target].focus();
                });
            });
            rowNode.addEventListener("dblclick", () => {
                if (typeof properties.doubleClickActionID === "string" && rowValue(row) === selectedRow) {
                    ctx.model.dispatchAction(properties.doubleClickActionID, element.id, 0, index);
                }
            });
        }
        return rowNode;
    };

    // Apply a new rows array with a common-prefix diff (Helpers/RowDiff.js) instead
    // of a full rebuild: an append (the rows API re-sends the whole array) keeps
    // every unchanged prefix row - its node, selection styling and wiring - in place
    // and builds only the new tail; a prepend / mid-list edit rebuilds from the first
    // change (which re-bakes the shifted per-row indices in the click/dblclick
    // handlers). The diff preserves the selection across an append.
    const applyRows = (next) => {
        next = Array.isArray(next) ? next : [];
        const keep = commonRowPrefix(rows, next);
        while (rowNodes.length > keep) { rowNodes[rowNodes.length - 1].remove(); rowNodes.pop(); }
        for (let index = keep; index < next.length; index++) {
            const rowNode = buildRowNode(next[index], index);
            rowNodes.push(rowNode);
            node.appendChild(rowNode);
        }
        rows = next;
        node.classList.toggle("aui-list-empty", rows.length === 0);
        // A rows change that drops the selected row clears the selection.
        if (selectedRow !== "" && !rows.some((row) => rowValue(row) === selectedRow)) selectedRow = "";
        applySelectionStyles();
    };

    if (element.id > 0) {
        // The rows store: set/append/clearElementRows route through here and
        // re-render the rows in place (incrementally - see applyRows).
        ctx.model.bindState(element.id, {
            getState: (key) => (key === "content" ? rows : undefined),
            setState: (key, value) => { if (key === "content") applyRows(value); },
        });
        // The selection value: the selected row tab-joined; highlighted silently
        // when set programmatically.
        ctx.model.bind(element.id, {
            getValue: () => selectedRow,
            setValue: (value) => {
                selectedRow = String(value ?? "");
                applySelectionStyles();
            },
        });
    }

    applyRows([]);
    return node;
}

// One homogeneous itemType cell: the row's first column rendered as the
// itemType.viewType. Text shows the value; Button fires itemType.actionID
// (context = the row index or the value) and consumes its tap; Image / AsyncImage
// render a real image (via the shared data-image-cell helper).
function renderHomogeneousCell(itemType, value, index, element, ctx) {
    const viewType = itemType.viewType ?? "Text";
    if (viewType === "Button") {
        const button = document.createElement("button");
        button.className = "aui-list-button";
        button.textContent = value;
        button.addEventListener("click", (event) => {
            event.stopPropagation(); // the cell's own tap, not row selection
            if (typeof itemType.actionID === "string") {
                const context = itemType.actionContext === "rowIndex" ? index : value;
                ctx.model.dispatchAction(itemType.actionID, element.id, 0, context);
            }
        });
        return button;
    }
    if (viewType === "Image") {
        return buildDataImageCell(value, itemType.dataInterpretation ?? "systemName", ctx.logger, "List");
    }
    if (viewType === "AsyncImage") {
        const img = document.createElement("img");
        img.className = "aui-data-image";
        img.loading = "lazy";
        img.src = value;
        img.alt = "";
        return img;
    }
    const span = document.createElement("span");
    span.textContent = value;
    return span;
}

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

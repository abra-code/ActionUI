// ActionUIElement.js — parse raw JSON into the element tree.
// Web analog of ActionUI/Common/ActionUIElement.swift (PoC subset).
//
// {
//   "type": "VStack",
//   "id": 1,              // Optional: positive integer for programmatic interaction
//   "properties": {},     // Optional: view-specific properties
//   "children": []        // Optional: child elements (stored in subviews.children)
// }
//
// Subset routed so far: the "children" and "destinations" (arrays); "content",
// "label", "template", "sidebar", "detail" and "destination" (single); plus "rows"
// (array-of-arrays, for Grid's GridRows). "label" is the custom-trigger view
// (Menu's label-instead-of-title; later Button/Toggle). "template" is the
// data-driven repeater's per-row prototype (List's template mode; later Section).
// "sidebar"/"content"/"detail" are NavigationSplitView's panes and "destinations"
// its detail targets; "destination" is NavigationLink's inline push target;
// "toolbar" is the array of ToolbarItem/ToolbarItemGroup chrome carriers any view
// may declare. "sheet"/"fullScreenCover"/"popover" are the element-level
// presentation modifiers any view may carry (Helpers/PresentationModifier.js).
// "overlay"/"background" are the view-valued decoration subviews any view may
// carry (Helpers/DecorationModifier.js) — drawn over / behind the element without
// affecting its layout size. Note "background" is also a string *property* (a
// color); the subview form (an object) is the decoration view, and the two can
// coexist (the color paints in front of the background view, per Apple).

let negativeIDCounter = -1;

// "contextMenu" is an array subview (the menu's action items) and "contextMenuPreview"
// a single one (the optional preview view) — mirroring SwiftUI's two-builder
// `.contextMenu(menuItems:preview:)`. Modeled as element subtrees so a designer can
// place real elements (an Image preview, an HStack), not a button-descriptor array.
// "swipeActions" is likewise an array subview (the swipe action Buttons) — SwiftUI's
// `.swipeActions(edge:allowsFullSwipe:)`, a ViewBuilder of real Button elements.
// "persistentToolbar" is the same ToolbarItem/ToolbarItemGroup shape as "toolbar", but
// declared on a NavigationStack / NavigationSplitView: its items stay in the bar on every
// screen inside that container instead of on the one screen that declares them. Only those
// two types read it (Views/NavigationStack.js, Views/NavigationSplitView.js); anywhere else
// it renders nothing and Window.fromJSON warns.
const SUBVIEW_ARRAY_KEYS = ["children", "destinations", "toolbar", "persistentToolbar", "contextMenu", "swipeActions"];
const SUBVIEW_SINGLE_KEYS = ["content", "label", "template", "sidebar", "detail", "destination",
    "sheet", "fullScreenCover", "popover", "overlay", "background", "contextMenuPreview", "safeAreaInset"];
// Keys whose value is an array of arrays of elements (Grid's "rows": one inner
// array per GridRow). Stored as [[ActionUIElement]], mirroring Grid.swift's
// `subviews["rows"] as? [[any ActionUIElementBase]]`.
const SUBVIEW_NESTED_ARRAY_KEYS = ["rows"];

// The element types that own a navigation context rather than being a single screen. A
// toolbar authored on one of these belongs to the CONTAINER, not to the screen it happens
// to sit next to. Defined here, in the model, because both the parser (below) and the
// renderer (Helpers/ToolbarHelper.js) have to agree on the list and the model is the layer
// neither of them can avoid importing.
export const NAVIGATION_CONTAINER_TYPES = new Set(["NavigationStack", "NavigationSplitView"]);

export function isNavigationContainer(type) {
    return NAVIGATION_CONTAINER_TYPES.has(type);
}

export class ActionUIElement {
    constructor(id, type, properties, subviews) {
        this.id = id;
        this.type = type;
        this.properties = properties;
        this.subviews = subviews; // null or { children: [ActionUIElement], content: ActionUIElement }
    }

    static fromObject(raw, logger) {
        if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
            logger.log(`Element must be a JSON object, got ${JSON.stringify(raw)}`, "error");
            return null;
        }
        if (typeof raw.type !== "string" || raw.type.length === 0) {
            logger.log(`Element missing required "type" string`, "error");
            return null;
        }
        const id = Number.isInteger(raw.id) ? raw.id : negativeIDCounter--;
        const properties = (typeof raw.properties === "object" && raw.properties !== null)
            ? raw.properties : {};

        let subviews = null;
        for (const key of SUBVIEW_ARRAY_KEYS) {
            if (Array.isArray(raw[key])) {
                const children = raw[key]
                    .map((child) => ActionUIElement.fromObject(child, logger))
                    .filter((child) => child !== null);
                subviews = subviews ?? {};
                subviews[key] = children;
            }
        }
        for (const key of SUBVIEW_SINGLE_KEYS) {
            if (typeof raw[key] === "object" && raw[key] !== null) {
                const child = ActionUIElement.fromObject(raw[key], logger);
                if (child !== null) {
                    subviews = subviews ?? {};
                    subviews[key] = child;
                }
            }
        }
        for (const key of SUBVIEW_NESTED_ARRAY_KEYS) {
            if (Array.isArray(raw[key])) {
                const rows = raw[key]
                    .filter((row) => Array.isArray(row))
                    .map((row) => row
                        .map((child) => ActionUIElement.fromObject(child, logger))
                        .filter((child) => child !== null));
                subviews = subviews ?? {};
                subviews[key] = rows;
            }
        }
        // The two ways a toolbar key can be authored where nothing will read it. Reported
        // here because fromObject visits every element exactly once, on EVERY parse path -
        // the window document, a LoadableView, a modal description, a runtime insertion -
        // so a misauthored sub-document says so too. The renderer stays silent: by build
        // time the key has already been folded into the container's items or dropped, and
        // a render-time warning would repeat on every pane switch.
        const container = NAVIGATION_CONTAINER_TYPES.has(raw.type);
        if (container && subviews?.toolbar?.length) {
            logger.log(
                `Deprecated: 'toolbar' on ${raw.type} (id ${id}) is treated as 'persistentToolbar' - its items `
                + "stay in the bar on every screen inside the container. Rename the key to silence this; declare "
                + "a screen's own toolbar on that screen's element instead.",
                "warning",
            );
        }
        if (!container && subviews?.persistentToolbar?.length) {
            logger.log(
                `'persistentToolbar' on ${raw.type} (id ${id}) is ignored - only NavigationStack and `
                + "NavigationSplitView have screens to keep it on. Use 'toolbar' for this view's own toolbar, or "
                + "move the key to the enclosing navigation container.",
                "warning",
            );
        }

        return new ActionUIElement(id, raw.type, properties, subviews);
    }

    static fromJSONString(jsonString, logger) {
        let raw;
        try {
            raw = JSON.parse(jsonString);
        } catch (error) {
            logger.log(`Invalid JSON: ${error.message}`, "error");
            return null;
        }
        return ActionUIElement.fromObject(raw, logger);
    }

    children() {
        return this.subviews?.children ?? [];
    }

    // The data-driven repeater's per-row prototype (List's template mode), or
    // null. Never built directly — the owner substitutes a copy per data row.
    template() {
        return this.subviews?.template ?? null;
    }

    // NavigationSplitView's panes and detail targets. sidebar() / content() /
    // detail() are single child elements (or null); destinations() is the array
    // of detail targets addressed by id (empty when absent).
    sidebar() {
        return this.subviews?.sidebar ?? null;
    }

    content() {
        return this.subviews?.content ?? null;
    }

    detail() {
        return this.subviews?.detail ?? null;
    }

    destinations() {
        return this.subviews?.destinations ?? [];
    }

    // NavigationLink's inline push target (Form 1), or null. Hoisted by id into
    // the enclosing NavigationStack's destination registry (it must carry an id
    // to be addressable, like Android's NavHost routes).
    destination() {
        return this.subviews?.destination ?? null;
    }

    // The view's toolbar chrome carriers (ToolbarItem / ToolbarItemGroup), or an
    // empty array. Rendered as screen chrome by ToolbarHelper, not built directly.
    toolbar() {
        return this.subviews?.toolbar ?? [];
    }

    // A navigation container's persistent chrome carriers: the items it keeps in the bar
    // on every screen inside it. Read through Helpers/ToolbarHelper.js's
    // persistentToolbarItems(), which also folds in the deprecated `toolbar` spelling.
    persistentToolbar() {
        return this.subviews?.persistentToolbar ?? [];
    }
}

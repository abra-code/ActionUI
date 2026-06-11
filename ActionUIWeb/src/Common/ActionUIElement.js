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
// PoC subset: only the "children" and "content" subview keys are routed.
// The full set (rows, destination, sidebar, detail, label, popover, template,
// toolbar, overlay, background, ...) comes with the elements that need them.

let negativeIDCounter = -1;

const SUBVIEW_ARRAY_KEYS = ["children"];
const SUBVIEW_SINGLE_KEYS = ["content"];

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
}

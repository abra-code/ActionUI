// Button.js — Button element.
// Web analog of ActionUI/Views/Button.swift (PoC subset).
//
// Properties: title (String, defaults to ""), role ("destructive" | "cancel"),
// buttonStyle ("automatic", "bordered", "borderedProminent", "borderless",
// "plain" — View-level property on Apple, handled here for styling).
// systemImage is out of PoC scope (needs the Material Symbols mapping).
// Action context carries the button title, matching the Swift implementation.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

const BUTTON_STYLES = new Set([
    "automatic", "bordered", "borderedProminent", "borderless", "plain",
]);

register("Button", {
    valueType: "none",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.buttonStyle !== undefined && !BUTTON_STYLES.has(validated.buttonStyle)) {
            logger.log(`Unknown buttonStyle "${validated.buttonStyle}", using "bordered"`, "warning");
            validated.buttonStyle = "bordered";
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("button");
        const style = properties.buttonStyle ?? "bordered";
        node.className = `aui-button aui-button-${style}`;
        if (properties.role === "destructive") node.classList.add("aui-button-destructive");
        node.textContent = properties.title ?? "";

        if (typeof properties.actionID === "string") {
            markHandlesAction(node);
            node.addEventListener("click", () => {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, {
                    title: properties.title ?? "",
                });
            });
        }
        return node;
    },
});

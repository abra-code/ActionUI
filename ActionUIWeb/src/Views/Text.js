// Text.js — Text element.
// Web analog of ActionUI/Views/Text.swift (PoC subset).
//
// Properties: text (String, defaults to ""), markdown (String, takes precedence
// over text). Web degrade: markdown is shown as its plain source string — no
// markdown formatting yet (needs a renderer decision; see Web_Porting_Notes.md).
// Observable value: the displayed string (get/setElementValue round-trips).

import { register } from "../Common/ActionUIRegistry.js";

// Markdown wins over text (matching Text.swift); web shows the source as plain text.
function displayString(properties) {
    return (typeof properties.markdown === "string")
        ? properties.markdown
        : (properties.text ?? "");
}

register("Text", {
    valueType: "string",

    // Mirrors Text.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.markdown !== undefined && typeof validated.markdown !== "string") {
            logger.log("Text markdown must be a String; ignoring", "warning");
            delete validated.markdown;
        }
        if (validated.text !== undefined && validated.markdown !== undefined) {
            logger.log("Text has both text and markdown; markdown takes precedence", "warning");
        }
        return validated;
    },

    initialValue: (element, properties) => displayString(properties),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("span");
        node.className = "aui-text";
        node.textContent = displayString(properties);
        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => node.textContent,
                setValue: (value) => { node.textContent = String(value); },
            });
        }
        return node;
    },
});

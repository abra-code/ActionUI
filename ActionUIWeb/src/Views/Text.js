// Text.js — Text element.
// Web analog of ActionUI/Views/Text.swift (PoC subset).
//
// Properties: text (String, defaults to ""). The "markdown" property from the
// schema is out of PoC scope (needs a markdown renderer decision).
// Observable value: the displayed string (get/setElementValue round-trips).

import { register } from "../Common/ActionUIRegistry.js";

register("Text", {
    valueType: "string",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.text !== undefined && typeof validated.text !== "string") {
            logger.log(`Text "text" must be a string, got ${JSON.stringify(validated.text)}`, "warning");
            validated.text = String(validated.text);
        }
        if (validated.markdown !== undefined) {
            logger.log(`Text "markdown" is not supported in the web PoC; using plain text`, "warning");
        }
        return validated;
    },

    initialValue: (element, properties) => properties.text ?? "",

    buildView: (element, properties, ctx) => {
        const node = document.createElement("span");
        node.className = "aui-text";
        node.textContent = properties.text ?? properties.markdown ?? "";
        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => node.textContent,
                setValue: (value) => { node.textContent = String(value); },
            });
        }
        return node;
    },
});

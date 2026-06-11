// TextField.js — TextField element.
// Web analog of ActionUI/Views/TextField.swift (PoC subset).
//
// Properties: title (String label), text (String initial value),
// prompt (String placeholder), actionID (fires on Enter and on focus loss,
// matching the documented macOS commit behavior), valueChangeActionID
// (fires on every value change, user or programmatic).
// Out of PoC scope: axis/lineLimit (multi-line), numeric format modes,
// textContentType.
// Observable value: the field string.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

register("TextField", {
    valueType: "string",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        for (const key of ["title", "text", "prompt"]) {
            if (validated[key] !== undefined && typeof validated[key] !== "string") {
                logger.log(`TextField "${key}" must be a string`, "warning");
                validated[key] = String(validated[key]);
            }
        }
        return validated;
    },

    initialValue: (element, properties) => properties.text ?? "",

    buildView: (element, properties, ctx) => {
        const input = document.createElement("input");
        input.type = "text";
        input.className = "aui-textfield";
        input.value = properties.text ?? "";
        if (properties.prompt) input.placeholder = properties.prompt;

        const dispatchValueChange = () => {
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        };
        const dispatchCommit = () => {
            if (typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id);
            }
        };

        markHandlesAction(input);
        input.addEventListener("input", dispatchValueChange);
        input.addEventListener("change", dispatchCommit); // fires on blur after edit
        input.addEventListener("keydown", (event) => {
            if (event.key === "Enter") dispatchCommit();
        });

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => input.value,
                setValue: (value) => {
                    input.value = String(value);
                    dispatchValueChange(); // programmatic changes also notify
                },
            });
        }

        // Optional leading label, shown when "title" is present (Form-style).
        if (properties.title) {
            const wrapper = document.createElement("label");
            wrapper.className = "aui-labeled-field";
            const label = document.createElement("span");
            label.className = "aui-field-label";
            label.textContent = properties.title;
            wrapper.append(label, input);
            return wrapper;
        }
        return input;
    },
});

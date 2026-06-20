// SecureField.js — SecureField element.
// Web analog of ActionUI/Views/SecureField.swift (and ActionUIAndroid Views/SecureField.kt).
//
// A masked text entry, rendered as an <input type="password">. It mirrors
// TextField but hides the typed characters; valueType is "string", so the host
// reads/writes the entry with get/setString(id).
//
// Properties (mirroring SecureField.swift):
//   title            String label, shown (Form-style) to the left when present.
//   text             initial String value (defaults to "").
//   prompt           placeholder shown inside the field when empty.
//   textContentType  one of "password" | "newPassword" | "oneTimeCode"; maps to
//                    the HTML autocomplete hint (the web analog of the Apple
//                    UITextContentType, which is ignored on macOS).
//   actionID         dispatched on submit (Enter) and on focus loss (blur after
//                    an edit), matching the documented macOS commit behavior.
//   valueChangeActionID  dispatched on every change (user or programmatic),
//                    matching TextField and the Apple binding setter.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { AUTOCOMPLETE } from "../Helpers/TextContentType.js";

// SecureField accepts only the masked-entry content types; their autocomplete
// tokens come from the shared TextContentType map (a subset of its full table).
const SECURE_CONTENT_TYPES = ["password", "newPassword", "oneTimeCode"];

register("SecureField", {
    valueType: "string",

    // Mirrors SecureField.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.text !== undefined && typeof validated.text !== "string") {
            logger.log("SecureField text must be a String; ignoring", "warning");
            delete validated.text;
        }
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("SecureField title must be a String; defaulting to empty string", "warning");
            delete validated.title;
        }
        if (validated.prompt !== undefined && typeof validated.prompt !== "string") {
            logger.log("SecureField prompt must be a String; defaulting to nil", "warning");
            delete validated.prompt;
        }
        // textContentType: only the secure set is allowed, else dropped.
        if (typeof validated.textContentType === "string"
            && SECURE_CONTENT_TYPES.includes(validated.textContentType)) {
            // keep as-is
        } else if (validated.textContentType !== undefined) {
            logger.log("SecureField textContentType must be 'password', 'newPassword', or 'oneTimeCode'; defaulting to nil", "warning");
            delete validated.textContentType;
        }

        return validated;
    },

    initialValue: (element, properties) => properties.text ?? "",

    buildView: (element, properties, ctx) => {
        const input = document.createElement("input");
        input.type = "password";
        input.className = "aui-securefield";
        input.value = properties.text ?? "";
        if (properties.prompt) input.placeholder = properties.prompt;
        if (typeof properties.textContentType === "string") {
            input.autocomplete = AUTOCOMPLETE[properties.textContentType];
        }

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

        // Optional leading label, shown when "title" is present (Form-style),
        // reusing TextField's labeled-field layout.
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

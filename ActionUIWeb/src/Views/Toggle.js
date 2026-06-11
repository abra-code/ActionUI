// Toggle.js — Toggle element.
// Web analog of ActionUI/Views/Toggle.swift (PoC subset).
//
// Properties: isOn (Boolean, defaults to false), title (String, defaults to
// "Toggle"), style ("switch" | "checkbox"; "button" style is out of PoC scope).
// actionID fires on user change; valueChangeActionID on any change.
// Observable value: Boolean on/off state.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

register("Toggle", {
    valueType: "boolean",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.isOn !== undefined && typeof validated.isOn !== "boolean") {
            logger.log(`Toggle "isOn" must be a boolean`, "warning");
            validated.isOn = Boolean(validated.isOn);
        }
        if (validated.style !== undefined && !["switch", "checkbox", "button"].includes(validated.style)) {
            logger.log(`Unknown Toggle style "${validated.style}", using "switch"`, "warning");
            validated.style = "switch";
        }
        if (validated.style === "button") {
            logger.log(`Toggle style "button" is not supported in the web PoC; using "switch"`, "warning");
            validated.style = "switch";
        }
        return validated;
    },

    initialValue: (element, properties) => properties.isOn ?? false,

    buildView: (element, properties, ctx) => {
        const style = properties.style ?? "switch";
        const wrapper = document.createElement("label");
        wrapper.className = `aui-toggle aui-toggle-${style}`;

        const input = document.createElement("input");
        input.type = "checkbox";
        input.checked = properties.isOn ?? false;

        const visual = document.createElement("span");
        visual.className = "aui-toggle-visual";

        const title = document.createElement("span");
        title.className = "aui-toggle-title";
        title.textContent = properties.title ?? "Toggle";

        // SwiftUI switch toggles put the label before the control;
        // checkboxes put the box first.
        if (style === "switch") wrapper.append(title, input, visual);
        else wrapper.append(input, visual, title);

        const dispatchValueChange = () => {
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        };

        markHandlesAction(wrapper);
        input.addEventListener("change", () => {
            dispatchValueChange();
            if (typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, {
                    isOn: input.checked,
                });
            }
        });

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => input.checked,
                setValue: (value) => {
                    input.checked = Boolean(value);
                    dispatchValueChange();
                },
            });
        }
        return wrapper;
    },
});

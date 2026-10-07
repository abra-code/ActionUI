// Toggle.js — Toggle element.
// Web analog of ActionUI/Views/Toggle.swift (PoC subset).
//
// Properties: isOn (Boolean, defaults to false), title (String, defaults to
// "Toggle"), style ("switch" | "checkbox"; "button" style is out of PoC scope).
// actionID fires on user change; valueChangeActionID on any change.
// Observable value: Boolean on/off state.
//
// In a data-driven template the row data is the source of truth (see
// Helpers/TemplateHelper.js): isOn is read from the row, and when it is exactly one
// column reference a user toggle writes "true" or "false" into that cell of the
// container's rows, then fires actionID with viewID = the container's id,
// viewPartID = the row index and context = the new Boolean (the Swift / Android
// convention; outside a template the context stays { isOn }). Any other isOn in a
// template is display-only. A rows change made by the host fires nothing.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { IS_ON_COLUMN_KEY, rowBoolText, warnOnce } from "../Helpers/TemplateHelper.js";

register("Toggle", {
    valueType: "boolean",

    // Mirrors Toggle.swift validateProperties (warning text included verbatim).
    // Valid styles follow the macOS set ("switch", "button", "checkbox"); the
    // "button" style is substituted at build time (see buildView).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.isOn !== undefined && typeof validated.isOn !== "boolean") {
            logger.log("Toggle isOn must be a Bool; ignoring", "warning");
            delete validated.isOn;
        }
        const validStyles = ["switch", "button", "checkbox"];
        if (typeof validated.style === "string" && !validStyles.includes(validated.style)) {
            logger.log(`Toggle style '${validated.style}' invalid; falling back to default`, "warning");
            delete validated.style;
        }
        return validated;
    },

    initialValue: (element, properties) => properties.isOn ?? false,

    buildView: (element, properties, ctx) => {
        let style = properties.style ?? "switch";
        if (style === "button") {
            // Web has no button-style toggle yet; render as a switch.
            ctx.logger.log("Toggle style 'button' is not yet supported on web; using 'switch'", "warning");
            style = "switch";
        }
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
        const templateContext = ctx.templateContext;
        if (templateContext) {
            // A key on the control is the control's own, not a row selection.
            wrapper.addEventListener("keydown", (event) => event.stopPropagation());
            const column = properties[IS_ON_COLUMN_KEY];
            if (!Number.isInteger(column)) {
                warnOnce("Toggle isOn in a template must be a single column reference such as \"$1\" to keep its state; this Toggle is display-only", ctx.logger);
            }
            input.addEventListener("change", () => {
                const { parentID, rowIndex } = templateContext;
                if (!Number.isInteger(column)
                    || !ctx.model.writeRowCell(parentID, rowIndex, column, rowBoolText(input.checked))) {
                    input.checked = !input.checked; // display-only, or the row is gone
                    return;
                }
                if (typeof properties.actionID === "string") {
                    ctx.model.dispatchAction(properties.actionID, parentID, rowIndex, input.checked);
                }
            });
            return wrapper;
        }
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

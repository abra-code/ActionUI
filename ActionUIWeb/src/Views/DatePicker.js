// DatePicker.js — DatePicker element.
// Web analog of ActionUI/Views/DatePicker.swift (and ActionUIAndroid Views/DatePicker.kt).
//
// A calendar-date selector, rendered as a native <input type="date">. Apple's
// valueType is Date; the web has no Date token, so valueType is "string" and the
// value is the ISO 8601 calendar date "YYYY-MM-DD" (the native input's own
// format). A host reads/writes it with get/setString(id).
//
// Properties (mirroring DatePicker.swift):
//   title         leading label; defaults to "Date".
//   selectedDate  initial date (ISO 8601 string); defaults to today.
//   range         { start, end } ISO date strings; applied as min/max when both
//                 are present and start <= end (else ignored, per Apple).
//   displayStyle  "automatic" | "compact" | "graphical" | "stepperField" |
//                 "field" (the macOS set); validated and stashed, but the web has
//                 one native date control, so the style is appearance-only.
//   valueChangeActionID  dispatched on user selection (the native `change`);
//                 programmatic setString is silent (the Apple binding setter only
//                 fires on UI interaction).

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

// The macOS-valid display styles (the web's default skin is macOS-flavored).
const VALID_STYLES = ["automatic", "compact", "graphical", "stepperField", "field"];

register("DatePicker", {
    valueType: "string",

    // Mirrors DatePicker.swift validateProperties (warning text included verbatim;
    // the displayStyle message drops Apple's runtime OS-version string).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("DatePicker requires 'title' as String; ignoring", "warning");
            delete validated.title;
        }

        if (typeof validated.displayStyle === "string") {
            if (!VALID_STYLES.includes(validated.displayStyle)) {
                logger.log(`DatePicker displayStyle '${validated.displayStyle}' invalid on this platform; ignoring`, "warning");
                delete validated.displayStyle;
            }
        } else if (validated.displayStyle !== undefined) {
            logger.log("DatePicker requires 'displayStyle' as String; ignoring", "warning");
            delete validated.displayStyle;
        }

        // range must be a { start, end } dictionary of strings; missing endpoints
        // drop it (Apple's typo "is not not specified" is preserved verbatim).
        if (isStringDict(validated.range)) {
            let valid = true;
            if (validated.range.start === undefined) {
                logger.log("DatePicker range.start is not specified; ignoring range", "warning");
                valid = false;
            }
            if (validated.range.end === undefined) {
                logger.log("DatePicker range.end is not not specified; ignoring range", "warning");
                valid = false;
            }
            if (!valid) delete validated.range;
        } else if (validated.range !== undefined) {
            logger.log("DatePicker requires 'range' as [String: String]; ignoring", "warning");
            delete validated.range;
        }

        if (validated.selectedDate !== undefined && typeof validated.selectedDate !== "string") {
            logger.log("DatePicker selectedDate is not a string; ignoring", "warning");
            delete validated.selectedDate;
        }

        return validated;
    },

    // Seeds the initial date: the selectedDate (normalized to YYYY-MM-DD) or today,
    // mirroring Apple's fallback to Date().
    initialValue: (element, properties) => toDateValue(properties.selectedDate) || todayValue(),

    buildView: (element, properties, ctx) => {
        const title = properties.title ?? "Date";
        const initial = toDateValue(properties.selectedDate) || todayValue();

        const input = document.createElement("input");
        input.type = "date";
        input.className = "aui-datepicker";
        input.value = initial;
        if (typeof properties.displayStyle === "string") {
            input.dataset.auiDisplayStyle = properties.displayStyle;
        }

        // Range → min/max, only when both endpoints parse and start <= end (ISO
        // YYYY-MM-DD compares lexicographically the same as chronologically).
        if (isStringDict(properties.range)) {
            const start = toDateValue(properties.range.start);
            const end = toDateValue(properties.range.end);
            if (start && end && start <= end) {
                input.min = start;
                input.max = end;
            }
        }

        const dispatchValueChange = () => {
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        };

        markHandlesAction(input);
        // `change` fires when the user commits a date (the Apple binding setter).
        input.addEventListener("change", dispatchValueChange);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => input.value,
                setValue: (value) => { input.value = toDateValue(value); }, // programmatic: silent
            });
        }

        // Leading label (title always present, default "Date"), reusing the shared
        // labeled-field layout.
        const wrapper = document.createElement("label");
        wrapper.className = "aui-labeled-field";
        const label = document.createElement("span");
        label.className = "aui-field-label";
        label.textContent = title;
        wrapper.append(label, input);
        return wrapper;
    },
});

function isStringDict(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
        && Object.values(value).every((entry) => typeof entry === "string");
}

// Normalizes an ISO 8601 string to the <input type="date"> format "YYYY-MM-DD";
// returns "" when not parseable.
function toDateValue(value) {
    if (typeof value !== "string" || value === "") return "";
    if (/^\d{4}-\d{2}-\d{2}/.test(value)) return value.slice(0, 10);
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toISOString().slice(0, 10);
}

function todayValue() {
    return new Date().toISOString().slice(0, 10);
}

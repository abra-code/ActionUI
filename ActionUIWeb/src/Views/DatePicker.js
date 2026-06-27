// DatePicker.js — DatePicker element.
// Web analog of ActionUI/Views/DatePicker.swift (and ActionUIAndroid Views/DatePicker.kt).
//
// A date/time selector, rendered as a native <input>. Apple's valueType is Date;
// the web has no Date token, so valueType is "string". The element's
// `displayedComponents` selects the mode and the value's wire format:
//   "date" (default) -> <input type="date">; value is "YYYY-MM-DD".
//   "hourAndMinute"  -> <input type="time">; value is a full ISO datetime
//                       "YYYY-MM-DDTHH:mm:ss" (today's date + the chosen time).
//   "dateAndTime"    -> <input type="datetime-local">; value is a full ISO
//                       datetime "YYYY-MM-DDTHH:mm:ss".
// A host reads/writes the wire value with get/setString(id). The native input's
// own value formats differ (date "YYYY-MM-DD", time "HH:mm",
// datetime-local "YYYY-MM-DDTHH:mm"), so we convert in both directions.
//
// Properties (mirroring DatePicker.swift):
//   title         leading label; defaults to "Date".
//   displayedComponents  "date" | "hourAndMinute" | "dateAndTime"; default "date".
//   selectedDate  initial value (ISO 8601 string); defaults to today / now.
//                 Parsed flexibly: "YYYY-MM-DD", "HH:mm", or a full ISO datetime.
//   range         { start, end } ISO date strings; applied as min/max when both
//                 are present and start <= end (else ignored, per Apple). Only
//                 meaningful for the date-bearing modes.
//   displayStyle  "automatic" | "compact" | "graphical" | "stepperField" |
//                 "field" (the macOS set); validated and stashed, but the web has
//                 one native control per type, so the style is appearance-only.
//   valueChangeActionID  dispatched on user selection (the native `change`);
//                 programmatic setString is silent (the Apple binding setter only
//                 fires on UI interaction).

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

// The macOS-valid display styles (the web's default skin is macOS-flavored).
const VALID_STYLES = ["automatic", "compact", "graphical", "stepperField", "field"];

// The displayedComponents modes and their allowed values.
const VALID_COMPONENTS = ["date", "hourAndMinute", "dateAndTime"];

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

        if (typeof validated.displayedComponents === "string") {
            if (!VALID_COMPONENTS.includes(validated.displayedComponents)) {
                logger.log(`DatePicker displayedComponents '${validated.displayedComponents}' invalid; ignoring`, "warning");
                delete validated.displayedComponents;
            }
        } else if (validated.displayedComponents !== undefined) {
            logger.log("DatePicker requires 'displayedComponents' as String; ignoring", "warning");
            delete validated.displayedComponents;
        }

        // range must be a { start, end } dictionary of strings; missing endpoints
        if (isStringDict(validated.range)) {
            let valid = true;
            if (validated.range.start === undefined) {
                logger.log("DatePicker range.start is not specified; ignoring range", "warning");
                valid = false;
            }
            if (validated.range.end === undefined) {
                logger.log("DatePicker range.end is not specified; ignoring range", "warning");
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

    // Seeds the initial wire value for the mode: the selectedDate (normalized) or
    // today/now, mirroring Apple's fallback to Date().
    initialValue: (element, properties) => {
        const mode = resolveComponents(properties.displayedComponents);
        return toWireValue(properties.selectedDate, mode) || nowWireValue(mode);
    },

    buildView: (element, properties, ctx) => {
        const title = properties.title ?? "Date";
        const mode = resolveComponents(properties.displayedComponents);
        const initialWire = toWireValue(properties.selectedDate, mode) || nowWireValue(mode);

        const input = document.createElement("input");
        input.type = inputTypeFor(mode);
        input.className = "aui-datepicker";
        input.value = wireToInput(initialWire, mode);
        if (typeof properties.displayStyle === "string") {
            input.dataset.auiDisplayStyle = properties.displayStyle;
        }
        input.dataset.auiDisplayedComponents = mode;

        // Range -> min/max, only when both endpoints parse and start <= end (the
        // native min/max for date/datetime-local follow the input's own format).
        // Range is meaningful only for the date-bearing modes.
        if (mode !== "hourAndMinute" && isStringDict(properties.range)) {
            const start = wireToInput(toWireValue(properties.range.start, mode), mode);
            const end = wireToInput(toWireValue(properties.range.end, mode), mode);
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
        // `change` fires when the user commits a value (the Apple binding setter).
        input.addEventListener("change", dispatchValueChange);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                // Read: convert the native input value to the wire format.
                getValue: () => inputToWire(input.value, mode),
                // Write: normalize the incoming wire value to the native format. Silent.
                setValue: (value) => { input.value = wireToInput(toWireValue(value, mode), mode); },
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

// Maps the JSON displayedComponents to a known mode; unknown/absent -> "date".
function resolveComponents(raw) {
    return VALID_COMPONENTS.includes(raw) ? raw : "date";
}

// The native <input> type for a mode.
function inputTypeFor(mode) {
    if (mode === "hourAndMinute") return "time";
    if (mode === "dateAndTime") return "datetime-local";
    return "date";
}

// Parses a flexible ISO 8601 input into { y, mo, d, h, mi, s } parts, or null.
// Accepts "YYYY-MM-DD", "HH:mm" / "HH:mm:ss", and full ISO datetime forms.
function parseParts(value) {
    if (typeof value !== "string" || value === "") return null;
    const trimmed = value.trim();

    // Full datetime "YYYY-MM-DDTHH:mm[:ss]" (with optional offset/Z).
    let m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(trimmed);
    if (m) {
        return { y: +m[1], mo: +m[2], d: +m[3], h: +m[4], mi: +m[5], s: m[6] ? +m[6] : 0 };
    }
    // Date-only "YYYY-MM-DD".
    m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
    if (m) {
        return { y: +m[1], mo: +m[2], d: +m[3], h: 0, mi: 0, s: 0 };
    }
    // Time-only "HH:mm[:ss]" -> seed with today's date.
    m = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(trimmed);
    if (m) {
        const now = new Date();
        return {
            y: now.getFullYear(), mo: now.getMonth() + 1, d: now.getDate(),
            h: +m[1], mi: +m[2], s: m[3] ? +m[3] : 0,
        };
    }
    // Last resort: let the engine try.
    const dt = new Date(trimmed);
    if (!Number.isNaN(dt.getTime())) {
        return {
            y: dt.getFullYear(), mo: dt.getMonth() + 1, d: dt.getDate(),
            h: dt.getHours(), mi: dt.getMinutes(), s: dt.getSeconds(),
        };
    }
    return null;
}

const pad = (n) => String(n).padStart(2, "0");

// Builds the wire value for a mode from parsed parts:
//   "date"        -> "YYYY-MM-DD"
//   time-bearing  -> "YYYY-MM-DDTHH:mm:ss"
function partsToWire(p, mode) {
    const date = `${String(p.y).padStart(4, "0")}-${pad(p.mo)}-${pad(p.d)}`;
    if (mode === "date") return date;
    return `${date}T${pad(p.h)}:${pad(p.mi)}:${pad(p.s)}`;
}

// Normalizes any flexible input string to the mode's wire format; "" when
// unparseable. For time-bearing modes given a time-only input, today's date is
// used to form the full ISO datetime.
function toWireValue(value, mode) {
    const p = parseParts(value);
    return p ? partsToWire(p, mode) : "";
}

// The wire value for "now" in the given mode.
function nowWireValue(mode) {
    const now = new Date();
    const p = {
        y: now.getFullYear(), mo: now.getMonth() + 1, d: now.getDate(),
        h: now.getHours(), mi: now.getMinutes(), s: now.getSeconds(),
    };
    return partsToWire(p, mode);
}

// Converts a wire value to the native <input> value for the mode:
//   "date"           -> "YYYY-MM-DD"
//   "hourAndMinute"  -> "HH:mm"
//   "dateAndTime"    -> "YYYY-MM-DDTHH:mm"
function wireToInput(wire, mode) {
    const p = parseParts(wire);
    if (!p) return "";
    if (mode === "hourAndMinute") return `${pad(p.h)}:${pad(p.mi)}`;
    if (mode === "dateAndTime") {
        return `${String(p.y).padStart(4, "0")}-${pad(p.mo)}-${pad(p.d)}T${pad(p.h)}:${pad(p.mi)}`;
    }
    return `${String(p.y).padStart(4, "0")}-${pad(p.mo)}-${pad(p.d)}`;
}

// Converts a native <input> value (date / time / datetime-local format) to the
// mode's wire value.
function inputToWire(value, mode) {
    return toWireValue(value, mode);
}

// Exported for unit tests: pure value-format conversions.
export const __test__ = {
    resolveComponents, inputTypeFor, toWireValue, wireToInput, inputToWire, nowWireValue,
};

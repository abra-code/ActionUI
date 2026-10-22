// Stepper.js — Stepper element.
// Web analog of ActionUI/Views/Stepper.swift (and ActionUIAndroid Views/Stepper.kt).
//
// A discrete Double value adjusted in fixed increments, rendered as a label plus a
// pair of −/+ buttons (the browser has no native stepper control). valueType is
// "double", so a host reads/writes the value with get/setDouble(id).
//
// Properties (mirroring Stepper.swift):
//   value        initial value (Double, defaults to 0.0).
//   range        { min, max } (optional; no clamping when omitted, min <= max).
//   step         positive increment (Double, defaults to 1.0).
//   label        static label text; ignored when labelFormat is set.
//   labelFormat  printf-style format string embedding the current value (e.g.
//                "Count: %d", "Volume: %g%%"; NumberPrintf). Takes precedence over
//                label and is re-evaluated on every change.
//   actionID     dispatched on user-initiated change only (a −/+ press), matching
//                the Apple binding setter; programmatic setElementValue is silent.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { formatNumber, plainNumber, systemDecimalSeparator } from "../Helpers/NumberPrintf.js";

register("Stepper", {
    valueType: "double",

    // Mirrors Stepper.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // value: a non-number (but present) defaults to 0.0; absent ⇒ 0.0.
        if (typeof validated.value !== "number") {
            if (validated.value !== undefined) {
                logger.log("Stepper value must be a number; defaulting to 0.0", "warning");
            }
            validated.value = 0.0;
        }

        // range: a dictionary with numeric min/max and min <= max, else ignored
        // (no clamping — distinct from Slider, which falls back to 0…1).
        if (isPlainObject(validated.range)) {
            const { min, max } = validated.range;
            if (typeof min === "number" && typeof max === "number" && min <= max) {
                validated.range = { min, max };
            } else {
                logger.log("Stepper range must have valid min/max numbers with min <= max; ignoring range", "warning");
                delete validated.range;
            }
        } else if (validated.range !== undefined) {
            logger.log("Stepper range must be a dictionary with min/max numbers; ignoring range", "warning");
            delete validated.range;
        }

        // step: a positive number, else 1.0.
        if (typeof validated.step === "number" && validated.step > 0) {
            // keep as-is
        } else if (validated.step !== undefined) {
            logger.log("Stepper step must be a positive number; defaulting to 1.0", "warning");
            validated.step = 1.0;
        } else {
            validated.step = 1.0;
        }

        // label: must be a String, else ignored.
        if (validated.label !== undefined && typeof validated.label !== "string") {
            logger.log("Stepper label must be a String; ignoring", "warning");
            delete validated.label;
        }

        // labelFormat: must be a String, else ignored.
        if (validated.labelFormat !== undefined && typeof validated.labelFormat !== "string") {
            logger.log("Stepper labelFormat must be a String; ignoring", "warning");
            delete validated.labelFormat;
        }

        return validated;
    },

    initialValue: (element, properties) => properties.value ?? 0.0,

    buildView: (element, properties, ctx) => {
        const step = (typeof properties.step === "number" && properties.step > 0) ? properties.step : 1.0;
        const hasRange = isPlainObject(properties.range)
            && typeof properties.range.min === "number" && typeof properties.range.max === "number";
        const min = hasRange ? properties.range.min : -Infinity;
        const max = hasRange ? properties.range.max : Infinity;
        const hasFormat = typeof properties.labelFormat === "string";

        let current = clamp(properties.value ?? 0.0, min, max);

        const wrapper = document.createElement("div");
        wrapper.className = "aui-stepper";

        const labelText = document.createElement("span");
        labelText.className = "aui-stepper-label";

        const controls = document.createElement("div");
        controls.className = "aui-stepper-controls";
        const minus = makeButton("−", "aui-stepper-decrement");
        const plus = makeButton("+", "aui-stepper-increment");
        controls.append(minus, plus);

        // Label text reflects labelFormat (re-evaluated per change) or the static
        // label; the box collapses when there is nothing to show, like SwiftUI.
        const renderLabel = () => {
            const text = hasFormat ? stepperLabel(properties.labelFormat, current, ctx.logger) : (properties.label ?? "");
            labelText.textContent = text;
            labelText.style.display = text === "" ? "none" : "";
        };
        renderLabel();
        wrapper.append(labelText, controls);

        const updateDisabled = () => {
            minus.disabled = current <= min;
            plus.disabled = current >= max;
        };
        updateDisabled();

        // User-initiated step: clamp, update, and fire actionID (binding setter).
        const stepBy = (delta) => {
            const next = clamp(current + delta, min, max);
            if (next === current) return;
            current = next;
            renderLabel();
            updateDisabled();
            // The model reads through the binding's getValue, so `current` is the
            // live value — no separate store write is needed.
            if (typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, current);
            }
        };

        markHandlesAction(wrapper);
        minus.addEventListener("click", () => stepBy(-step));
        plus.addEventListener("click", () => stepBy(step));

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => current,
                setValue: (value) => {
                    const n = Number(value);
                    // Clamp only when a range is set (no clamping otherwise, per the
                    // validator). Programmatic updates do not fire actionID.
                    current = clamp(Number.isFinite(n) ? n : current, min, max);
                    renderLabel();
                    updateDisabled();
                },
            });
        }
        return wrapper;
    },
});

function makeButton(glyph, className) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `aui-stepper-button ${className}`;
    button.textContent = glyph;
    return button;
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
}

// The label, as on every platform: labelFormat with the value in it (NumberPrintf, with the
// system's decimal separator); a format NumberPrintf refuses shows the plain value and is logged
// once per format.
const reportedLabelFormats = new Set();

export function stepperLabel(format, value, logger, decimalSeparator = systemDecimalSeparator()) {
    const text = formatNumber(format, value, decimalSeparator);
    if (text !== null) return text;
    if (!reportedLabelFormats.has(format)) {
        reportedLabelFormats.add(format);
        logger?.log(`Stepper: labelFormat "${format}" is not one number format; showing the value`, "warning");
    }
    return plainNumber(value, decimalSeparator);
}

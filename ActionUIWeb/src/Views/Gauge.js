// Gauge.js — Gauge element.
// Web analog of ActionUI/Views/Gauge.swift (and ActionUIAndroid Views/Gauge.kt).
//
// A read-only level indicator for a value within a range. Like Slider it is
// "double" on the value bridge, but the control is non-interactive: only the
// host moves it (setDouble re-renders the indicator; no action dispatch).
//
// Style mapping (Apple's four accessory styles + the default):
//   absent style (SwiftUI's default linearCapacity look, label shown)
//       → a column of the title over a native <meter> — the DOM's own gauge
//         element, the same fit Android found in its progress indicators.
//   accessoryLinear / accessoryLinearCapacity (SwiftUI hides the label in
//       both) → a bare <meter>. The accessoryLinear dot-marker look has no
//       native analog; both render as a filled bar, as on Android.
//   accessoryCircular / accessoryCircularCapacity → a conic-gradient ring
//       with the title centered. Divergences (same as Android): the ring is
//       closed (SwiftUI's accessoryCircular is an open arc with a bottom
//       gap), and the capacity variant centers the title where SwiftUI puts
//       the currentValueLabel (which the JSON contract never supplies).
//
// The rendered fill is the value's fraction of the range, clamped to 0…1 (a
// degenerate range max <= min renders empty rather than dividing by zero) —
// the Android stance; the stored value itself is kept raw for getValue.
//
// Properties: value (Double, default 0.0), title (String), style (one of the
// four accessory styles), range ({min, max}, default 0.0…1.0).

import { register } from "../Common/ActionUIRegistry.js";

const VALID_STYLES = [
    "accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity",
];

// The filled fraction for value within min…max, clamped to 0…1. Mirrors the
// Android gaugeFraction helper (SwiftUI's min...max range would crash outright
// on a degenerate max <= min; rendering empty is the graceful analog).
function gaugeFraction(min, max, value) {
    if (max <= min) return 0;
    return Math.min(Math.max((value - min) / (max - min), 0), 1);
}

register("Gauge", {
    valueType: "double",

    // Mirrors Gauge.swift validateProperties (warning text included verbatim).
    // Note the Swift quirk, kept faithfully: a non-String `style` passes
    // validation silently (only an invalid style *string* warns) and is then
    // ignored by buildView's string cast.
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.value !== undefined && typeof validated.value !== "number") {
            logger.log("Gauge value must be a number; defaulting to 0.0", "warning");
            delete validated.value;
        }

        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("Gauge title must be a String; defaulting to nil", "warning");
            delete validated.title;
        }

        if (typeof validated.style === "string" && !VALID_STYLES.includes(validated.style)) {
            logger.log(`Gauge style '${validated.style}' invalid; defaulting to nil`, "warning");
            delete validated.style;
        }

        if (typeof validated.range === "object" && validated.range !== null && !Array.isArray(validated.range)) {
            const validatedRange = {};
            if (typeof validated.range.min === "number") {
                validatedRange.min = validated.range.min;
            } else {
                logger.log("Gauge range.min must be a number; defaulting to 0.0", "warning");
                validatedRange.min = 0.0;
            }
            if (typeof validated.range.max === "number") {
                validatedRange.max = validated.range.max;
            } else {
                logger.log("Gauge range.max must be a number; defaulting to 1.0", "warning");
                validatedRange.max = 1.0;
            }
            validated.range = validatedRange;
        } else if (validated.range !== undefined) {
            logger.log("Gauge range must be a dictionary with min/max; defaulting to 0.0...1.0", "warning");
            validated.range = { min: 0.0, max: 1.0 };
        }

        return validated;
    },

    initialValue: (element, properties) => properties.value ?? 0.0,

    buildView: (element, properties, ctx) => {
        const min = properties.range?.min ?? 0.0;
        const max = properties.range?.max ?? 1.0;
        const style = (typeof properties.style === "string") ? properties.style : null;
        let current = properties.value ?? 0.0;

        let root;
        let render;
        if (style === "accessoryCircular" || style === "accessoryCircularCapacity") {
            root = document.createElement("div");
            root.className = "aui-gauge-circular";
            const ring = document.createElement("div");
            ring.className = "aui-gauge-ring";
            root.appendChild(ring);
            if (typeof properties.title === "string") {
                const title = document.createElement("span");
                title.className = "aui-gauge-ring-title";
                title.textContent = properties.title;
                root.appendChild(title);
            }
            render = () => ring.style.setProperty("--aui-gauge-fill", String(gaugeFraction(min, max, current)));
        } else {
            // <meter> is always rendered 0…1 with the precomputed fraction, so
            // degenerate ranges stay graceful instead of hitting the browser's
            // own min/max fixups.
            const bar = document.createElement("meter");
            bar.className = "aui-gauge-bar";
            bar.min = 0;
            bar.max = 1;
            render = () => { bar.value = gaugeFraction(min, max, current); };

            if (style === null && typeof properties.title === "string") {
                root = document.createElement("div");
                root.className = "aui-gauge";
                const title = document.createElement("span");
                title.className = "aui-gauge-title";
                title.textContent = properties.title;
                root.append(title, bar);
            } else {
                // The accessory linear styles hide the label, as on Apple/Android.
                root = bar;
            }
        }
        render();

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => current,
                setValue: (value) => {
                    const n = Number(value);
                    if (!Number.isFinite(n)) return;
                    current = n;
                    render();
                },
            });
        }
        return root;
    },
});

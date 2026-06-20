// AnimationModifier.js — the `animation` modifier (implicit transitions).
// Web analog of Apple's resolveAnimation (View.swift) / Android's AnimationHelper.
// SwiftUI's `.animation` makes value changes animate; the web equivalent is a CSS
// `transition` armed on the element, so a later change to its animatable visual
// properties (opacity, color, background, border-radius, transform, box-shadow)
// eases/springs to the new value with the configured curve instead of snapping.
//
// JSON: "animation": "spring"   (shorthand: just the curve), or
//       "animation": { "curve": "easeOut", "duration": 0.3, "delay": 0,
//                       "speed": 1, "value": "<key>" }
// Curves: default, linear, easeIn, easeOut, easeInOut, spring, bouncy, smooth,
//         snappy, interactiveSpring. Validation mirrors Apple's validateProperties.
//
// Web specifics / divergences:
//   * Trigger. The transition is armed at build, so it animates a LATER mutation -
//     a host setElementProperty (ModifierResolver.applyElementProperty mutates the
//     same node in place, which is why this composes on top of it), or any other
//     style change. It does not animate at load (initial styles are set on the
//     detached node before mount), matching the canonical "only on mutation" caveat.
//   * Springs are approximated with cubic-bezier easings (mild overshoot for
//     spring/bouncy/snappy; none for smooth) - close enough for short UI
//     transitions, no real spring physics.
//   * `value` (watch a specific key) is parsed/validated but does not scope on web:
//     a CSS transition animates by property, not by trigger key. Documented divergence.
//   * `display` is not animatable in CSS, so `hidden` toggles still snap.
//   * Respects `prefers-reduced-motion: reduce` (arms nothing, so mutations are
//     instant).

import { prefersReducedMotion } from "./Modality.js";

const VALID_CURVES = [
    "default", "linear", "easeIn", "easeOut", "easeInOut",
    "spring", "bouncy", "smooth", "snappy", "interactiveSpring",
];

// curve -> { timing (CSS timing function), duration (seconds, default) }. The
// duration curves default to SwiftUI's 0.35s; the springs to 0.5s (interactiveSpring
// 0.15s). Springs map to overshooting cubic-beziers (smooth: none).
const CURVES = {
    default:           { timing: "cubic-bezier(0.42, 0, 0.58, 1)",  duration: 0.35 },
    linear:            { timing: "linear",                          duration: 0.35 },
    easeIn:            { timing: "cubic-bezier(0.42, 0, 1, 1)",      duration: 0.35 },
    easeOut:           { timing: "cubic-bezier(0, 0, 0.58, 1)",      duration: 0.35 },
    easeInOut:         { timing: "cubic-bezier(0.42, 0, 0.58, 1)",   duration: 0.35 },
    spring:            { timing: "cubic-bezier(0.34, 1.2, 0.64, 1)",  duration: 0.5 },
    bouncy:            { timing: "cubic-bezier(0.34, 1.56, 0.64, 1)", duration: 0.5 },
    smooth:            { timing: "cubic-bezier(0.4, 0, 0.2, 1)",      duration: 0.5 },
    snappy:            { timing: "cubic-bezier(0.3, 1.3, 0.5, 1)",    duration: 0.5 },
    interactiveSpring: { timing: "cubic-bezier(0.4, 0, 0.2, 1)",      duration: 0.15 },
};

// The animatable CSS properties our visual modifiers / setElementProperty set
// (incl. the independent `scale` / `rotate` transform properties for
// scaleEffect / rotationEffect).
const ANIMATED_PROPERTIES =
    "opacity, color, background-color, border-color, border-radius, scale, rotate, transform, box-shadow, filter";

// Validates `animation` (shorthand or dict), mirroring Apple's validateProperties
// block message for message. Returns the normalized config { curve, duration?,
// delay?, speed? } or null when absent/invalid.
function validateAnimation(animation, logger) {
    if (animation === undefined || animation === null) return null;

    if (typeof animation === "string") {
        if (VALID_CURVES.includes(animation)) return { curve: animation };
        logger.log(`Invalid animation curve '${animation}', expected one of ${VALID_CURVES.join(", ")}, ignoring`, "warning");
        return null;
    }

    if (typeof animation !== "object" || Array.isArray(animation)) {
        logger.log(`Invalid type for animation: expected String or object, got ${typeof animation}, ignoring`, "warning");
        return null;
    }

    const curve = animation.curve;
    if (typeof curve !== "string" || !VALID_CURVES.includes(curve)) {
        const curveStr = typeof curve === "string" ? curve : "(missing)";
        logger.log(`animation.curve '${curveStr}' must be one of ${VALID_CURVES.join(", ")}, ignoring`, "warning");
        return null;
    }

    const out = { curve };
    if (animation.duration !== undefined) {
        if (typeof animation.duration === "number" && animation.duration > 0) out.duration = animation.duration;
        else if (typeof animation.duration === "number") logger.log("animation.duration must be positive, ignoring", "warning");
        else logger.log("Invalid animation.duration: expected positive Double, ignoring", "warning");
    }
    if (animation.delay !== undefined) {
        if (typeof animation.delay === "number" && animation.delay >= 0) out.delay = animation.delay;
        else logger.log("Invalid animation.delay: expected non-negative Double, ignoring", "warning");
    }
    if (animation.speed !== undefined) {
        if (typeof animation.speed === "number" && animation.speed > 0) out.speed = animation.speed;
        else logger.log("Invalid animation.speed: expected positive Double, ignoring", "warning");
    }
    if (animation.value !== undefined && typeof animation.value !== "string") {
        logger.log("Invalid animation.value: expected String, ignoring", "warning");
    }
    // `value` is accepted but not used for scoping on web (a CSS transition animates
    // by property, not by trigger key) - documented divergence.
    return out;
}

// Resolves `animation` to the CSS transition parameters { duration, timing, delay }
// (seconds), or null when absent/invalid. Pure, so it is testable.
export function resolveAnimation(animation, logger) {
    const config = validateAnimation(animation, logger);
    if (!config) return null;
    const base = CURVES[config.curve];
    const speed = config.speed ?? 1;
    return {
        duration: (config.duration ?? base.duration) / speed,
        timing: base.timing,
        delay: config.delay ?? 0,
    };
}

// Arms a CSS transition on [node] from the element's `animation` property so a later
// visual-property change eases/springs. A no-op when no valid `animation` is declared,
// or under prefers-reduced-motion (mutations stay instant). Part of the build pipeline.
export function applyAnimation(node, properties, logger) {
    const anim = resolveAnimation(properties.animation, logger);
    if (!anim) return;
    if (prefersReducedMotion()) return;
    node.style.transitionProperty = ANIMATED_PROPERTIES;
    node.style.transitionDuration = `${anim.duration}s`;
    node.style.transitionTimingFunction = anim.timing;
    node.style.transitionDelay = `${anim.delay}s`;
}

// Debug.js — a process-wide debug-mode flag for the web renderer.
//
// Off by default (production). When on, the renderer surfaces issues that would
// otherwise fail silently — currently: an unmapped SF Symbol (`systemImage`
// with no SF->Material entry) draws a visible `broken_image` placeholder instead
// of a blank span (see SymbolIcon.js). The host turns it on before building
// (the ActionUIWeb demo wires it to a `?debug` query param + a checkbox).

let debugMode = false;

export function setDebugMode(on) {
    debugMode = !!on;
}

export function isDebugMode() {
    return debugMode;
}

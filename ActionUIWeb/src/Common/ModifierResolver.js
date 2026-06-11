// ModifierResolver.js — baseline View modifiers applied to every element.
// Web analog of ActionUI/Views/View.swift applyViewModifiers (PoC subset).
//
// Supported subset (property names follow Documentation/Schemas/View.md):
//   padding          Number, "default", or {top, bottom, leading, trailing}
//   hidden           Boolean
//   disabled         Boolean
//   opacity          Number 0..1
//   foregroundColor  SwiftUI color name or hex string
//   background       SwiftUI color name or hex string
//   cornerRadius     Number
//   font             Named text style ("largeTitle".."caption2") — CSS class
//   frame            {width, height, minWidth, maxWidth, minHeight, maxHeight}
//                    ("infinity" accepted for maxWidth/maxHeight)
//   help             String tooltip -> title attribute
//   actionID         Handled by individual views (interaction semantics differ
//                    per control); plain display views get a click action here.

const NAMED_COLORS = {
    // SwiftUI color names -> CSS custom properties resolved in theme.css,
    // so they adapt to light/dark mode like SwiftUI semantic colors.
    primary: "var(--aui-color-primary)",
    secondary: "var(--aui-color-secondary)",
    accentColor: "var(--aui-color-accent)",
    red: "var(--aui-color-red)",
    orange: "var(--aui-color-orange)",
    yellow: "var(--aui-color-yellow)",
    green: "var(--aui-color-green)",
    mint: "var(--aui-color-mint)",
    teal: "var(--aui-color-teal)",
    cyan: "var(--aui-color-cyan)",
    blue: "var(--aui-color-blue)",
    indigo: "var(--aui-color-indigo)",
    purple: "var(--aui-color-purple)",
    pink: "var(--aui-color-pink)",
    brown: "var(--aui-color-brown)",
    white: "#ffffff",
    black: "#000000",
    gray: "var(--aui-color-gray)",
    clear: "transparent",
};

const FONT_TEXT_STYLES = new Set([
    "largeTitle", "title", "title2", "title3", "headline", "subheadline",
    "body", "callout", "footnote", "caption", "caption2",
]);

export function resolveColor(value, logger) {
    if (typeof value !== "string") return null;
    if (NAMED_COLORS[value]) return NAMED_COLORS[value];
    if (/^#[0-9a-fA-F]{3,8}$/.test(value)) return value;
    logger.log(`Unknown color "${value}"`, "warning");
    return null;
}

const DEFAULT_PADDING = 8; // pt; approximates SwiftUI's adaptive default

function applyPadding(node, padding, logger) {
    if (typeof padding === "number") {
        node.style.padding = `${padding}px`;
    } else if (padding === "default") {
        node.style.padding = `${DEFAULT_PADDING}px`;
    } else if (typeof padding === "object" && padding !== null) {
        const { top = 0, bottom = 0, leading = 0, trailing = 0 } = padding;
        node.style.padding = `${top}px ${trailing}px ${bottom}px ${leading}px`;
    } else {
        logger.log(`Invalid padding ${JSON.stringify(padding)}`, "warning");
    }
}

function applyFrameDimension(node, value, cssProperty) {
    if (value === "infinity") {
        node.style[cssProperty] = "100%";
        if (cssProperty === "maxWidth" || cssProperty === "width") node.style.flexGrow = "1";
    } else if (typeof value === "number") {
        node.style[cssProperty] = `${value}px`;
    }
}

function applyFrame(node, frame) {
    applyFrameDimension(node, frame.width, "width");
    applyFrameDimension(node, frame.height, "height");
    applyFrameDimension(node, frame.minWidth, "minWidth");
    applyFrameDimension(node, frame.maxWidth, "maxWidth");
    applyFrameDimension(node, frame.minHeight, "minHeight");
    applyFrameDimension(node, frame.maxHeight, "maxHeight");
    if (typeof frame.width === "number" || typeof frame.height === "number") {
        node.style.flexShrink = "0";
    }
}

// Interactive controls wire actionID themselves with control-specific
// semantics; they set this flag to opt out of the generic click handler.
export function markHandlesAction(node) {
    node.dataset.auiHandlesAction = "1";
}

export function applyViewModifiers(node, element, properties, ctx) {
    const { logger } = ctx;

    if (properties.padding !== undefined) applyPadding(node, properties.padding, logger);
    if (properties.hidden === true) node.style.display = "none";
    if (typeof properties.opacity === "number") node.style.opacity = String(properties.opacity);
    if (typeof properties.cornerRadius === "number") {
        node.style.borderRadius = `${properties.cornerRadius}px`;
        node.style.overflow = "hidden";
    }

    const foreground = resolveColor(properties.foregroundColor, logger);
    if (foreground) node.style.color = foreground;
    const background = resolveColor(properties.background, logger);
    if (background) node.style.backgroundColor = background;

    if (typeof properties.font === "string") {
        if (FONT_TEXT_STYLES.has(properties.font)) {
            node.classList.add(`aui-font-${properties.font}`);
        } else {
            node.style.fontFamily = properties.font;
        }
    }

    if (typeof properties.frame === "object" && properties.frame !== null) {
        applyFrame(node, properties.frame);
    }

    if (properties.disabled === true) {
        node.classList.add("aui-disabled");
        if ("disabled" in node) node.disabled = true;
        const control = node.querySelector?.("button, input, textarea, select");
        if (control) control.disabled = true;
    }

    if (typeof properties.help === "string") node.title = properties.help;

    if (typeof properties.actionID === "string" && !node.dataset.auiHandlesAction) {
        node.addEventListener("click", () => {
            ctx.model.dispatchAction(properties.actionID, element.id);
        });
    }
}

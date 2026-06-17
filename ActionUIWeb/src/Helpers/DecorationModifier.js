// DecorationModifier.js — view-valued overlay / background decoration subviews.
// Web analog of Apple's .overlay(alignment:) / .background(alignment:) view-valued
// modifiers (ActionUI/Views/View.swift) and ActionUIAndroid's ViewModifierHelper
// decorations. Part of the build pipeline: buildElementView calls applyDecorations
// right after applyPresentationModifiers, and it is a no-op unless the element
// declares an `overlay` or `background` *subview* (an object; the color `background`
// is a separate property handled by ModifierResolver).
//
// Apple semantics reproduced:
//   * a decoration never affects the carrier's layout size,
//   * it is positioned by the SwiftUI alignment vocabulary (default center;
//     warn-and-center on an unknown value, matching View.swift validateProperties),
//   * draw order is background -> element (incl. its own background color) -> overlay,
//   * overlayAlignment / backgroundAlignment pick the placement.
//
// Web rendering. The carrier is wrapped in a grid box (`.aui-decorated`); the
// element is its single in-flow grid item, so it alone defines the box size (a
// fill/greedy element still fills it via the grid item's default stretch). The two
// decoration layers are `position:absolute; inset:0` siblings, so they exactly
// cover the element's box WITHOUT contributing to its size (Apple's "decoration
// does not change layout"). Each layer is a flex box whose justify/align places the
// decoration content; a bare greedy shape (the `.aui-shape` flex idiom) fills the
// layer, a framed decoration keeps its size and is positioned (the same
// frame-conditional behavior Android reads off the JSON). z-index + `isolation`
// order the background behind and the overlay above the element.
//
// The wrapper takes over the carrier's role in the PARENT's layout: the fill
// classes (resolved by the parent stack's `> .aui-fill-*` selectors) and a fixed
// frame's rigid flex-shrink must live on the direct child = wrapper. Everything
// else (size, padding, background color, cornerRadius/clip, opacity, transforms)
// stays on the element.
//
// Divergences (documented; some match Apple's own modifier-apply order):
//   * The carrier's cornerRadius/clip (overflow:hidden on the element) does NOT cut
//     the decoration layers (they are siblings, not children) — corner badges
//     escape (as on Apple), but a background view behind a rounded element shows
//     square corners. Same divergence Android documents.
//   * opacity stays on the element, so a background view does not fade with it
//     (Apple fades it, but applies the overlay after opacity so the overlay does
//     not fade — we match the overlay case, diverge on background).
//   * An overlay receives pointer events where its content sits (faithful to a
//     default SwiftUI .overlay, which is hit-testable).

// SwiftUI alignment -> [align-items (cross/vertical), justify-content (main/
// horizontal)] for the flex decoration layer (default flex-direction: row).
const DECO_ALIGN = {
    center: ["center", "center"],
    leading: ["center", "flex-start"], trailing: ["center", "flex-end"],
    top: ["flex-start", "center"], bottom: ["flex-end", "center"],
    topLeading: ["flex-start", "flex-start"], topTrailing: ["flex-start", "flex-end"],
    bottomLeading: ["flex-end", "flex-start"], bottomTrailing: ["flex-end", "flex-end"],
};
// Verbatim copy of View.swift's validAlignments order for overlay/backgroundAlignment.
const DECO_ALIGN_VALID = ["center", "leading", "trailing", "top", "bottom",
    "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"];
const DECO_ALIGN_LIST_TEXT = `[${DECO_ALIGN_VALID.map((a) => `"${a}"`).join(", ")}]`;

// Validation folded in at the point of use ("validate where you read"): a wrong
// type / value logs the verbatim View.swift warning and falls back to center.
function resolveDecoAlignment(value, key, logger) {
    if (value === undefined) return "center";
    if (typeof value !== "string") {
        logger.log(`Invalid type for ${key}: expected String, got ${typeof value}, ignoring`, "warning");
        return "center";
    }
    if (!DECO_ALIGN_VALID.includes(value)) {
        logger.log(`Invalid ${key} '${value}'; expected one of ${DECO_ALIGN_LIST_TEXT}, defaulting to 'center'`, "warning");
        return "center";
    }
    return value;
}

function buildDecoLayer(childElement, kind, alignmentValue, ctx) {
    const layer = document.createElement("div");
    layer.className = `aui-deco aui-deco-${kind}`;
    const key = kind === "overlay" ? "overlayAlignment" : "backgroundAlignment";
    const alignment = resolveDecoAlignment(alignmentValue, key, ctx.logger);
    const [alignItems, justifyContent] = DECO_ALIGN[alignment];
    layer.style.alignItems = alignItems;
    layer.style.justifyContent = justifyContent;
    // ctx.build recurses through buildElementView, so the decoration content
    // registers its own value/state bindings and stays host-addressable by id.
    layer.appendChild(ctx.build(childElement));
    return layer;
}

// Wraps `node` in a decoration box when the element declares an overlay/background
// subview; returns `node` unchanged otherwise (the overwhelmingly common case).
export function applyDecorations(node, element, properties, ctx) {
    const subs = element.subviews;
    const overlay = subs?.overlay;
    const background = subs?.background; // the SUBVIEW (object); color bg is a property
    if (!overlay && !background) return node;

    const wrapper = document.createElement("div");
    wrapper.className = "aui-decorated";

    // Hand the parent-layout role to the wrapper (the new direct child of the parent):
    // fill classes (parent's `> .aui-fill-*` selectors) and a fixed frame's
    // flex-shrink. The element fills the wrapper via the grid item's default stretch.
    for (const cls of ["aui-fill-width", "aui-fill-height"]) {
        if (node.classList.contains(cls)) {
            node.classList.remove(cls);
            wrapper.classList.add(cls);
        }
    }
    if (node.style.flexShrink) {
        wrapper.style.flexShrink = node.style.flexShrink;
        node.style.flexShrink = "";
    }

    // DOM order is cosmetic (z-index decides paint), but keep it intuitive:
    // background, element, overlay.
    if (background) {
        wrapper.appendChild(buildDecoLayer(background, "background", properties.backgroundAlignment, ctx));
    }
    wrapper.appendChild(node);
    if (overlay) {
        wrapper.appendChild(buildDecoLayer(overlay, "overlay", properties.overlayAlignment, ctx));
    }
    return wrapper;
}

// ModifierResolver.js — baseline View modifiers applied to every element.
// Web analog of ActionUI/Views/View.swift applyViewModifiers (PoC subset).
//
// Supported subset (property names follow Documentation/Schemas/View.md):
//   padding          Number, "default", or {top, bottom, leading, trailing}
//   hidden           Boolean - SwiftUI `.hidden()`: invisible and non-interactive, but
//                    STILL LAID OUT (its space is reserved). CSS `visibility: hidden`,
//                    not `display: none`. It also drops the element from the accessibility
//                    tree, which Apple's `.hidden()` does NOT - see applyViewModifiers.
//   disabled         Boolean
//   opacity          Number 0..1
//   foregroundStyle  SwiftUI color name or hex string
//   background       SwiftUI color name or hex string
//   cornerRadius     Number
//   font             Named text style ("largeTitle".."caption2") — CSS class
//   frame            {width, height, minWidth, idealWidth, maxWidth,
//                    minHeight, idealHeight, maxHeight, alignment} — sizes
//                    clamped against the viewport per the SwiftUI rules;
//                    "infinity" accepted for maxWidth/maxHeight (see applyFrame).
//                    alignment positions the content within a larger frame box
//                    ("leading".."bottomTrailing"); leaf-oriented (a node that
//                    lays out its own children keeps that layout — see applyFrame).
//   help             String tooltip -> title attribute
//   actionID         Handled by individual views (interaction semantics differ
//                    per control); plain display views get a click action here.
//   onHoverActionID  String -> fires on pointer enter/exit, context {isHovering}.
//   onDropActionID   String -> fires when a valid drop lands, context
//                    {items:[String], location:{x,y}} plus a web-only files:[File]
//                    so the host can read bytes and upload (other platforms lack it,
//                    having only a path string). Requires non-empty onDropTypes.
//   onDropTypes      [String] of UTType identifiers accepted as a drop target.
//   onDropTargetedActionID  String -> fires when a drag enters/exits, context
//                    {isTargeted}. See Helpers/DropHelper.swift (Apple canonical);
//                    web type-filtering is coarse (the DnD spec hides item
//                    contents during dragover).

import { StackAxis } from "./StackAxis.js";
import { applyContextMenu } from "../Helpers/ContextMenuModifier.js";
import { applyIgnoresSafeArea } from "../Helpers/SafeAreaModifier.js";

const NAMED_COLORS = {
    // Standard SwiftUI color names -> CSS custom properties resolved in theme.css,
    // so they adapt to light/dark mode like SwiftUI semantic colors.
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

    // Apple SEMANTIC styles (ActionUI/Helpers/ColorHelper.swift resolveShapeStyle)
    // -> the --aui-* tokens defined in theme.css (light + dark, adaptive). The full
    // set so a semantic color authored once renders theme-correct here exactly as on
    // Apple and Android (Material roles). The .opacity(f) path below color-mixes the
    // resolved var().
    // (primary/secondary keep their existing --aui-color-* meaning, which already
    // tracks the label ink; the rest are new tokens.)
    primary: "var(--aui-color-primary)",
    secondary: "var(--aui-color-secondary)",
    tertiary: "var(--aui-tertiary)",
    quaternary: "var(--aui-quaternary)",
    quinary: "var(--aui-quinary)",
    foreground: "var(--aui-foreground)",
    "foreground.secondary": "var(--aui-foreground-secondary)",
    "foreground.tertiary": "var(--aui-foreground-tertiary)",
    "foreground.quaternary": "var(--aui-foreground-quaternary)",
    background: "var(--aui-background)",
    "background.secondary": "var(--aui-background-secondary)",
    "background.tertiary": "var(--aui-background-tertiary)",
    "background.quaternary": "var(--aui-background-quaternary)",
    windowBackground: "var(--aui-window-background)",
    fill: "var(--aui-fill)",
    "fill.secondary": "var(--aui-fill-secondary)",
    "fill.tertiary": "var(--aui-fill-tertiary)",
    "fill.quaternary": "var(--aui-fill-quaternary)",
    separator: "var(--aui-separator)",
    tint: "var(--aui-tint)",
    link: "var(--aui-link)",
    placeholder: "var(--aui-placeholder)",
    selection: "var(--aui-selection)",
};

const FONT_TEXT_STYLES = new Set([
    "largeTitle", "title", "title2", "title3", "headline", "subheadline",
    "body", "callout", "footnote", "caption", "caption2",
]);

// SwiftUI frame alignment -> CSS place-content / place-items ("<block> <inline>",
// i.e. vertical then horizontal), the same vocabulary ZStack/GeometryReader use.
const FRAME_ALIGN = {
    leading: "center start", center: "center center", trailing: "center end",
    top: "start center", bottom: "end center",
    topLeading: "start start", topTrailing: "start end",
    bottomLeading: "end start", bottomTrailing: "end end",
};
// Verbatim copy of View.swift's validAlignments order, so the warning text matches.
const FRAME_ALIGN_VALID = ["leading", "center", "trailing", "top", "bottom",
    "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"];
const FRAME_ALIGN_LIST_TEXT = `[${FRAME_ALIGN_VALID.map((a) => `"${a}"`).join(", ")}]`;

// Nodes that lay out their own children (a flex/grid container) keep that layout;
// turning them into a frame-alignment grid box would collapse it. Frame alignment
// is therefore leaf-oriented, a deliberate divergence for containers.
const SELF_LAYOUT_CLASSES = ["aui-stack", "aui-zstack", "aui-grid", "aui-geometry-reader", "aui-list"];

function nodeManagesOwnLayout(node) {
    return SELF_LAYOUT_CLASSES.some((c) => node.classList.contains(c));
}

export function resolveColor(value, logger) {
    if (typeof value !== "string") return null;
    if (NAMED_COLORS[value]) return NAMED_COLORS[value];
    if (/^#[0-9a-fA-F]{3,8}$/.test(value)) return value;
    // SwiftUI's `<color>.opacity(<fraction>)` (e.g. "gray.opacity(0.15)") - fade the base
    // color toward transparent. Mirrors SwiftUI's Color.opacity(_:); CSS color-mix handles
    // the base being a `var()` semantic color (which rgba()/hex math can't).
    const op = value.match(/^(.+)\.opacity\(\s*([0-9]*\.?[0-9]+)\s*\)$/);
    if (op) {
        const base = resolveColor(op[1], logger); // warns itself if the base is unknown
        if (base === null) return null;
        const pct = Math.round(Math.min(1, Math.max(0, parseFloat(op[2]))) * 100);
        return `color-mix(in srgb, ${base} ${pct}%, transparent)`;
    }
    logger.log(`Unknown color "${value}"`, "warning");
    return null;
}

// SwiftUI's .padding() with no length: 16 pt on each edge on macOS (measured: a 10 x 10 view
// padded that way fits 42 x 42), as on Android.
const DEFAULT_PADDING = 16;

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

// Frame -> CSS, following the SwiftUI frame contract. The browser viewport is the proposed
// size; min/ideal/max clamp against it, per axis:
//   - never below min (the box overflows the window instead of shrinking past it),
//   - apply ideal when it fits the proposal,
//   - never above max even if the proposal is larger.
// In CSS this is the native min/max interaction: ideal -> the base size,
// max -> min(<max>, 100%) (so ideal yields to a smaller window while max caps a
// larger one), min -> the hard floor. A fixed width/height is rigid. maxWidth/
// maxHeight ".infinity" -> a fill class the parent stack resolves per axis (grow
// along its main axis, stretch across its cross axis).
//
// `alignment` positions the (possibly smaller) element within the frame box
// (wrapWithFrameBox), a grid whose one child is placed by place-content/place-items;
// centered without one, as SwiftUI's frame centers the view it wraps.
function applyFrame(node, frame, logger) {
    // --- width axis ---
    if (typeof frame.width === "number") {
        node.style.width = `${frame.width}px`;            // fixed: exactly this wide
    } else if (typeof frame.idealWidth === "number") {
        node.style.width = `${frame.idealWidth}px`;       // ideal: base; yields to a smaller window
        if (frame.maxWidth === undefined) node.style.maxWidth = "100%";
    }
    if (typeof frame.minWidth === "number") node.style.minWidth = `${frame.minWidth}px`;
    if (frame.maxWidth === "infinity") {
        node.classList.add("aui-fill-width");
    } else if (typeof frame.maxWidth === "number") {
        node.style.maxWidth = `min(${frame.maxWidth}px, 100%)`;
        // A finite maxWidth GROWS to the cap (SwiftUI .frame(maxWidth:N) grows up
        // to N, it does not only bound). The axis-aware CAP class makes the element
        // grow - flex along an HStack main axis, width:100% across a VStack cross
        // axis - bounded by the max-width above, and (unlike the fill class) leaves
        // the box positioned by the parent's alignment, so a centered max-width
        // card centers instead of anchoring left. Skipped when the width is already
        // pinned by a fixed/ideal width on this axis.
        if (frame.width === undefined && frame.idealWidth === undefined) {
            node.classList.add("aui-cap-width");
        }
    }

    // --- height axis ---
    if (typeof frame.height === "number") {
        node.style.height = `${frame.height}px`;
    } else if (typeof frame.idealHeight === "number") {
        node.style.height = `${frame.idealHeight}px`;
        if (frame.maxHeight === undefined) node.style.maxHeight = "100%";
    }
    if (typeof frame.minHeight === "number") node.style.minHeight = `${frame.minHeight}px`;
    if (frame.maxHeight === "infinity") {
        node.classList.add("aui-fill-height");
    } else if (typeof frame.maxHeight === "number") {
        node.style.maxHeight = `min(${frame.maxHeight}px, 100%)`;
        // Grow to the cap on the height axis too (see the width axis above).
        if (frame.height === undefined && frame.idealHeight === undefined) {
            node.classList.add("aui-cap-height");
        }
    }

    // A fixed dimension is rigid: it neither grows nor shrinks along that axis.
    if (typeof frame.width === "number" || typeof frame.height === "number") {
        node.style.flexShrink = "0";
    }

    applyFrameAlignment(node, frame.alignment, logger);
}

// Positions content within a larger frame box. Validation is folded in at the
// point of use (the "validate where you read" discipline): a wrong type / value
// logs the same warning string as View.swift validateProperties and is skipped.
function applyFrameAlignment(node, alignment, logger) {
    if (alignment === undefined) return;
    if (typeof alignment !== "string") {
        logger.log(`Invalid type for frame.alignment: expected String, got ${typeof alignment}, ignoring alignment`, "warning");
        return;
    }
    if (!FRAME_ALIGN_VALID.includes(alignment)) {
        logger.log(`Invalid value for frame.alignment: expected one of ${FRAME_ALIGN_LIST_TEXT}, got ${alignment}, ignoring alignment`, "warning");
        return;
    }
    // A frame box holds one element in a track that fills it: the alignment places the
    // element in the track.
    if (node.classList.contains("aui-frame-box")) {
        node.style.placeItems = FRAME_ALIGN[alignment];
        return;
    }
    // A container manages its own children's layout; converting it to a grid box
    // would collapse it, so frame.alignment is leaf-oriented (documented divergence).
    if (nodeManagesOwnLayout(node)) return;
    // .aui-frame-align is display:grid via a class, not an inline style, so a view's own
    // inline `display` toggle (TabView panels, NavigationStack panes) still wins.
    node.classList.add("aui-frame-align");
    const place = FRAME_ALIGN[alignment];
    node.style.placeContent = place;
    node.style.placeItems = place;
}

// "This node dispatches its own action." Two consumers, and both readings matter:
//  - at BUILD time, the generic actionID wiring below skips a node already marked, so an
//    interactive control (Button, Toggle, Picker, ...) keeps its control-specific semantics
//    instead of getting a second, generic click handler;
//  - at CLICK time, `innerHandlerServed` treats a marked DESCENDANT as having served the
//    click, so an enclosing tappable container stands down.
// A tappable container marks itself too, after it is wired - it does dispatch its own
// action, so a container above it must not fire as well.
export function markHandlesAction(node) {
    node.dataset.auiHandlesAction = "1";
}

// True when a bubbling click was already served by a descendant that dispatches its
// own action - a Button, a Toggle, a Picker: anything that called markHandlesAction.
// Walking UP from the event target and stopping AT `node` keeps the question local: a
// marked ancestor above this container answered for that container, not for this one,
// and a marked `node` itself never reaches here (the caller checks it first).
function innerHandlerServed(event, node) {
    for (let n = event.target; n && n !== node; n = n.parentNode) {
        if (n.dataset?.auiHandlesAction) return true;
    }
    return false;
}

// True when this node, or any ancestor, is disabled - asked at EVENT time, not wire time.
//
// A tappable container is a plain <div role="button">, not a native control, so neither
// defense a real control gets applies to it: there is no `node.disabled` to set, and the
// `.aui-disabled { pointer-events: none }` rule stops POINTER events only. A keyboard
// Enter/Space on a focused disabled cell still reached the listener and dispatched, so
// "a disabled container is inert" held for the mouse and quietly failed for the keyboard -
// exactly the direction this pattern is supposed to be an improvement in.
//
// Reading the class off the nearest disabled ancestor answers both halves in one check -
// the element's own `disabled` and an inherited one - and stays correct when a host flips
// it later through setElementProperty, because that applier toggles this same class.
// Apple needs two separate routes here (ContainerAction.resolve for the container's own
// `disabled`, \.isEnabled for an ancestor's) and Android gets both from LocalActionUIEnabled.
function containerActionDisabled(node) {
    return node.closest?.(".aui-disabled") != null;
}

// Per-property appliers for runtime `setElementProperty` mutations — each sets ONE
// visual View property on an already-mounted node, bidirectionally (so a host can
// turn a property on AND off). Deliberately surgical (not a re-run of
// applyViewModifiers): re-running that additive pass would clobber styles a view's
// own buildView set (e.g. a shape's fill) and double-bind its listeners. Covers the
// animatable / host-driven visual properties; properties read inside an element's
// buildView (Text `text`, Button `title`, ...) are not here — those are the value
// bridge's job. Each applier resets to the CSS default when the value is absent.
const PROPERTY_APPLIERS = {
    // Opacity, scale and rotation come after the background and the clip on Apple, so with a
    // frame box they apply to the box (its padding and background fade and turn with the element).
    opacity: (node, value) => { (node.auiFrameBox ?? node).style.opacity = typeof value === "number" ? String(value) : ""; },
    hidden: (node, value) => {
        const on = value === true;
        node.style.visibility = on ? "hidden" : "";
        // The decoration / safe-area inset wrapper around the node, if any (buildElementView).
        if (node.auiHiddenRoot) node.auiHiddenRoot.style.visibility = on ? "hidden" : "";
        // Toolbar chrome COLLAPSES rather than reserving its slot (Helpers/ToolbarHelper.js).
        // Chrome nodes are built even when authored hidden, precisely so this path works:
        // a host can reveal a hidden bar item at runtime the way Android's recomposing
        // chromeHidden does. `.aui-chrome-item` is the marker; `.aui-chrome-hidden` is
        // display:none in theme.css.
        //
        // Gated on `data-aui-chrome`, THEN closest(): renderChromeItem puts the collapse
        // class on the node buildElementView returns (the outermost wrapper) and the flag
        // on the node carrying `data-aui-id`, which is the inner element node once a
        // wrapper is in play - so the walk up is what finds the class from the node the
        // bridge resolved. The flag is what keeps the walk honest: a chrome item's
        // DESCENDANTS are addressable too (a toolbar Menu stamps `data-aui-id` on every
        // row), and without it hiding one row would vanish the whole Menu, while revealing
        // a sibling row would resurrect it - one shared boolean class, N writers, no
        // ownership. A nested id has no flag, so it just hides itself.
        if (node.dataset?.auiChrome) {
            node.closest?.(".aui-chrome-item")?.classList.toggle("aui-chrome-hidden", on);
        }
    },
    cornerRadius: (node, value) => {
        const target = node.auiFrameBox ?? node;
        if (typeof value === "number") {
            target.style.borderRadius = `${value}px`;
            target.style.overflow = "hidden";
        } else {
            target.style.borderRadius = "";
            target.style.overflow = "";
        }
    },
    help: (node, value) => { (node.auiFrameBox ?? node).title = typeof value === "string" ? value : ""; },
    disabled: (node, value) => {
        const on = value === true;
        node.classList.toggle("aui-disabled", on);
        if ("disabled" in node) node.disabled = on;
        const control = node.querySelector?.("button, input, textarea, select");
        if (control) control.disabled = on;
    },
    foregroundStyle: (node, value, logger) => { node.style.color = resolveColor(value, logger) ?? ""; },
    background: (node, value, logger) => {
        (node.auiFrameBox ?? node).style.backgroundColor = resolveColor(value, logger) ?? "";
    },
    // The independent CSS `scale` / `rotate` transform properties (not `transform`),
    // so the two compose without clobbering each other and each animates on its own.
    scaleEffect: (node, value) => { (node.auiFrameBox ?? node).style.scale = typeof value === "number" ? String(value) : ""; },
    rotationEffect: (node, value) => { (node.auiFrameBox ?? node).style.rotate = typeof value === "number" ? `${value}deg` : ""; },
};

// Lets a view module contribute a runtime `setElementProperty` applier for a
// property it reads inside its own buildView (e.g. Picker `options`). Apple/Android
// recompose such properties for free off the mutated element; the web has no
// reactive re-render, so the owning view registers a surgical DOM rebuild here at
// import time. Keeps the structural knowledge in the view, not in this generic file.
export function registerElementPropertyApplier(name, applier) {
    PROPERTY_APPLIERS[name] = applier;
}

// Applies one runtime property mutation to [node]. Returns true if [name] is a
// host-settable visual property (and was applied), false (with a warning) otherwise.
export function applyElementProperty(node, name, value, logger) {
    const applier = PROPERTY_APPLIERS[name];
    if (!applier) {
        logger.log(
            `setElementProperty: '${name}' is not a host-settable visual property on web; ignored ` +
            `(supported: ${Object.keys(PROPERTY_APPLIERS).join(", ")}).`,
            "warning",
        );
        return false;
    }
    applier(node, value, logger);
    return true;
}

// True when the element gets a frame box (wrapWithFrameBox): it has a frame or padding.
export function needsFrameBox(properties) {
    return properties.padding !== undefined
        || (typeof properties.frame === "object" && properties.frame !== null);
}

// The frame box: a wrapper around the element that carries its padding, frame, background
// and corner radius, in View.applyModifiers' order (padding, then frame, then background and
// the clip), as SwiftUI's modifiers wrap a view. The element keeps its own size inside it and
// is placed by the frame's alignment (centered by default), so a VStack in a bigger frame is
// centered, as SwiftUI's frame centers the view it wraps, and a Color's fill stops at its
// padding. The box is the parent stack's child, so it takes the frame's fill and cap classes.
// data-aui-id stays on the element, like the other wraps; the runtime background and corner
// radius appliers find the box through node.auiFrameBox.
export function wrapWithFrameBox(content, node, properties, logger) {
    return finishFrameBox(makeFrameBox(node, properties, logger), content, node, properties);
}

// The frame box with its padding, frame, background, clip and effects, not yet holding the
// element: made before applyViewModifiers so the interactions it wires (actionID, hover, drop,
// help, contextMenu) cover the padding and background, as on Apple, where they come after the
// modifiers.
export function makeFrameBox(node, properties, logger) {
    const box = document.createElement("div");
    box.className = "aui-frame-box";
    if (properties.padding !== undefined) applyPadding(box, properties.padding, logger);
    if (typeof properties.frame === "object" && properties.frame !== null) {
        applyFrame(box, properties.frame, logger);
    }
    applyBoxPaint(box, properties, logger);
    applyBoxEffects(box, properties);
    node.auiFrameBox = box;
    return box;
}

// Puts `content` (the element, or its pull-to-refresh wrapper) in the box and gives the box its
// content's expansion.
export function finishFrameBox(box, content, node, properties) {
    // The `animation` transition applyAnimation armed on the element: the box carries the
    // background, corner radius, opacity, scale and rotation now, so a runtime change of those
    // eases on the box too.
    for (const name of ["transitionProperty", "transitionDuration", "transitionTimingFunction", "transitionDelay"]) {
        if (node.style[name]) box.style[name] = node.style[name];
    }
    // The box expands where its content does, unless its frame sets that axis's size or cap.
    const frame = typeof properties.frame === "object" && properties.frame !== null ? properties.frame : {};
    // A control that fills its proposal in SwiftUI (a TextField's width, a List) fills its box.
    const [greedyWidth, greedyHeight] = greedyAxes(node.dataset?.auiType, properties);
    if (greedyWidth) content.classList.add("aui-expands-w");
    if (greedyHeight) content.classList.add("aui-expands-h");
    box.auiBoxPass = { content, properties };
    markBoxExtent(box);
    box.appendChild(content);
    return box;
}

// The frame box's expansion and extent from its frame and its content (finishFrameBox); run
// again after a child of the content is inserted or removed (refreshExpansion).
function markBoxExtent(box) {
    const { content, properties } = box.auiBoxPass;
    beginPass(box);
    const frame = typeof properties.frame === "object" && properties.frame !== null ? properties.frame : {};
    const [expandsWidth, expandsHeight] = expansionOf(content, null);
    // The box's extent per axis, as SwiftUI's frame and padding give it: the frame's own size or
    // cap where it sets one; else the content's cap or fixed size plus the padding, at least the
    // frame's minimum; else it expands where the content does.
    // A negative side makes CSS drop the whole padding declaration, so none is drawn.
    const pad = paddingIsDrawn(properties.padding)
        ? { w: horizontalPadding(properties.padding), h: verticalPadding(properties.padding) }
        : { w: 0, h: 0 };
    for (const a of ["w", "h"]) {
        const fixed = a === "w" ? frame.width : frame.height;
        const maximum = a === "w" ? frame.maxWidth : frame.maxHeight;
        const minimum = a === "w" ? frame.minWidth : frame.minHeight;
        if (typeof fixed === "number") {
            box.auiExtent = { ...(box.auiExtent ?? {}), [a]: { kind: "fixed", value: fixed } };
            continue;
        }
        if (typeof maximum === "number") {
            box.auiExtent = { ...(box.auiExtent ?? {}), [a]: { kind: "cap", value: Math.max(maximum, typeof minimum === "number" ? minimum : 0) } };
            continue;
        }
        if (maximum !== undefined) continue; // infinity: the fill class
        const expands = a === "w" ? expandsWidth : expandsHeight;
        const ideal = a === "w" ? frame.idealWidth : frame.idealHeight;
        if (typeof ideal === "number") {
            // The ideal is the box's CSS size (applyFrame), not the content's: no extent is
            // recorded, and the box expands where the content does.
            if (expands) markClass(box, a === "w" ? "aui-expands-w" : "aui-expands-h");
            continue;
        }
        const known = content.auiExtent?.[a];
        const floor = typeof minimum === "number" ? minimum : 0;
        if (expands && known?.kind === "cap") {
            setExtent(box, a, "cap", Math.max(known.value + pad[a], floor));
        } else if (expands) {
            markClass(box, a === "w" ? "aui-expands-w" : "aui-expands-h");
        } else if (known?.kind === "fixed" && typeof minimum !== "number") {
            box.auiExtent = { ...(box.auiExtent ?? {}), [a]: { kind: "fixed", value: known.value + pad[a] } };
        }
    }
}

// The element types that fill the space they are offered in SwiftUI, in both axes or in width
// only; everything else (Text, Button, Toggle, Image, ...) keeps its own size. A view in a frame
// box takes the box's size only where it fills, so a Text in a wide frame is centered, as in
// SwiftUI. (Shapes and stacks are told by their classes: aui-shape, markExpansion.)
// Measured on macOS 27 (a view hosted alone in a 600 x 400 window): GroupBox, a segmented Picker
// and the circular ProgressView keep their content size; the lazy stacks and grids fill their
// scroll axis only (LazyVStack and LazyVGrid the width, LazyHStack and LazyHGrid the height); a
// ScrollView fills the axes it scrolls. A Form and a NavigationStack fill only through their
// children (a Form with a TextField fills the width, a NavigationStack with a List fills both),
// which this list cannot see, so they are taken as filling, their usual content.
const GREEDY_BOTH = new Set(["List", "Table", "MapEmbed", "Map", "WebView", "VideoPlayer", "Canvas", "GeometryReader",
    "TabView", "NavigationStack", "NavigationSplitView", "TextEditor"]);
const GREEDY_WIDTH = new Set(["TextField", "SecureField", "Slider", "DisclosureGroup", "Form", "LazyVGrid", "LazyVStack"]);
const GREEDY_HEIGHT = new Set(["LazyHGrid", "LazyHStack"]);

function greedyAxes(type, properties) {
    if (GREEDY_BOTH.has(type)) return [true, true];
    if (GREEDY_WIDTH.has(type)) return [true, false];
    if (GREEDY_HEIGHT.has(type)) return [false, true];
    if (type === "ProgressView") return [properties.progressViewStyle !== "circular", false];
    if (type === "Gauge") return [!(typeof properties.style === "string" && properties.style.includes("Circular")), false];
    if (type === "ScrollView") {
        const axis = properties.axis ?? "vertical";
        return [axis !== "vertical", axis !== "horizontal"];
    }
    return [false, false];
}

// Whether a stack child (its outermost node) expands in width and in height, as SwiftUI's
// views do: a Color or shape with no fixed size in that axis, a frame that fills or caps it,
// a container one of whose children does (markExpansion), a Spacer along its stack's axis, and a
// Divider across it.
function expansionOf(child, parentAxis) {
    const c = child.classList;
    if (!c) return [false, false];
    if (c.contains("aui-spacer")) {
        return [parentAxis === StackAxis.Horizontal, parentAxis === StackAxis.Vertical];
    }
    // A Divider fills across its stack: a vertical rule in an HStack, a horizontal one in a VStack.
    if (c.contains("aui-divider")) {
        return [parentAxis === StackAxis.Vertical, parentAxis === StackAxis.Horizontal];
    }
    const shape = c.contains("aui-shape");
    const width = (shape && !child.style.width) || c.contains("aui-fill-width") || c.contains("aui-cap-width")
        || c.contains("aui-expands-w");
    const height = (shape && !child.style.height) || c.contains("aui-fill-height") || c.contains("aui-cap-height")
        || c.contains("aui-expands-h");
    return [width, height];
}

// A stack or ZStack expands in an axis when one of its children does, as in SwiftUI (a VStack
// holding a Color fills what it is offered): marked with aui-expands-w / aui-expands-h, which
// the parent stack and the frame box read. Where every child's extent in an axis is known (a
// fixed size, or a cap such as a frame's maxWidth or ContentUnavailableView's 400), the
// container's own extent follows, as SwiftUI's stacks compute it: the sum along the stack plus
// its spacing, the largest across it. Then an expanding container is capped there (aui-cap-*
// and a max size, as a frame's maxWidth is) instead of expanding without limit, and a container
// that does not expand records its fixed size for its own parent. `inset` adds a container's
// own CSS padding (a GroupBox card's 5 on each side). Called once the children are built.
export function markExpansion(node, inset = { w: 0, h: 0 }) {
    const zstack = node.classList.contains("aui-zstack");
    if (!node.classList.contains("aui-stack") && !zstack) return;
    beginPass(node);
    node.auiPass = { inset };
    const axis = zstack ? null : (node.dataset.auiAxis ?? null);
    const children = layoutChildren(node);
    let width = false;
    let height = false;
    for (const child of children) {
        const [childWidth, childHeight] = expansionOf(child, axis);
        width ||= childWidth;
        height ||= childHeight;
    }
    const along = (a) => (a === "w" ? axis === StackAxis.Horizontal : axis === StackAxis.Vertical);
    // A container that fills an axis by type (a Form, a LazyVStack) is not held to its children.
    const [greedyWidth, greedyHeight] = greedyAxes(node.dataset?.auiType, {});
    for (const [a, expands] of [["w", width], ["h", height]]) {
        const extents = children.map((child) => extentOf(child, a, axis));
        const greedy = a === "w" ? greedyWidth : greedyHeight;
        if (greedy || extents.some((e) => e.kind === "unknown" || e.kind === "unbounded")) {
            if (expands) markClass(node, a === "w" ? "aui-expands-w" : "aui-expands-h");
            continue;
        }
        const values = extents.map((e) => e.value);
        let total;
        if (along(a)) {
            const shown = children.filter((child) => !child.classList.contains("aui-empty")).length;
            total = values.reduce((sum, value) => sum + value, 0) + Math.max(shown - 1, 0) * stackSpacing(node);
        } else {
            total = values.reduce((most, value) => Math.max(most, value), 0);
        }
        total += inset[a];
        setExtent(node, a, expands ? "cap" : "fixed", total);
    }
}

// A stack's children as its layout sees them: a Group's children (display: contents) in its place.
function layoutChildren(node) {
    const result = [];
    for (const child of node.children) {
        if (child.classList?.contains("aui-group")) {
            result.push(...layoutChildren(child));
        } else {
            result.push(child);
        }
    }
    return result;
}

// The spacing between a stack's shown children: its inline gap, or 8 for SwiftUI's default
// (aui-default-spacing; no Spacer is among them when this is asked, a Spacer being unbounded).
function stackSpacing(node) {
    if (node.classList.contains("aui-default-spacing")) return 8;
    const gap = parseFloat(node.style.gap);
    return Number.isFinite(gap) ? gap : 0;
}

// A child's extent in axis `a` ("w" or "h") inside a parent laid out along `parentAxis`: a fixed
// size, a cap (it expands up to it), unbounded (it expands without one) or unknown (its content
// decides, as a Text's does).
function extentOf(child, a, parentAxis) {
    const c = child.classList;
    if (c?.contains("aui-empty")) return { kind: "fixed", value: 0 };
    const alongParent = a === "w" ? parentAxis === StackAxis.Horizontal : parentAxis === StackAxis.Vertical;
    if (c?.contains("aui-spacer")) return alongParent ? { kind: "unbounded" } : { kind: "fixed", value: 0 };
    const [expandsWidth, expandsHeight] = expansionOf(child, parentAxis);
    const known = child.auiExtent?.[a];
    if (a === "w" ? expandsWidth : expandsHeight) {
        return known?.kind === "cap" ? known : { kind: "unbounded" };
    }
    return known?.kind === "fixed" ? known : { kind: "unknown" };
}

// Records a node's extent in axis `a` and, for a cap, makes it expand only up to it.
function setExtent(node, a, kind, value) {
    node.auiExtent = { ...(node.auiExtent ?? {}), [a]: { kind, value } };
    if (kind !== "cap") return;
    markClass(node, a === "w" ? "aui-cap-width" : "aui-cap-height");
    if (a === "w") {
        node.style.maxWidth = `min(${value}px, 100%)`;
        node.auiMarks.maxWidth = true;
    } else {
        node.style.maxHeight = `min(${value}px, 100%)`;
        node.auiMarks.maxHeight = true;
    }
}

// Starts an extent pass on a node: takes off what its last pass set (the classes and max sizes
// recorded in auiMarks, never a frame's own) and forgets its extent.
function beginPass(node) {
    const marks = node.auiMarks;
    if (marks) {
        for (const name of marks.classes) node.classList.remove(name);
        if (marks.maxWidth) node.style.maxWidth = "";
        if (marks.maxHeight) node.style.maxHeight = "";
    }
    node.auiMarks = { classes: [], maxWidth: false, maxHeight: false };
    node.auiExtent = undefined;
}

// Adds a class an extent pass decided, so the next pass can take it off.
function markClass(node, name) {
    node.classList.add(name);
    node.auiMarks.classes.push(name);
}

// After a child is inserted into or removed from `container` at run time: its extent pass runs
// again, and each ancestor's, stack or frame box, up the tree, as the marks made at build time
// no longer hold (a Text inserted beside a capped Color makes its stack unbounded again).
export function refreshExpansion(container) {
    for (let node = container; node && node.nodeType === 1; node = node.parentNode) {
        if (node.auiPass) markExpansion(node, node.auiPass.inset);
        if (node.auiBoxPass) markBoxExtent(node);
    }
}

// The leading plus trailing padding of a padding property, in points.
function horizontalPadding(padding) {
    if (typeof padding === "number") return 2 * padding;
    if (padding === "default") return 2 * DEFAULT_PADDING;
    if (typeof padding === "object" && padding !== null) {
        return (Number(padding.leading) || 0) + (Number(padding.trailing) || 0);
    }
    return 0;
}

// False when a side of a padding property is negative: CSS drops the whole padding declaration
// applyPadding writes, so the box draws none of it.
function paddingIsDrawn(padding) {
    if (typeof padding === "number") return padding >= 0;
    if (typeof padding === "object" && padding !== null) {
        return !Object.values(padding).some((side) => Number(side) < 0);
    }
    return true;
}

// The top plus bottom padding of a padding property, in points.
function verticalPadding(padding) {
    if (typeof padding === "number") return 2 * padding;
    if (padding === "default") return 2 * DEFAULT_PADDING;
    if (typeof padding === "object" && padding !== null) {
        return (Number(padding.top) || 0) + (Number(padding.bottom) || 0);
    }
    return 0;
}

// Background and corner radius, on the frame box when there is one, else on the element.
function applyBoxPaint(target, properties, logger) {
    if (typeof properties.cornerRadius === "number") {
        target.style.borderRadius = `${properties.cornerRadius}px`;
        target.style.overflow = "hidden";
    }
    const background = resolveColor(properties.background, logger);
    if (background) target.style.backgroundColor = background;
}

// Opacity, scale and rotation, on the frame box when there is one, else on the element (they
// come after the background and the clip on Apple).
function applyBoxEffects(target, properties) {
    if (typeof properties.opacity === "number") target.style.opacity = String(properties.opacity);
    if (typeof properties.scaleEffect === "number") target.style.scale = String(properties.scaleEffect);
    if (typeof properties.rotationEffect === "number") target.style.rotate = `${properties.rotationEffect}deg`;
}

export function applyViewModifiers(node, element, properties, ctx) {
    const { logger } = ctx;
    // With a frame box, padding, frame, background and corner radius go on the box instead.
    const boxed = needsFrameBox(properties);

    if (properties.padding !== undefined && !boxed) applyPadding(node, properties.padding, logger);
    // `hidden` is SwiftUI's `.hidden()`, not `display: none`: the element stays LAID OUT -
    // its space is reserved - while being invisible and untouchable. CSS
    // `visibility: hidden` is that primitive: the box is still generated and sized, it is
    // not painted, it is not hit-tested, and it drops out of both the tab order and the
    // accessibility tree, so no extra `pointer-events` or `aria-hidden` is needed.
    // `display: none` - what this was until 2026-08-20 - COLLAPSED the box instead, so
    // identical JSON laid out differently here than on Apple (`.hidden()`) and Android
    // (`Modifier.hiddenSubtree()` plus the environment narrowing around it - however
    // Android suppresses input at any given time, all of it is layout-inert and the space
    // stays reserved).
    //
    // One place where matching Apple is NOT the goal, deliberately: accessibility. Apple's
    // `.hidden()` leaves the element IN the accessibility tree, which is why a host hiding
    // chrome on Apple must also author `accessibilityHidden` and blank the label. Web and
    // Android both drop it. That is better, not parity.
    //
    // The element's painted decoration hides with it on every host: Apple applies
    // `.hidden()` after the background, border, overlay, safe-area inset and shadow.
    // Here `visibility: hidden` covers the element's own paint (background color, corner
    // radius), and buildElementView puts it on the outermost decoration / swipe /
    // safe-area inset wrapper too, so the view-valued background/overlay and the inset bar
    // hide as well. The searchable field and toolbar chrome outside those stay, as on Apple.
    //
    // There is no collapse semantic on any host; the ZStack panel-switcher idiom (all
    // bodies overlaid, one visible) is what authors use instead. Toolbars are the single
    // exception - see the chrome note in Helpers/ToolbarHelper.js.
    if (properties.hidden === true) node.style.visibility = "hidden";
    if (!boxed) applyBoxPaint(node, properties, logger);

    const foreground = resolveColor(properties.foregroundStyle, logger);
    if (foreground) node.style.color = foreground;

    if (typeof properties.font === "string") {
        if (FONT_TEXT_STYLES.has(properties.font)) {
            node.classList.add(`aui-font-${properties.font}`);
        } else {
            node.style.fontFamily = properties.font;
        }
    }

    if (typeof properties.frame === "object" && properties.frame !== null && !boxed) {
        applyFrame(node, properties.frame, logger);
    }

    // opacity, scaleEffect / rotationEffect (the independent CSS scale / rotate transform
    // properties, SwiftUI .scaleEffect / .rotationEffect). Animatable, and the
    // setElementProperty bridge mutates the same three for runtime animation. With a frame box
    // they go on the box (wrapWithFrameBox): on Apple they come after the background and the
    // clip, so the padding and background fade and turn with the element.
    if (!boxed) applyBoxEffects(node, properties);

    if (properties.disabled === true) {
        node.classList.add("aui-disabled");
        if ("disabled" in node) node.disabled = true;
        const control = node.querySelector?.("button, input, textarea, select");
        if (control) control.disabled = true;
    }

    // The interactions cover the frame box when there is one: its padding and background are
    // part of the view a tap, a hover, a drop or a help tag reaches, as on Apple.
    const hit = node.auiFrameBox ?? node;

    if (typeof properties.help === "string") hit.title = properties.help;

    // A view carrying an actionID is tappable as a whole - the way a rich cell wants to
    // be: one target, one a11y element, instead of a small glyph Button inside it.
    //
    // Two things were wrong here. Inside a template row the dispatch carried
    // `element.id`, which Helpers/TemplateHelper.js forces to 0 on every cloned
    // instance, so a whole-cell tap arrived with NO row identity and no way to recover
    // one - the handler could not tell row 0 from row 9. It now reads
    // ctx.templateContext, exactly as Views/Button.js does two files over.
    //
    // And a DOM click BUBBLES, which the other two hosts do not have to think about:
    // SwiftUI resolves a tap to the innermost control and Compose's inner clickable
    // consumes the press, so on those hosts exactly one handler runs. On the web every
    // ancestor listener runs unless something stops it, and that produced three separate
    // double-dispatches:
    //
    //   1. a Button (or any control that called markHandlesAction) inside a tappable
    //      container fired its own action AND the container's;
    //   2. a tappable container inside ANOTHER tappable container fired both;
    //   3. a tappable container inside a selectable List row fired the cell action AND
    //      selected the row - List guards with its own `INTERACTIVE_SELECTOR` of native
    //      control tags, and a container is a plain <div> that never matches it.
    //
    // `innerHandlerServed` answers (1). Marking the node and stopping propagation answers
    // (2) and (3) together, and is the convention already used by Views/List.js and
    // Views/Table.js for a cell's own tap: once this container has served the click, no
    // ancestor should treat it as theirs. markHandlesAction must come AFTER the wire-time
    // check above, or the container would opt itself out before it is wired.
    // A blank actionID is refused rather than wiring a target that dispatches an
    // unroutable empty id - matching ContainerAction.resolve on Apple and
    // containerActionDispatch on Android, so all three hosts agree.
    if (typeof properties.actionID === "string" && properties.actionID.trim() !== ""
        && !node.dataset.auiHandlesAction) {
        const actionID = properties.actionID;
        const templateContext = ctx.templateContext;
        const viewID = templateContext ? templateContext.parentID : element.id;
        const viewPartID = templateContext ? templateContext.rowIndex : 0;
        markHandlesAction(hit);
        const dispatch = () => ctx.model.dispatchAction(actionID, viewID, viewPartID, null);
        hit.addEventListener("click", (event) => {
            if (containerActionDisabled(node)) return;
            if (innerHandlerServed(event, hit)) return;
            event.stopPropagation();
            dispatch();
        });
        // The accessibility and keyboard half of "one tap target". A bare <div> with a click
        // listener is invisible to a screen reader and unreachable by keyboard, so without
        // this the pattern is an improvement for a mouse and a regression for everyone else -
        // the opposite of the reason to prefer it over a leading-glyph Button. Views/List.js
        // does the same for its rows (role, tabIndex, Enter/Space). Apple gets there with
        // .accessibilityAddTraits(.isButton); Android with clickable(role = Role.Button),
        // which merges descendant semantics for free.
        //
        // A container disabled at build time is kept OUT of the tab order rather than left
        // as a focusable stop that does nothing - `disabled` is not a real attribute on a
        // <div>, so nothing else would remove it. `containerActionDisabled` above is still
        // what makes it inert, since a host can flip `disabled` later.
        hit.setAttribute("role", "button");
        hit.tabIndex = containerActionDisabled(node) ? -1 : 0;
        hit.style.cursor = "pointer";
        hit.addEventListener("keydown", (event) => {
            if (event.key !== "Enter" && event.key !== " ") return;
            if (containerActionDisabled(node)) return;
            if (innerHandlerServed(event, hit)) return; // a focused inner control answers first
            event.preventDefault();                      // Space would scroll the page
            event.stopPropagation();
            dispatch();
        });
    }

    // onAppearActionID: SwiftUI `.onAppear` parity (Apple/Android fire it when the
    // element enters composition; see ActionHookHelper.kt / View.swift). The web has
    // no reactive lifecycle, so we fire once after the synchronous mount via a
    // microtask - by then the node is in the DOM and the host's app.action handlers
    // are registered (they run in the same synchronous task as presentWindow). viewID
    // is the element id and context is null, matching the native hosts. Guarded per
    // node so a rebuild of the same node fires at most once. (onDisappearActionID has
    // no web element-unmount lifecycle yet; deferred.)
    if (typeof properties.onAppearActionID === "string" && !node.dataset.auiAppeared) {
        node.dataset.auiAppeared = "1";
        const onAppearActionID = properties.onAppearActionID;
        const viewID = element.id;
        queueMicrotask(() => ctx.model.dispatchAction(onAppearActionID, viewID, 0, null));
    }

    applyHoverDrop(hit, element, properties, ctx);

    // contextMenu (any view): a right-click / long-press floating menu of action
    // items (Helpers/ContextMenuModifier.js). A no-op unless a valid contextMenu is
    // declared. The Apple parity is `.contextMenu`; the Android parity is the
    // long-press DropdownMenu.
    applyContextMenu(hit, element, properties, ctx);

    // ignoresSafeArea: extend this view into the safe area (negative env() margins on the chosen
    // edges). A no-op when absent/false, or on a non-notched / desktop screen (env() is 0).
    applyIgnoresSafeArea(node, properties);
}

// UTType identifiers that the web treats as a plain-text drag (DataTransfer
// "text/plain"); anything else in onDropTypes is treated as a file drag. Mirrors
// DropHelper.swift's utf8PlainText/plainText -> file-url priority, but coarsely:
// the HTML5 DnD spec hides item contents during dragover, so we cannot filter by
// concrete type until the drop actually lands.
const DROP_TEXT_TYPES = new Set([
    "public.utf8-plain-text", "public.plain-text", "public.text", "public.rtf",
]);

function dropTypesAccept(types) {
    let text = false;
    let files = false;
    for (const t of types) {
        if (DROP_TEXT_TYPES.has(t)) text = true;
        else files = true; // file-url / url / image / folder / data / item / ...
    }
    return { text, files };
}

// onHover / onDrop / onDropTargeted base modifiers (Apple: View.swift +
// Helpers/DropHelper.swift). Validation is folded in at the point of use ("validate
// where you read"): a present-but-wrong-typed property logs the same warning string
// as Swift and is skipped. Listeners are GC'd with the node, so no cleanup hook is
// needed (unlike a Map provider instance).
function applyHoverDrop(node, element, properties, ctx) {
    const { logger } = ctx;

    // onHover -> pointerenter/pointerleave (do not bubble across children, matching
    // .onHover). isHovering travels as the action context dict.
    if (properties.onHoverActionID !== undefined) {
        if (typeof properties.onHoverActionID === "string") {
            const actionID = properties.onHoverActionID;
            node.addEventListener("pointerenter", () => {
                ctx.model.dispatchAction(actionID, element.id, 0, { isHovering: true });
            });
            node.addEventListener("pointerleave", () => {
                ctx.model.dispatchAction(actionID, element.id, 0, { isHovering: false });
            });
        } else {
            logger.log(`Invalid type for onHoverActionID: expected String, got ${typeof properties.onHoverActionID}, ignoring`, "warning");
        }
    }

    // onDropActionID / onDropTypes / onDropTargetedActionID. A view is a drop target
    // only when onDropActionID is a String AND onDropTypes is a non-empty [String]
    // (matches the View.swift gate). Validate each independently so wrong types log
    // the verbatim Swift warning.
    let onDropActionID = null;
    if (properties.onDropActionID !== undefined) {
        if (typeof properties.onDropActionID === "string") onDropActionID = properties.onDropActionID;
        else logger.log(`Invalid type for onDropActionID: expected String, got ${typeof properties.onDropActionID}, ignoring`, "warning");
    }

    let onDropTypes = null;
    if (properties.onDropTypes !== undefined) {
        if (Array.isArray(properties.onDropTypes) && properties.onDropTypes.length > 0
            && properties.onDropTypes.every((t) => typeof t === "string")) {
            onDropTypes = properties.onDropTypes;
        } else {
            logger.log(`Invalid type for onDropTypes: expected non-empty [String], got ${typeof properties.onDropTypes}, ignoring`, "warning");
        }
    }

    let onDropTargetedActionID = null;
    if (properties.onDropTargetedActionID !== undefined) {
        if (typeof properties.onDropTargetedActionID === "string") onDropTargetedActionID = properties.onDropTargetedActionID;
        else logger.log(`Invalid type for onDropTargetedActionID: expected String, got ${typeof properties.onDropTargetedActionID}, ignoring`, "warning");
    }

    if (!onDropActionID || !onDropTypes) return; // not a drop target

    const accept = dropTypesAccept(onDropTypes);

    // dragenter/dragleave fire once per descendant, so track depth and only report
    // the 0<->1 transition as the targeted state change.
    let depth = 0;
    const setTargeted = (isTargeted) => {
        if (!onDropTargetedActionID) return;
        ctx.model.dispatchAction(onDropTargetedActionID, element.id, 0, { isTargeted });
    };

    node.addEventListener("dragenter", (e) => {
        e.preventDefault();
        depth += 1;
        if (depth === 1) setTargeted(true);
    });
    node.addEventListener("dragleave", () => {
        depth = Math.max(0, depth - 1);
        if (depth === 0) setTargeted(false);
    });
    node.addEventListener("dragover", (e) => {
        e.preventDefault(); // required to permit a drop
        if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
    });
    node.addEventListener("drop", (e) => {
        e.preventDefault();
        if (depth !== 0) { depth = 0; setTargeted(false); }

        const dt = e.dataTransfer;
        const fileList = dt && accept.files ? Array.from(dt.files) : [];
        const items = [];
        if (dt && accept.text) {
            const text = dt.getData("text/plain");
            if (text) items.push(text);
        }
        // items carries file NAMES (the web's closest analog to Apple's file path);
        // the real File objects ride along in `files` so the host can upload bytes.
        for (const f of fileList) items.push(f.name);

        ctx.model.dispatchAction(onDropActionID, element.id, 0, {
            items,
            location: { x: e.offsetX, y: e.offsetY },
            files: fileList,
        });
    });
}

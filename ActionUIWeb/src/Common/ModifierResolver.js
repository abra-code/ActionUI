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
//                    {isTargeted}. See Helpers/DropHelper.swift (Apple canonical)
//                    and HoverDrop_Design.md; web type-filtering is coarse (the DnD
//                    spec hides item contents during dragover).

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
    // resolved var(). See Private/Semantic_Color_Mapping_Design.md for the table.
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
// is therefore leaf-oriented (the design doc's "leaf-only" step), a documented
// divergence for containers. See Private/ActionUI-Web-Layout-Engine.md (Stage 2b).
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

// Frame -> CSS, following the SwiftUI frame contract (see
// Private/ActionUI-Web-Layout-Engine.md). The browser viewport is the proposed
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
// `alignment` positions the (possibly smaller) content within the frame box. We
// stay single-node (no wrapper, so background/border keep filling the framed
// size) and make the node a grid box (.aui-frame-align) whose content is placed
// by place-content/place-items. Leaf-oriented: a node that lays out its own
// children (stack/grid/...) keeps that layout and ignores frame.alignment.
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
    // A container manages its own children's layout; converting it to a grid box
    // would collapse it, so frame.alignment is leaf-oriented (documented divergence).
    if (nodeManagesOwnLayout(node)) return;
    // .aui-frame-align is display:grid via a class, so an inline display:none from
    // `hidden` (set earlier in applyViewModifiers) still wins by specificity.
    node.classList.add("aui-frame-align");
    const place = FRAME_ALIGN[alignment];
    node.style.placeContent = place;
    node.style.placeItems = place;
}

// Interactive controls wire actionID themselves with control-specific
// semantics; they set this flag to opt out of the generic click handler.
export function markHandlesAction(node) {
    node.dataset.auiHandlesAction = "1";
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
    opacity: (node, value) => { node.style.opacity = typeof value === "number" ? String(value) : ""; },
    hidden: (node, value) => { node.style.display = value === true ? "none" : ""; },
    cornerRadius: (node, value) => {
        if (typeof value === "number") {
            node.style.borderRadius = `${value}px`;
            node.style.overflow = "hidden";
        } else {
            node.style.borderRadius = "";
            node.style.overflow = "";
        }
    },
    help: (node, value) => { node.title = typeof value === "string" ? value : ""; },
    disabled: (node, value) => {
        const on = value === true;
        node.classList.toggle("aui-disabled", on);
        if ("disabled" in node) node.disabled = on;
        const control = node.querySelector?.("button, input, textarea, select");
        if (control) control.disabled = on;
    },
    foregroundColor: (node, value, logger) => { node.style.color = resolveColor(value, logger) ?? ""; },
    background: (node, value, logger) => { node.style.backgroundColor = resolveColor(value, logger) ?? ""; },
    // The independent CSS `scale` / `rotate` transform properties (not `transform`),
    // so the two compose without clobbering each other and each animates on its own.
    scaleEffect: (node, value) => { node.style.scale = typeof value === "number" ? String(value) : ""; },
    rotationEffect: (node, value) => { node.style.rotate = typeof value === "number" ? `${value}deg` : ""; },
};
// `foregroundStyle` is the canonical name; `foregroundColor` is its alias - both set color.
PROPERTY_APPLIERS.foregroundStyle = PROPERTY_APPLIERS.foregroundColor;

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
        applyFrame(node, properties.frame, logger);
    }

    // scaleEffect / rotationEffect -> the independent CSS scale / rotate transform
    // properties (SwiftUI .scaleEffect / .rotationEffect). Animatable, and the
    // setElementProperty bridge mutates the same two for runtime animation.
    if (typeof properties.scaleEffect === "number") node.style.scale = String(properties.scaleEffect);
    if (typeof properties.rotationEffect === "number") node.style.rotate = `${properties.rotationEffect}deg`;

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

    applyHoverDrop(node, element, properties, ctx);

    // contextMenu (any view): a right-click / long-press floating menu of action
    // items (Helpers/ContextMenuModifier.js). A no-op unless a valid contextMenu is
    // declared. The Apple parity is `.contextMenu`; the Android parity is the
    // long-press DropdownMenu.
    applyContextMenu(node, element, properties, ctx);

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

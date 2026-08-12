// ModifierResolver.js — baseline View modifiers applied to every element.
// Web analog of ActionUI/Views/View.swift applyViewModifiers (PoC subset).
//
// Supported subset (property names follow Documentation/Schemas/View.md):
//   padding          Number, "default", or {top, bottom, leading, trailing}
//   hidden           Boolean
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
    foregroundStyle: (node, value, logger) => { node.style.color = resolveColor(value, logger) ?? ""; },
    background: (node, value, logger) => { node.style.backgroundColor = resolveColor(value, logger) ?? ""; },
    // The independent CSS `scale` / `rotate` transform properties (not `transform`),
    // so the two compose without clobbering each other and each animates on its own.
    scaleEffect: (node, value) => { node.style.scale = typeof value === "number" ? String(value) : ""; },
    rotationEffect: (node, value) => { node.style.rotate = typeof value === "number" ? `${value}deg` : ""; },
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

export function applyViewModifiers(node, element, properties, ctx) {
    const { logger } = ctx;

    if (properties.padding !== undefined) applyPadding(node, properties.padding, logger);
    if (properties.hidden === true) node.style.display = "none";
    if (typeof properties.opacity === "number") node.style.opacity = String(properties.opacity);
    if (typeof properties.cornerRadius === "number") {
        node.style.borderRadius = `${properties.cornerRadius}px`;
        node.style.overflow = "hidden";
    }

    const foreground = resolveColor(properties.foregroundStyle, logger);
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
        markHandlesAction(node);
        const dispatch = () => ctx.model.dispatchAction(actionID, viewID, viewPartID, null);
        node.addEventListener("click", (event) => {
            if (containerActionDisabled(node)) return;
            if (innerHandlerServed(event, node)) return;
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
        node.setAttribute("role", "button");
        node.tabIndex = containerActionDisabled(node) ? -1 : 0;
        node.style.cursor = "pointer";
        node.addEventListener("keydown", (event) => {
            if (event.key !== "Enter" && event.key !== " ") return;
            if (containerActionDisabled(node)) return;
            if (innerHandlerServed(event, node)) return; // a focused inner control answers first
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

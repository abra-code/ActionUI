// PresentationModifier.js — element-level sheet / fullScreenCover / popover.
// Web analog of the subview-carrying presentation modifiers in Apple's View.swift
// (SheetHelper.swift / PopoverHelper.swift) and ActionUIAndroid's ViewModifierHelper.
// Part of the build modifier pipeline: buildElementView calls this for every
// element, right after the baseline ModifierResolver, and it is a no-op unless the
// element declares a `sheet`, `fullScreenCover`, or `popover` subview.
//
// Each is driven by a boolean on the *carrier* element's state, the Apple contract:
//   sheet           -> "sheetVisible"
//   fullScreenCover -> "fullScreenCoverVisible"
//   popover         -> "popoverVisible"
// so a host opens/closes it with setElementState(carrierID, key, true|false). A
// Button carrier also opens its sheet/cover and toggles its popover on tap (Apple:
// Button.swift folds the toggle into its action); a non-Button popover toggles on
// its own tap too (PopoverHelper's onTapGesture), while a non-Button sheet/cover is
// host-driven only (SheetHelper adds no gesture). dismiss fires
// sheetOnDismissActionID / fullScreenCoverOnDismissActionID (viewID = carrier id),
// shown popover fires popoverActionID.
//
// Web rendering. sheet and fullScreenCover are native <dialog>s shown with
// showModal() (the same top-layer modal as Scenes/DialogHost.js, with a ::backdrop
// and Escape-to-cancel for free); popover is a shared top-layer floating panel
// (Helpers/PopoverPlacement.js) anchored to the carrier. The content subview is
// built once, up front (registering its value/state bindings into the window model
// so the value/state API reaches the modal's controls by id even before it is
// shown - the web analog of Apple allocating the content's ViewModel up front), and
// reused across show/hide.
//
// Divergences (web is a desktop target, like macOS):
//   * fullScreenCover renders as a full-viewport <dialog>, not an OS cover; like
//     macOS (where SwiftUI falls back to .sheet) it has no system back gesture, so
//     it is dismissed by Escape, the backdrop, or a host setElementState.
//   * the carrier's own decoration modifiers are not re-applied to the presented
//     content (the content is its own subtree); SwiftUI attaches the presentation
//     to the carrier but renders the content independently too.

import { makeFloatingPanel } from "./PopoverPlacement.js";

const POPOVER_EDGES = new Set(["top", "bottom", "leading", "trailing"]);

// Applies any sheet/fullScreenCover/popover presentation declared on `element`.
// A no-op for the (overwhelmingly common) element with none. Returns nothing -
// the carrier `node` is returned unchanged by the caller; this only attaches
// bindings/listeners and the presented surfaces.
export function applyPresentationModifiers(node, element, properties, ctx) {
    const subs = element.subviews;
    if (!subs || (!subs.sheet && !subs.fullScreenCover && !subs.popover)) return;

    // Compose every presentation visibility key into one state binding that
    // delegates unknown keys to the element's own state binding (if it registered
    // one in buildView), so a carrier that also binds state is not clobbered.
    const prior = ctx.model.getStateBinding?.(element.id);
    const getters = {}; // key -> () => boolean
    const setters = {}; // key -> (value) => void

    if (subs.sheet) {
        wireDialogPresentation(node, element, subs.sheet, "sheet", "sheetVisible",
            properties.sheetOnDismissActionID, ctx, getters, setters);
    }
    if (subs.fullScreenCover) {
        wireDialogPresentation(node, element, subs.fullScreenCover, "cover", "fullScreenCoverVisible",
            properties.fullScreenCoverOnDismissActionID, ctx, getters, setters);
    }
    if (subs.popover) {
        wirePopoverPresentation(node, element, subs.popover, properties, ctx, getters, setters);
    }

    // Bind only for host-addressable carriers; the tap handlers above work without
    // an id (a Button popover with no id still toggles on tap), they just are not
    // reachable by setElementState. The binding always answers the visibility keys,
    // so no states-map seeding is needed (and none clobbers the element's own).
    if (element.id > 0) {
        ctx.model.bindState(element.id, {
            getState(key) {
                if (key in getters) return getters[key]();
                return prior?.getState(key);
            },
            setState(key, value) {
                if (key in setters) { setters[key](value); return; }
                prior?.setState(key, value);
            },
        });
    }
}

// sheet / fullScreenCover: a native <dialog> built from the content subview, shown
// with showModal(). `style` is "sheet" or "cover" (the CSS variant). The dialog's
// `close` event is the single dismiss point - Escape, the backdrop, a programmatic
// close, or a close affordance all route through it - firing onDismissActionID
// once, matching SwiftUI's .sheet/.fullScreenCover onDismiss (fired on any
// transition to dismissed).
function wireDialogPresentation(node, element, contentElement, style, key, onDismissActionID, ctx, getters, setters) {
    const contentNode = ctx.build(contentElement); // built up front: registers the content's bindings
    let dialog = null;
    let open = false;

    const ensureDialog = () => {
        if (dialog) return dialog;
        dialog = document.createElement("dialog");
        dialog.className = `aui-modal aui-modal-${style}`;
        dialog.appendChild(contentNode);
        // A click whose target is the dialog itself lands on the backdrop area.
        dialog.addEventListener("click", (event) => { if (event.target === dialog) requestClose(); });
        dialog.addEventListener("close", () => {
            if (!open) return;
            open = false;
            if (typeof onDismissActionID === "string") {
                ctx.model.dispatchAction(onDismissActionID, element.id, 0, null);
            }
        });
        return dialog;
    };
    const show = () => {
        if (open) return;
        open = true;
        const host = ctx.model.rootNode ?? document.body;
        const d = ensureDialog();
        if (d.parentNode !== host) host.appendChild(d);
        d.showModal();
    };
    const requestClose = () => { if (dialog && dialog.open) dialog.close(); }; // -> close listener

    getters[key] = () => open;
    setters[key] = (value) => { if (value) show(); else requestClose(); };

    // A Button carrier opens it on tap; non-Button carriers are host-driven only
    // (Apple's SheetHelper adds no gesture).
    if (element.type === "Button") node.addEventListener("click", () => show());
}

// popover: a shared top-layer floating panel (Helpers/PopoverPlacement.js) anchored
// to the carrier, with the same outside-click/Escape dismissal as Menu.
function wirePopoverPresentation(node, element, contentElement, properties, ctx, getters, setters) {
    const arrowEdge = POPOVER_EDGES.has(properties.popoverArrowEdge) ? properties.popoverArrowEdge : "top";
    const popoverActionID = typeof properties.popoverActionID === "string" ? properties.popoverActionID : null;

    const panel = document.createElement("div");
    panel.className = "aui-popover-panel";
    panel.appendChild(ctx.build(contentElement)); // built up front: registers the content's bindings
    let appended = false;

    const controller = makeFloatingPanel(panel, node, {
        arrowEdge,
        containmentRoots: [node],
        fallbackOpenClass: "is-open",
    });

    const show = () => {
        if (!appended) {
            (ctx.model.rootNode ?? document.body).appendChild(panel); // top-layer overlay sibling
            appended = true;
        }
        controller.show();
    };

    getters.popoverVisible = () => controller.open;
    setters.popoverVisible = (value) => { if (value) show(); else controller.close(); };

    // Tap the carrier to toggle; fire popoverActionID only on the show transition
    // (Apple fires it from the tap, not on dismiss or a host-driven open).
    node.addEventListener("click", () => {
        if (controller.open) {
            controller.close();
        } else {
            show();
            if (popoverActionID) ctx.model.dispatchAction(popoverActionID, element.id, 0, null);
        }
    });
}

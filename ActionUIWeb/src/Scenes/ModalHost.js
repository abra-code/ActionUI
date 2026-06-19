// ModalHost.js — window-level modal (sheet / fullScreenCover).
// Web analog of the *modal* half of ActionUI/Common/WindowModal.swift, driven by
// ActionUIModel.presentModal / dismissModal, and ActionUIAndroid's
// Helpers/WindowModalHost.kt (Android_Porting_Notes). The second member of the
// Phase 3 presentation layer (Scenes/), after DialogHost.
//
// Unlike a window dialog (pure title/message/buttons, Scenes/DialogHost.js), a
// modal loads a JSON sub-document, builds it through the registry - which registers
// every loaded id's value/state binding into the window model, so the value/state/
// rows API reaches the modal's controls by id (the web's implicit "merge", as in
// LoadableView) - and removes exactly those bindings again on dismiss (the web
// analog of WindowModal.loadedViewIDs being pruned from the window's ViewModel
// pool). Presented as a native <dialog> shown with showModal(), reusing the
// element-level sheet/cover surface (theme.css .aui-modal*). Only one window modal
// is active at a time (Apple's single windowModal slot), so presenting replaces any
// current one. The modal's own controls drive dismissal by routing an actionID the
// host maps to dismissModal() (the Modal.json / Android contract), or the user
// dismisses with Escape / the backdrop.
//
// Divergences (web is a desktop target, like macOS):
//   * fullScreenCover is a full-viewport <dialog>, not an OS cover, with no system
//     back gesture - Escape, the backdrop, or a host dismissModal() closes it.
//   * `.plist` descriptions are not supported (no web property-list parser; the
//     LoadableView stance) - pass JSON.

import { ActionUIElement } from "../Common/ActionUIElement.js";
import { PlatformFilter } from "../Common/PlatformFilter.js";
import { collectElementIds } from "../Common/ActionUIInsertion.js";

// Presentation style for a window modal. Mirror of the Node adapter's ModalStyle
// (and Swift's ModalStyle); re-exported from ActionUI.js alongside InsertPosition.
export const ModalStyle = Object.freeze({
    SHEET: "sheet",
    FULL_SCREEN_COVER: "fullScreenCover",
});

// Presents a loaded modal into `host` (the window root). Replaces any active modal.
// `spec` = { data: JSON string, format: "json", style, onDismissActionID }.
// Returns the <dialog> node, or null when the description could not be loaded.
export function presentModal(host, spec, model, logger) {
    dismissActiveModal(host, model); // single active window modal (Apple parity)

    const { data, format, style, onDismissActionID } = spec;
    if (format === "plist") {
        logger.log("presentModal: '.plist' descriptions are not supported on the web (no property-list parser); use JSON", "warning");
        return null;
    }

    let raw;
    try {
        raw = JSON.parse(data);
    } catch (error) {
        logger.log(`presentModal: invalid JSON description: ${error.message}`, "error");
        return null;
    }
    const normalized = PlatformFilter.WEB.withLogger(logger).filter(raw);
    const element = ActionUIElement.fromObject(normalized, logger);
    if (!element) {
        logger.log("presentModal: failed to parse modal description", "error");
        return null;
    }

    // The ids whose bindings this modal adds to the window model - pruned on dismiss.
    const loadedIDs = collectElementIds(element);

    const variant = style === "fullScreenCover" ? "cover" : "sheet";
    const dialog = document.createElement("dialog");
    dialog.className = `aui-modal aui-modal-${variant}`;
    dialog.dataset.auiModal = "1"; // marks the single active window modal (vs element sheets)
    // Build through the registry on the window's render context - registers every
    // loaded id's value/state binding into the model.
    dialog.appendChild(model.buildFn(element));

    // A click whose target is the dialog itself lands on the backdrop area.
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
    // The single dismiss point (Escape, backdrop, close(), or a routed dismissModal):
    // remove the node, prune the modal's bindings, then fire onDismissActionID with
    // viewID 0 (ActionUIModel.dismissModal parity).
    dialog.addEventListener("close", () => {
        dialog.remove();
        for (const id of loadedIDs) model.cleanupElement(id);
        if (typeof onDismissActionID === "string") model.dispatchAction(onDismissActionID, 0, 0, null);
    });

    host.appendChild(dialog);
    dialog.showModal();
    logger.log(`presentModal: ${style}`, "debug");
    return dialog;
}

// Dismisses the active window modal (if any). The host-API dismissModal and the
// Escape/backdrop path share this. Mirrors ActionUIModel.dismissModal.
export function dismissActiveModal(host, model) {
    if (!host) return;
    const existing = host.querySelector("dialog[data-aui-modal]");
    if (existing) existing.close(); // triggers the 'close' listener -> remove + cleanup
}

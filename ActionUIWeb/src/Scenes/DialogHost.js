// DialogHost.js — window-level alerts and confirmation dialogs.
// Web analog of ActionUI/Common/WindowModalView.swift (the SwiftUI .alert /
// .confirmationDialog presenters) and ActionUIAndroid's Material3 AlertDialog
// (Android_Porting_Notes entry 40). The first member of the Phase 3 presentation
// layer (Scenes/), and the first file under src/Scenes/.
//
// A WindowDialog is pure data (title, message, buttons) - no ViewModels are
// allocated, matching WindowModal.swift's WindowDialog. The web renders it as a
// native <dialog> shown with showModal(): the browser's own top-layer modal, with
// a ::backdrop and Escape-to-cancel for free (the native analog of SwiftUI's
// window-attached .alert and Android's AlertDialog). Only one dialog is active per
// window at a time (Apple's single windowDialog slot), so presenting replaces any
// current one.
//
// DialogButton shape (the JSON/host contract, mirroring WindowModal.swift's
// DialogButton): { title: String, role?: "default" | "cancel" | "destructive",
// actionID?: String }. role nil/"default" = a normal button; "cancel" = the
// escape/dismiss button (also what Escape and the backdrop map to); "destructive"
// = a red button. actionID nil = dismiss only. On any tap SwiftUI dismisses the
// dialog and then fires the button's action with viewID 0 / no context
// (WindowModalView.dialogButtons) - the web does the same.
//
// Divergences:
//   * confirmationDialog is rendered as the same <dialog> as alert on the web
//     (a desktop target, like macOS, where a confirmationDialog is a small dialog
//     rather than iOS's bottom action sheet); a marker class stacks its buttons
//     vertically (the action-sheet shape) where alert lays them in a trailing row.
//   * Escape / backdrop dismiss fires no action (Apple's dismissDialog), so a
//     dialog should always carry a cancel affordance; an empty button list gets a
//     default "Cancel" so the dialog is never un-dismissable.

const DEFAULT_ALERT_BUTTONS = [{ title: "OK", role: "cancel" }];
const ROLES = new Set(["default", "cancel", "destructive"]);

// Presents a dialog into `host` (the window root). Replaces any active dialog.
// Returns the <dialog> node.
export function presentDialog(host, spec, model, logger) {
    dismissActiveDialog(host); // single active dialog per window (Apple parity)

    const style = spec.style === "confirmationDialog" ? "confirmationDialog" : "alert";
    const buttons = normalizeButtons(spec.buttons, logger);

    const dialog = document.createElement("dialog");
    dialog.className = `aui-dialog aui-dialog-${style}`;

    if (spec.title) {
        const titleEl = document.createElement("strong");
        titleEl.className = "aui-dialog-title";
        titleEl.textContent = spec.title;
        dialog.appendChild(titleEl);
    }
    if (spec.message) {
        const messageEl = document.createElement("p");
        messageEl.className = "aui-dialog-message";
        messageEl.textContent = spec.message;
        dialog.appendChild(messageEl);
    }

    const row = document.createElement("div");
    row.className = "aui-dialog-buttons";
    for (const btn of buttons) {
        const role = ROLES.has(btn.role) ? btn.role : "default";
        const actionID = stringOrNull(btn.actionID) ?? stringOrNull(btn.actionId); // accept either spelling
        const b = document.createElement("button");
        b.className = `aui-dialog-button aui-dialog-button-${role}`;
        b.textContent = typeof btn.title === "string" ? btn.title : "";
        b.addEventListener("click", () => {
            dialog.close(); // SwiftUI dismisses after any tap (the close listener cleans up)
            if (actionID) model.dispatchAction(actionID, 0, 0, null); // viewID 0, no context (Apple parity)
        });
        row.appendChild(b);
    }
    dialog.appendChild(row);

    // Escape / backdrop -> dismiss with no action (Apple's dismissDialog). The
    // native 'cancel' event closes the dialog, which 'close' then cleans up.
    dialog.addEventListener("close", () => dialog.remove());

    host.appendChild(dialog);
    dialog.showModal();
    if (logger) logger.log(`present${style === "alert" ? "Alert" : "ConfirmationDialog"}: '${spec.title ?? ""}'`, "debug");
    return dialog;
}

// Dismisses the active dialog (if any) without firing an action - the host-API
// dismissDialog and the Escape/backdrop path share this. Mirrors
// ActionUIModel.dismissDialog.
export function dismissActiveDialog(host) {
    if (!host) return;
    const existing = host.querySelector("dialog.aui-dialog");
    if (existing) existing.close(); // triggers the 'close' listener -> remove
}

// An empty/absent button list gets a default so the dialog is dismissable; a
// non-empty list is used as given (the per-method defaults live in Window).
function normalizeButtons(buttons, logger) {
    if (Array.isArray(buttons) && buttons.length > 0) return buttons;
    if (Array.isArray(buttons) && buttons.length === 0) {
        if (logger) logger.log("Dialog presented with no buttons; adding a default Cancel", "warning");
    }
    return DEFAULT_ALERT_BUTTONS;
}

function stringOrNull(value) {
    return typeof value === "string" ? value : null;
}

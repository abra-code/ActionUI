// ActionUI.js — public API: Application and Window.
// Deliberately mirrors ActionUINodeJS/index.js (and stays shimmable to the
// window.ActionUI shape from ActionUIWebKitJSBridge.js).
//
//   import { Application, Window } from "./src/ActionUI.js";
//   const app = new Application({ name: "Demo" });
//   const win = await Window.fromURL("ui.json");
//   app.presentWindow(win, document.getElementById("root"));
//   app.action("save", (ctx) => { ... });
//   // no app.run() — the browser event loop is already running

import { ActionUIElement } from "./Common/ActionUIElement.js";
import { ActionUIModel } from "./Common/ActionUIModel.js";
import { buildElementView } from "./Common/ActionUIRegistry.js";
import { ConsoleLogger } from "./Common/ConsoleLogger.js";
import { PlatformFilter } from "./Common/PlatformFilter.js";
import { InsertPosition } from "./Common/ActionUIInsertion.js";
import { presentDialog, dismissActiveDialog } from "./Scenes/DialogHost.js";
import { presentModal, dismissActiveModal, ModalStyle } from "./Scenes/ModalHost.js";
import { presentToast, dismissActiveToast } from "./Scenes/ToastHost.js";
import { parseMenuBar, buildAppShell } from "./Scenes/MenuBar.js";
import { installLifecycleHooks } from "./Helpers/LifecycleHooks.js";

// Register all built-in view types (side-effect imports).
import "./Views/VStack.js";
import "./Views/HStack.js";
import "./Views/ZStack.js";
import "./Views/GeometryReader.js";
import "./Views/Spacer.js";
import "./Views/Divider.js";
import "./Views/Text.js";
import "./Views/Button.js";
import "./Views/TextField.js";
import "./Views/Toggle.js";
import "./Views/Image.js";
import "./Views/AsyncImage.js";
import "./Views/VideoPlayer.js";
import "./Views/WebView.js";
import "./Views/Canvas.js";
// Map's dependency-free default provider (an OSM embed + native-maps handoff). It
// registers "Map"; importing a richer provider module (providers/map-maplibre.js)
// after this overrides it (last registration wins) — the pluggable-provider model.
import "./Views/MapEmbed.js";
import "./Views/Label.js";
import "./Views/Slider.js";
import "./Views/Stepper.js";
import "./Views/SecureField.js";
import "./Views/Picker.js";
import "./Views/ProgressView.js";
import "./Views/DatePicker.js";
import "./Views/ColorPicker.js";
import "./Views/ScrollView.js";
import "./Views/ScrollViewReader.js";
import "./Views/LazyVStack.js";
import "./Views/LazyHStack.js";
import "./Views/Grid.js";
import "./Views/LazyVGrid.js";
import "./Views/LazyHGrid.js";
import "./Views/Form.js";
import "./Views/Section.js";
import "./Views/GroupBox.js";
import "./Views/LabeledContent.js";
import "./Views/DisclosureGroup.js";
import "./Views/TextEditor.js";
import "./Views/Gauge.js";
import "./Views/Rectangle.js";
import "./Views/RoundedRectangle.js";
import "./Views/Capsule.js";
import "./Views/Circle.js";
import "./Views/Ellipse.js";
import "./Views/Tab.js";
import "./Views/TabView.js";
import "./Views/Menu.js";
import "./Views/List.js";
import "./Views/Table.js";
import "./Views/NavigationSplitView.js";
import "./Views/NavigationLink.js";
import "./Views/NavigationStack.js";
import "./Views/LoadableView.js";
// Group-A batch (low effort, no new architecture): the structural/utility
// passthroughs and the external-content elements.
import "./Views/Group.js";
import "./Views/EmptyView.js";
import "./Views/Link.js";
import "./Views/ShareLink.js";
import "./Views/ContentUnavailableView.js";

// Re-export so hosts can `import { Window, InsertPosition, ModalStyle } from
// ".../ActionUI.js"` (mirrors the Node.js adapter exposing these alongside Window).
export { InsertPosition, ModalStyle };

// A UUID for the window/element key space. `crypto.randomUUID()` is the ideal source,
// but it is SECURE-CONTEXT-ONLY: it is `undefined` on a plain-http origin that is not
// localhost (e.g. the Android emulator's `http://10.0.2.2`, or a LAN IP), so calling it
// there throws and blanks the app. Fall back to a v4 UUID from `crypto.getRandomValues`
// (which IS available in insecure contexts) and finally `Math.random`. This id is an
// internal key, not a security token, so non-cryptographic randomness is acceptable.
function generateUUID() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
        return crypto.randomUUID();
    }
    const bytes = new Uint8Array(16);
    if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
        crypto.getRandomValues(bytes);
    } else {
        for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0"));
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10, 16).join("")}`;
}

export class ActionContext {
    constructor(actionID, windowUUID, viewID, viewPartID, context) {
        this.actionID = actionID;
        this.windowUUID = windowUUID;
        this.viewID = viewID;
        this.viewPartID = viewPartID;
        this.context = context; // element-specific payload (e.g. button title) or null
    }
}

export class Window {
    constructor(rootElement, uuid, logger) {
        this.uuid = uuid ?? generateUUID();
        this.logger = logger ?? new ConsoleLogger();
        this.rootElement = rootElement;
        this.model = new ActionUIModel(this.uuid, this.logger);
        this.rootNode = null; // built on present()
    }

    // `logger` is optional: a host (e.g. the demo's diagnostics panel) can pass
    // its own ActionUILogger to capture parse + runtime messages; it defaults to
    // a ConsoleLogger. The same instance is used for parsing and handed to the
    // Window, so every message flows through one sink.
    static fromJSON(json, uuid, logger = new ConsoleLogger()) {
        let raw;
        if (typeof json === "string") {
            try {
                raw = JSON.parse(json);
            } catch (error) {
                logger.log(`Invalid JSON: ${error.message}`, "error");
                throw new Error("ActionUI: failed to parse window JSON");
            }
        } else {
            raw = json;
        }
        // Resolve `<key>:<platform>` overrides for the web runtime (e.g.
        // "font:web") before building the tree, dropping other platforms' keys.
        const normalized = PlatformFilter.WEB.withLogger(logger).filter(raw);
        const root = ActionUIElement.fromObject(normalized, logger);
        if (!root) throw new Error("ActionUI: failed to parse window JSON");
        return new Window(root, uuid, logger);
    }

    static async fromURL(url, uuid, logger) {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`ActionUI: failed to load ${url}: ${response.status}`);
        return Window.fromJSON(await response.text(), uuid, logger);
    }

    present(container) {
        const ctx = {
            model: this.model,
            windowUUID: this.uuid,
            logger: this.logger,
        };
        ctx.build = (element) => buildElementView(element, ctx);
        this.rootNode = ctx.build(this.rootElement);
        this.rootNode.classList.add("aui-window");
        // Hand the render context to the model so the insertion API can render
        // inserted subtrees and query the live tree by id.
        this.model.setRenderContext(this.rootNode, ctx.build, this.rootElement.id);
        container.replaceChildren(this.rootNode);
        // Page-lifecycle action hooks declared on the document root
        // (onForeground/onBackground/onTerminateActionID:web). Re-installed on each
        // present(); the prior cleanup removes any stale listeners first.
        this._lifecycleCleanup?.();
        this._lifecycleCleanup = installLifecycleHooks(this.rootElement.properties, this.model, this.logger);
        return this;
    }

    // Tears the window down: runs the page-lifecycle cleanup, unmounts the root node,
    // and disposes the model (drops every binding/state/value/override + the render
    // context). The window can be re-presented afterwards with present(). Idempotent.
    // Application.closeWindow calls this and also drops the registry entry; a host
    // that presented a window directly (no Application) can call it itself.
    dismiss() {
        this._lifecycleCleanup?.();
        this._lifecycleCleanup = null;
        this.rootNode?.remove();
        this.rootNode = null;
        this.model.dispose();
        return this;
    }

    // Value bridge — same names as the Node.js adapter.
    getValue(viewID, viewPartID = 0)        { return this.model.getElementValue(viewID, viewPartID); }
    setValue(viewID, viewPartID = 0, value) { this.model.setElementValue(viewID, viewPartID, value); }

    getString(viewID, viewPartID = 0) { return String(this.getValue(viewID, viewPartID) ?? ""); }
    getBool(viewID, viewPartID = 0)   { return Boolean(this.getValue(viewID, viewPartID)); }
    getInt(viewID, viewPartID = 0)    { return Math.trunc(Number(this.getValue(viewID, viewPartID)) || 0); }
    getDouble(viewID, viewPartID = 0) { return Number(this.getValue(viewID, viewPartID)) || 0; }

    setString(viewID, viewPartID = 0, value) { this.setValue(viewID, viewPartID, String(value)); }
    setBool(viewID, viewPartID = 0, value)   { this.setValue(viewID, viewPartID, Boolean(value)); }
    setInt(viewID, viewPartID = 0, value)    { this.setValue(viewID, viewPartID, Math.trunc(value)); }
    setDouble(viewID, viewPartID = 0, value) { this.setValue(viewID, viewPartID, Number(value)); }

    // State bridge — named per-element states (e.g. DisclosureGroup's
    // "isExpanded"), same names as the Node.js adapter. The string-transport
    // variants (getStateString/setStateFromString) are a C-bridge concern and
    // have no web counterpart; values here are already JS values.
    getState(viewID, key)        { return this.model.getElementState(viewID, key); }
    setState(viewID, key, value) { this.model.setElementState(viewID, key, value); }

    // Property bridge — runtime mutation of a visual View property (same name as
    // the Swift/Kotlin setElementProperty). Web has no reactive re-render, so this
    // mutates the live node directly; it covers the host-driven visual properties
    // (opacity, hidden, cornerRadius, foregroundColor/Style, background, disabled,
    // help). See ActionUIModel.setElementProperty / ModifierResolver.applyElementProperty.
    setElementProperty(viewID, propertyName, value) {
        this.model.setElementProperty(viewID, propertyName, value);
    }

    // Rows bridge — the data backing collection elements (Table now; List's
    // itemType/template modes next). Rows live in the `content` state as a
    // [[String]] (the Apple states["content"] contract), so these are sugar over
    // the state bridge: a bound element (e.g. Table) re-renders on set/append/clear.
    getElementRows(viewID) {
        const rows = this.model.getElementState(viewID, "content");
        return Array.isArray(rows) ? rows : [];
    }
    setElementRows(viewID, rows)    { this.model.setElementState(viewID, "content", normalizeRows(rows)); }
    appendElementRows(viewID, rows) { this.setElementRows(viewID, this.getElementRows(viewID).concat(normalizeRows(rows))); }
    clearElementRows(viewID)        { this.setElementRows(viewID, []); }
    getElementColumnCount(viewID) {
        return this.getElementRows(viewID).reduce((max, row) => Math.max(max, Array.isArray(row) ? row.length : 0), 0);
    }

    // Selection bridge — programmatic row selection for Table and the data-driven
    // List modes, shimmable to the window.ActionUI shape (ActionUIWebKitJSBridge.js).
    // Selection is silent: like Apple, it does NOT fire the element's actionID, so
    // the host updates any status UI itself. selectElementRow takes a 0-based index
    // (out of range clears the selection) and returns the selected row's column
    // values, or null. selectElementRowWithContent selects the first row whose column
    // equals text (exact, case-sensitive); column is 0-based, -1 (default) matches
    // any column; it returns the 0-based matched index, or -1. clearElementSelection
    // deselects. Read the selection back with getString(viewID).
    selectElementRow(viewID, index) { return this.model.selectElementRow(viewID, index); }
    selectElementRowWithContent(viewID, text, column = -1) {
        return this.model.selectElementRowWithContent(viewID, text, column);
    }
    clearElementSelection(viewID) { this.model.clearElementSelection(viewID); }

    // Structural mutations — same names/signature as the Node.js adapter's Window.
    // `element`/`cells` accept a JS object/array or a JSON string; `container` may
    // be null to auto-derive the unique container of the right shape; `position`
    // is an InsertPosition (default APPEND), `positionParam` the index (AT) or
    // sibling viewID (BEFORE/AFTER). insertElement returns the new id; insertRow
    // returns the cell ids; all throw InsertError on a bad request.
    insertElement(parentID, element, container = null, position = InsertPosition.APPEND, positionParam = 0) {
        return this.model.insertElement(parentID, element, container, position, positionParam);
    }
    insertRow(parentID, cells, container = null, position = InsertPosition.APPEND, positionParam = 0) {
        return this.model.insertRow(parentID, cells, container, position, positionParam);
    }
    removeElement(viewID) { return this.model.removeElement(viewID); }

    // Window-level dialogs - same names/signature as the Node.js adapter's Window.
    // A dialog is pure data (title, message, buttons) shown as a native top-layer
    // <dialog>; see Scenes/DialogHost.js. `buttons` is an array of
    // { title, role?: "default"|"cancel"|"destructive", actionID? }. presentAlert
    // defaults to a single "OK" (cancel role); presentConfirmationDialog requires
    // its buttons (an empty/absent list falls back to a "Cancel" so it stays
    // dismissable). Only one dialog is active per window at a time.
    presentAlert(title, message = null, buttons = null) {
        this._presentDialog("alert", title, message, buttons ?? [{ title: "OK", role: "cancel" }]);
    }
    presentConfirmationDialog(title, message = null, buttons = null) {
        this._presentDialog("confirmationDialog", title, message, buttons ?? []);
    }
    dismissDialog() { dismissActiveDialog(this.rootNode); }

    // Window-level modal - same names/signature as the Node.js adapter's Window.
    // Loads a JSON sub-document (`description`: a JSON string or object) and
    // presents it over the window as a native <dialog> (sheet or fullScreenCover);
    // the modal's own controls bind into the window model (addressable by id) and
    // are removed on dismiss. The modal dismisses itself by routing an actionID the
    // host maps to dismissModal(), or via Escape/the backdrop. See Scenes/ModalHost.js.
    presentModal(description, format = "json", style = ModalStyle.SHEET, onDismissActionID = null) {
        if (!this.rootNode) {
            this.logger.log("presentModal: window not presented yet; call present() first", "error");
            return;
        }
        presentModal(this.rootNode, {
            data: typeof description === "string" ? description : JSON.stringify(description),
            format,
            style: style === ModalStyle.FULL_SCREEN_COVER ? "fullScreenCover" : "sheet",
            onDismissActionID,
        }, this.model, this.logger);
    }
    dismissModal() { dismissActiveModal(this.rootNode, this.model); }

    // Window-level toast (snackbar) - same names/signature as the Node.js adapter's
    // Window. A transient, auto-dismissing non-modal banner; if one is already visible
    // the new one is queued and shown after it dismisses. Pass `actionTitle` and
    // `actionId` TOGETHER to add one inline action button (e.g. "Undo") that fires
    // `actionId` (viewID 0, no context) and then dismisses; supplying only one yields a
    // message-only toast. Placement (top default, bottom on Android) is a CSS concern.
    // See Scenes/ToastHost.js.
    presentToast(message, duration = 4.0, actionTitle = null, actionId = null) {
        if (!this.rootNode) {
            this.logger.log("presentToast: window not presented yet; call present() first", "error");
            return;
        }
        const action = (actionTitle != null && actionId != null)
            ? { title: String(actionTitle), actionID: String(actionId) }
            : undefined;
        presentToast(this.rootNode, {
            message: message == null ? "" : String(message),
            duration,
            action,
        }, this.model, this.logger);
    }
    dismissToast() { dismissActiveToast(this.rootNode, this.model, this.logger); }

    _presentDialog(style, title, message, buttons) {
        if (!this.rootNode) {
            this.logger.log("presentDialog: window not presented yet; call present() first", "error");
            return;
        }
        presentDialog(this.rootNode, {
            style,
            title: title == null ? "" : String(title),
            message: message == null ? null : String(message),
            buttons,
        }, this.model, this.logger);
    }
}

// Coerces host-supplied rows to the [[String]] shape: each row an array of
// strings, each cell stringified. A non-array yields no rows; a bare value
// becomes a one-cell row.
function normalizeRows(rows) {
    if (!Array.isArray(rows)) return [];
    return rows.map((row) => (Array.isArray(row) ? row : [row]).map((cell) => String(cell ?? "")));
}

export class Application {
    constructor({ name } = {}) {
        this.name = name ?? "ActionUI";
        this.handlers = new Map(); // actionID -> handler
        this.defaultHandler = null;
        this.windows = new Map();  // uuid -> Window
        this.logger = new ConsoleLogger();
        this.menuBar = null;       // parsed MainMenu.json model (Scenes/MenuBar.js)
    }

    // Application menu bar (the array-root MainMenu.json). `menu` is a JSON string
    // or an already-parsed array. On web this is not a desktop menu strip: it
    // renders as a top app bar (hamburger + optional account menu) wrapping the
    // window - see Scenes/MenuBar.js. Call before presentWindow.
    setMenuBar(menu, logger = this.logger) {
        let raw = menu;
        if (typeof menu === "string") {
            try {
                raw = JSON.parse(menu);
            } catch (error) {
                logger.log(`Invalid menu bar JSON: ${error.message}`, "error");
                return this;
            }
        }
        this.menuBar = parseMenuBar(raw, logger);
        return this;
    }

    async setMenuBarFromURL(url, logger = this.logger) {
        const response = await fetch(url);
        if (!response.ok) {
            logger.log(`Failed to load menu bar ${url}: ${response.status}`, "error");
            return this;
        }
        return this.setMenuBar(await response.text(), logger);
    }

    // Presents a window into a DOM container and tracks it (by uuid) so the host can
    // drive and later close it. One Application can present several windows - multiple
    // independent in-document surfaces (own uuid + own model each), all sharing this
    // action registry; the dispatched ActionContext.windowUUID disambiguates which
    // surface fired. (That is the web's honest "multi-window": separate OS windows via
    // window.open run in a different realm and cannot be driven by reference - out of
    // scope, see Web_Porting_Notes.md.) `options.appShell` (default true) wraps the
    // window in the menu-bar app shell when one is set; auxiliary surfaces pass
    // `{ appShell: false }` so the shell stays on the primary window only.
    presentWindow(win, container, { appShell = true } = {}) {
        win.model.actionDispatcher = (actionID, windowUUID, viewID, viewPartID, context) => {
            const handler = this.handlers.get(actionID) ?? this.defaultHandler;
            if (handler) {
                handler(new ActionContext(actionID, windowUUID, viewID, viewPartID, context));
            } else {
                win.logger.log(`No handler for action "${actionID}"`, "info");
            }
        };
        this.windows.set(win.uuid, win);
        // With a menu bar, wrap the window in an app shell (top app bar + drawer +
        // account menu) and present into its stage; menu commands dispatch at the
        // app level (viewID 0). Without one (or when opted out), mount directly.
        if (this.menuBar && appShell) {
            const dispatch = (actionID) => win.model.dispatchAction(actionID, 0);
            const { shell, stage } = buildAppShell(this.menuBar, this.name, dispatch, win.logger);
            container.replaceChildren(shell);
            return win.present(stage);
        }
        return win.present(container);
    }

    // The presented window for a uuid (or undefined) - e.g. to recover the surface a
    // dispatched action came from via ActionContext.windowUUID.
    getWindow(uuid) { return this.windows.get(uuid); }

    // Every presented window, in presentation order.
    get windowList() { return Array.from(this.windows.values()); }

    // Closes a presented window (a Window or its uuid): tears it down (Window.dismiss
    // unmounts + disposes the model) and drops it from the registry. A window this
    // Application did not present is ignored. Returns true when one was closed.
    closeWindow(winOrUuid) {
        const uuid = typeof winOrUuid === "string" ? winOrUuid : winOrUuid?.uuid;
        const win = this.windows.get(uuid);
        if (!win) return false;
        win.dismiss();
        this.windows.delete(uuid);
        return true;
    }

    action(actionID, handler) { this.handlers.set(actionID, handler); return this; }
    registerHandler(actionID, handler) { return this.action(actionID, handler); }
    unregisterHandler(actionID) { this.handlers.delete(actionID); return this; }
    setDefaultHandler(handler) { this.defaultHandler = handler; return this; }

    // File panels. The native app.openPanel (ActionUINodeJS/index.js) returns an
    // array of filesystem PATHS synchronously. The web has neither: a picker yields
    // File objects (name + bytes), reading is async, and access is user-gesture
    // gated. So this returns a Promise<File[] | null> (null on cancel). The File
    // objects carry their bytes (file.text() / .arrayBuffer()), which is how the
    // host actually uploads. config mirrors the native call shape; keys with no web
    // analog are ignored: title, prompt, message, identifier, directory,
    // showsHiddenFiles, treatsFilePackagesAsDirectories, canCreateDirectories,
    // allowsOtherFileTypes.
    openPanel(config = {}) {
        return new Promise((resolve) => {
            const input = document.createElement("input");
            input.type = "file";
            input.style.display = "none";
            if (config.allowsMultiple) input.multiple = true;
            // Directory selection: only when directories are the sole target.
            if (config.canChooseDirectories === true && config.canChooseFiles === false) {
                input.webkitdirectory = true;
            }
            const accept = utTypesToAccept(config.allowedTypes);
            if (accept) input.accept = accept;

            let settled = false;
            const settle = (result) => {
                if (settled) return;
                settled = true;
                input.remove();
                resolve(result);
            };
            input.addEventListener("change", () => {
                const files = Array.from(input.files);
                settle(files.length > 0 ? files : null);
            });
            // Modern browsers fire "cancel" when the picker is dismissed.
            input.addEventListener("cancel", () => settle(null));

            document.body.appendChild(input);
            input.click();
        });
    }

    // savePanel is deferred on web: a download needs the content up front and the
    // File System Access save picker is Chromium-only, so there is no clean
    // universal "return a path to write to". Honest no-op so a shared host that
    // calls it degrades gracefully rather than throwing. See Web_Porting_Notes.md.
    savePanel(_config = {}) {
        this.logger.log("savePanel is not supported on web (deferred); see Web_Porting_Notes.md (File panels)", "warning");
        return null;
    }
}

// Map native allowedTypes (file extensions like "json" and UTType identifiers like
// "public.image") to an <input accept> string. Unknown UTTypes are skipped. Returns
// null when nothing maps (an unrestricted picker).
const UT_TYPE_MIME = {
    "public.image": "image/*",
    "public.movie": "video/*",
    "public.audio": "audio/*",
    "public.video": "video/*",
    "public.pdf": "application/pdf",
    "public.json": "application/json",
    "public.plain-text": "text/plain",
    "public.text": "text/plain",
    "public.utf8-plain-text": "text/plain",
    "public.html": "text/html",
};

function utTypesToAccept(allowedTypes) {
    if (!Array.isArray(allowedTypes) || allowedTypes.length === 0) return null;
    const tokens = [];
    for (const t of allowedTypes) {
        if (typeof t !== "string" || t.length === 0) continue;
        if (t.includes(".")) {
            // A UTType identifier (e.g. "public.image"); map to a MIME, else skip.
            const mime = UT_TYPE_MIME[t];
            if (mime) tokens.push(mime);
        } else {
            // A bare file extension (e.g. "json", "txt") -> ".json".
            tokens.push("." + t);
        }
    }
    return tokens.length > 0 ? Array.from(new Set(tokens)).join(",") : null;
}

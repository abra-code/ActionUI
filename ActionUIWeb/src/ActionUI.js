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

// Register all built-in view types (side-effect imports).
import "./Views/VStack.js";
import "./Views/HStack.js";
import "./Views/ZStack.js";
import "./Views/Spacer.js";
import "./Views/Divider.js";
import "./Views/Text.js";
import "./Views/Button.js";
import "./Views/TextField.js";
import "./Views/Toggle.js";
import "./Views/Image.js";
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
import "./Views/LoadableView.js";

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
        this.uuid = uuid ?? crypto.randomUUID();
        this.logger = logger ?? new ConsoleLogger();
        this.rootElement = rootElement;
        this.model = new ActionUIModel(this.uuid, this.logger);
        this.rootNode = null; // built on present()
    }

    static fromJSON(json, uuid) {
        const logger = new ConsoleLogger();
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

    static async fromURL(url, uuid) {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`ActionUI: failed to load ${url}: ${response.status}`);
        return Window.fromJSON(await response.text(), uuid);
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
        container.replaceChildren(this.rootNode);
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
    }

    presentWindow(win, container) {
        win.model.actionDispatcher = (actionID, windowUUID, viewID, viewPartID, context) => {
            const handler = this.handlers.get(actionID) ?? this.defaultHandler;
            if (handler) {
                handler(new ActionContext(actionID, windowUUID, viewID, viewPartID, context));
            } else {
                win.logger.log(`No handler for action "${actionID}"`, "info");
            }
        };
        this.windows.set(win.uuid, win);
        return win.present(container);
    }

    action(actionID, handler) { this.handlers.set(actionID, handler); return this; }
    registerHandler(actionID, handler) { return this.action(actionID, handler); }
    unregisterHandler(actionID) { this.handlers.delete(actionID); return this; }
    setDefaultHandler(handler) { this.defaultHandler = handler; return this; }
}

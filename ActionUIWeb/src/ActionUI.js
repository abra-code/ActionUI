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
import "./Views/LazyVStack.js";
import "./Views/LazyHStack.js";

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

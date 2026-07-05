'use strict';
/**
 * actionui — high-level JavaScript API for ActionUI.
 *
 * Mirrors the structure of actionui.py (Python adapter).
 * All heavy lifting (type conversion, JSON serialisation) is done in the
 * native layer (actionui_node.m).  This file provides a JS-idiomatic wrapper.
 */

const _actionui = require('node-gyp-build')(__dirname);
const { randomUUID } = require('crypto');
const path = require('path');
const fs = require('fs');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const LogLevel = Object.freeze({
    ERROR:   _actionui.LOG_ERROR,
    WARNING: _actionui.LOG_WARNING,
    INFO:    _actionui.LOG_INFO,
    DEBUG:   _actionui.LOG_DEBUG,
    VERBOSE: _actionui.LOG_VERBOSE,
});

const ModalStyle = Object.freeze({
    SHEET:              'sheet',
    FULL_SCREEN_COVER:  'fullScreenCover',
});

const ButtonRole = Object.freeze({
    DEFAULT:     'default',
    CANCEL:      'cancel',
    DESTRUCTIVE: 'destructive',
});

const InsertPosition = Object.freeze({
    APPEND:  0,   // Add after the last existing child
    PREPEND: 1,   // Add before the first existing child
    AT:      2,   // Insert at a specific index      (positionParam = index)
    BEFORE:  3,   // Insert before a sibling         (positionParam = sibling viewID; flat containers only)
    AFTER:   4,   // Insert after a sibling          (positionParam = sibling viewID; flat containers only)
});

// ---------------------------------------------------------------------------
// ActionContext — passed to action handlers
// ---------------------------------------------------------------------------

class ActionContext {
    constructor(actionId, windowUuid, viewId, viewPartId, contextJSON) {
        this.actionId    = actionId;
        this.windowUuid  = windowUuid;
        this.viewId      = viewId;
        this.viewPartId  = viewPartId;
        this.context     = null;
        if (contextJSON != null) {
            try { this.context = JSON.parse(contextJSON); }
            catch { this.context = contextJSON; }
        }
    }
}

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

class Window {
    constructor(uuid) {
        this.uuid = uuid || randomUUID();
        this._viewPtr = null;
    }

    static fromFile(filePath, uuid, isContentView = true) {
        const win = new Window(uuid);
        let url = filePath;
        if (!url.startsWith('file://')) {
            url = 'file://' + path.resolve(filePath);
        }
        try {
            win._viewPtr = _actionui.loadHostingController(url, win.uuid, isContentView);
        } catch (e) {
            win._viewPtr = null;
        }
        return win;
    }

    static fromURL(url, uuid, isContentView = true) {
        const win = new Window(uuid);
        try {
            win._viewPtr = _actionui.loadHostingController(url, win.uuid, isContentView);
        } catch (e) {
            win._viewPtr = null;
        }
        return win;
    }

    // Content size limits of the loaded root element:
    // { minWidth, minHeight, maxWidth, maxHeight }. The minimum is what the
    // SwiftUI content reports for a zero size proposal, the maximum for an
    // infinite one; flexible axes report a very large maximum, and a fixed
    // root frame reports min == max (make the hosting window
    // non-user-resizable in that case). Measured on the bare root element,
    // bypassing the window-level modal/toast wrapper.
    // Returns null if the window has no loaded description.
    contentSizeLimits() {
        try {
            return _actionui.getContentSizeLimits(this.uuid);
        } catch (e) {
            return null;
        }
    }

    // Type-specific setters
    setInt(viewId, partId = 0, value)    { _actionui.setIntValue(this.uuid, viewId, partId, value); }
    setDouble(viewId, partId = 0, value) { _actionui.setDoubleValue(this.uuid, viewId, partId, value); }
    setBool(viewId, partId = 0, value)   { _actionui.setBoolValue(this.uuid, viewId, partId, value); }
    setString(viewId, partId = 0, value) { _actionui.setStringValue(this.uuid, viewId, partId, value); }

    // Type-specific getters
    getInt(viewId, partId = 0)    { return _actionui.getIntValue(this.uuid, viewId, partId); }
    getDouble(viewId, partId = 0) { return _actionui.getDoubleValue(this.uuid, viewId, partId); }
    getBool(viewId, partId = 0)   { return _actionui.getBoolValue(this.uuid, viewId, partId); }
    getString(viewId, partId = 0) { return _actionui.getStringValue(this.uuid, viewId, partId); }

    // Generic value access (JSON round-trip)
    setValue(viewId, partId = 0, value) {
        if (typeof value === 'boolean') {
            _actionui.setBoolValue(this.uuid, viewId, partId, value);
        } else if (typeof value === 'number') {
            if (Number.isInteger(value)) {
                _actionui.setIntValue(this.uuid, viewId, partId, value);
            } else {
                _actionui.setDoubleValue(this.uuid, viewId, partId, value);
            }
        } else if (typeof value === 'string') {
            _actionui.setStringValue(this.uuid, viewId, partId, value);
        } else {
            _actionui.setValueFromJSON(this.uuid, viewId, partId, JSON.stringify(value));
        }
    }

    getValue(viewId, partId = 0) {
        const raw = _actionui.getValueAsJSON(this.uuid, viewId, partId);
        if (raw == null) return null;
        try { return JSON.parse(raw); } catch { return raw; }
    }

    // String value access with optional content-type
    // contentType: "plain" (default), "markdown", "html", "rtf", or "json"
    setValueFromString(viewId, partId = 0, value, contentType = null) {
        return _actionui.setValueFromString(this.uuid, viewId, partId, value, contentType);
    }

    getValueAsString(viewId, partId = 0, contentType = null) {
        return _actionui.getValueAsString(this.uuid, viewId, partId, contentType);
    }

    // Element column count
    getColumnCount(viewId) { return _actionui.getElementColumnCount(this.uuid, viewId); }

    // Element rows
    getRows(viewId) {
        const raw = _actionui.getElementRowsJSON(this.uuid, viewId);
        return raw != null ? JSON.parse(raw) : null;
    }
    setRows(viewId, rows)    { _actionui.setElementRowsJSON(this.uuid, viewId, JSON.stringify(rows)); }
    appendRows(viewId, rows) { _actionui.appendElementRowsJSON(this.uuid, viewId, JSON.stringify(rows)); }
    clearRows(viewId)        { _actionui.clearElementRows(this.uuid, viewId); }

    // Element selection (Table / List) — programmatic, fires no actionID
    // selectRow: 0-based index; out-of-range clears the selection. Returns true if a row was selected.
    selectRow(viewId, index) { return _actionui.selectElementRowByIndex(this.uuid, viewId, index); }
    // selectRowWithContent: select the first row whose column equals text (exact). column is 0-based;
    // pass null/undefined or a negative value to match any column. Returns the 0-based index, or -1.
    selectRowWithContent(viewId, text, column = -1) {
        return _actionui.selectElementRowWithContent(this.uuid, viewId, text, column == null ? -1 : column);
    }
    clearSelection(viewId)   { _actionui.clearElementSelection(this.uuid, viewId); }

    // Element properties
    getProperty(viewId, name) {
        const raw = _actionui.getElementPropertyJSON(this.uuid, viewId, name);
        return raw != null ? JSON.parse(raw) : null;
    }
    setProperty(viewId, name, value) {
        _actionui.setElementPropertyJSON(this.uuid, viewId, name, JSON.stringify(value));
    }

    // Element config: the element's NON-VISUAL operational settings (the document's
    // "config" block, sibling of properties) - what a complex element DOES (wire
    // protocol, transports, data sources). Stored verbatim; the element checks what it
    // reads. Canonical use: load a static document, then inject runtime/session-specific
    // settings (e.g. a resolved transport) before showing it.
    getConfig(viewId, key) {
        const raw = _actionui.getElementConfigJSON(this.uuid, viewId, key);
        return raw != null ? JSON.parse(raw) : null;
    }
    setConfig(viewId, key, value) {
        _actionui.setElementConfigJSON(this.uuid, viewId, key, JSON.stringify(value));
    }

    // Element state
    getState(viewId, key) {
        const raw = _actionui.getElementStateJSON(this.uuid, viewId, key);
        return raw != null ? JSON.parse(raw) : null;
    }
    getStateString(viewId, key) { return _actionui.getElementStateString(this.uuid, viewId, key); }
    setState(viewId, key, value) {
        _actionui.setElementStateJSON(this.uuid, viewId, key, JSON.stringify(value));
    }
    setStateFromString(viewId, key, value) {
        _actionui.setElementStateFromString(this.uuid, viewId, key, value);
    }

    // Element info: { [viewId]: typeName }
    getElementInfo() {
        const raw = _actionui.getElementInfoJSON(this.uuid);
        if (raw == null) return {};
        const parsed = JSON.parse(raw);
        const result = {};
        for (const [k, v] of Object.entries(parsed)) result[Number(k)] = v;
        return result;
    }

    // Runtime structural mutations

    /**
     * Insert a new element into a flat container at runtime.
     * @param {number} parentId - View ID of the container.
     * @param {object|string} element - View descriptor dict or JSON string.
     * @param {string|null} container - Container name, or null to auto-derive.
     * @param {number} position - 0=append, 1=prepend, 2=at, 3=before, 4=after. Use InsertPosition enum
     * @param {number} positionParam - Index or sibling viewID for positions 2–4.
     * @returns {number} Newly assigned view ID, or -1 on failure.
     */
    insertElement(parentId, element, container = null, position = InsertPosition.APPEND, positionParam = 0) {
        const json = typeof element === 'string' ? element : JSON.stringify(element);
        return _actionui.insertElement(this.uuid, parentId, json, container, position, positionParam);
    }

    /**
     * Insert a new row of cells into a Grid rows container at runtime.
     * @param {number} parentId - View ID of the Grid container.
     * @param {Array<object>|string} cells - Array of cell dicts or JSON string.
     * @param {string|null} container - Container name, or null to auto-derive.
     * @param {number} position - 0=append, 1=prepend, 2=at. Use InsertPosition enum
     * @param {number} positionIndex - Row index for position 2 (at).
     * @returns {number[]|null} Array of newly assigned cell view IDs, or null on failure.
     */
    insertRow(parentId, cells, container = null, position = InsertPosition.APPEND, positionIndex = 0) {
        const json = typeof cells === 'string' ? cells : JSON.stringify(cells);
        return _actionui.insertRow(this.uuid, parentId, json, container, position, positionIndex);
    }

    /**
     * Remove a view (and all descendants) from its parent container at runtime.
     * @param {number} viewId - ID of the view to remove.
     * @returns {boolean} true on success.
     */
    removeElement(viewId) {
        return _actionui.removeElement(this.uuid, viewId);
    }

    // Modal presentation
    presentModal(jsonString, format = 'json', style = ModalStyle.SHEET, onDismissActionId = null) {
        _actionui.presentModal(this.uuid, jsonString, format, style, onDismissActionId);
    }
    dismissModal() { _actionui.dismissModal(this.uuid); }

    presentAlert(title, message = null, buttons = null) {
        const buttonsJSON = buttons != null ? JSON.stringify(buttons.map(_buttonToDict)) : null;
        _actionui.presentAlert(this.uuid, title, message, buttonsJSON);
    }

    presentConfirmationDialog(title, message = null, buttons = null) {
        const buttonsJSON = buttons != null ? JSON.stringify(buttons.map(_buttonToDict)) : '[]';
        _actionui.presentConfirmationDialog(this.uuid, title, message, buttonsJSON);
    }

    dismissDialog() { _actionui.dismissDialog(this.uuid); }

    /**
     * Present a transient, auto-dismissing toast (snackbar) pinned above the
     * window content. If a toast is already visible the new one is queued and
     * shown after the current dismisses.
     * @param {string} message - The toast text.
     * @param {number} [duration=4.0] - Seconds before auto-dismiss.
     * @param {string|null} [actionTitle=null] - Optional inline action button title (e.g. "Undo"); pass together with actionId.
     * @param {string|null} [actionId=null] - Optional actionID fired when the inline action button is tapped.
     */
    presentToast(message, duration = 4.0, actionTitle = null, actionId = null) {
        _actionui.presentToast(this.uuid, message, duration, actionTitle, actionId);
    }

    /** Dismiss the current toast, showing the next queued one if any. */
    dismissToast() { _actionui.dismissToast(this.uuid); }

    get viewPtr() { return this._viewPtr; }
}

function _buttonToDict(btn) {
    const d = { title: btn.title };
    if (btn.role && btn.role !== ButtonRole.DEFAULT) d.role = btn.role;
    if (btn.actionId) d.actionID = btn.actionId;
    return d;
}

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

let _appInstance = null;

class Application {
    constructor({ name, icon } = {}) {
        if (_appInstance != null) throw new Error('Only one Application instance can exist');
        _appInstance = this;

        this._actionHandlers = new Map();
        this._defaultHandler = null;
        this._windows        = new Map();   // uuid → Window

        if (name != null) {
        	_actionui.appSetName(name);
		}
		
        if (icon != null) {
            _actionui.appSetIcon(path.resolve(icon));
        } else {
            const defaultIcon = path.join(__dirname, 'actionui-app-icon.icns');
            if (fs.existsSync(defaultIcon)) _actionui.appSetIcon(defaultIcon);
        }

        // Route all actions through a single default bridge; per-action
        // registration still calls actionUIRegisterActionHandler so ActionUI's
        // internal routing knows which IDs are claimed.
        _actionui.setDefaultActionHandler(this._actionBridge.bind(this));
    }

    static instance() { return _appInstance; }

    // Internal action bridge — receives raw params from the native layer
    _actionBridge(actionId, windowUuid, viewId, viewPartId, contextJSON) {
        const ctx = new ActionContext(actionId, windowUuid, viewId, viewPartId, contextJSON);
        const handler = this._actionHandlers.get(actionId) ?? this._defaultHandler;
        if (handler) {
            try { handler(ctx); }
            catch (e) { console.error(`Error in action handler '${actionId}':`, e); }
        } else {
            console.warn(`No handler registered for action: ${actionId}`);
        }
    }

    // Register action handler (chainable decorator-style: app.action('id', fn))
    action(actionId, fn) {
        this.registerHandler(actionId, fn);
        return this;
    }

    registerHandler(actionId, fn) {
        this._actionHandlers.set(actionId, fn);
        _actionui.registerActionHandler(actionId, this._actionBridge.bind(this));
    }

    unregisterHandler(actionId) {
        this._actionHandlers.delete(actionId);
        _actionui.unregisterActionHandler(actionId);
    }

    setDefaultHandler(fn) {
        this._defaultHandler = fn;
    }

    // App lifecycle
    onWillFinishLaunching(fn) { _actionui.appSetWillFinishLaunching(fn); return this; }
    onDidFinishLaunching(fn)  { _actionui.appSetDidFinishLaunching(fn);  return this; }
    onWillBecomeActive(fn)    { _actionui.appSetWillBecomeActive(fn);    return this; }
    onDidBecomeActive(fn)     { _actionui.appSetDidBecomeActive(fn);     return this; }
    onWillResignActive(fn)    { _actionui.appSetWillResignActive(fn);    return this; }
    onDidResignActive(fn)     { _actionui.appSetDidResignActive(fn);     return this; }
    onWillTerminate(fn)       { _actionui.appSetWillTerminate(fn);       return this; }
    onShouldTerminate(fn)     { _actionui.appSetShouldTerminate(fn);     return this; }

    onWindowWillClose(fn) {
        _actionui.appSetWindowWillClose((uuid) => {
            const window = this._windows.get(uuid) ?? new Window(uuid);
            this._windows.delete(uuid);
            try { fn(window); } catch (e) { console.error('Error in windowWillClose:', e); }
        });
        return this;
    }

    onWindowWillPresent(fn) {
        _actionui.appSetWindowWillPresent((uuid) => {
            const window = this._windows.get(uuid) ?? new Window(uuid);
            try { fn(window); } catch (e) { console.error('Error in windowWillPresent:', e); }
        });
        return this;
    }

    // App control
    run() { _actionui.appRun(); }
    terminate() { _actionui.appTerminate(); }

    loadAndPresentWindow(url, uuid, title) {
        if (uuid == null) uuid = randomUUID();
        if (!url.startsWith('file://') && !url.startsWith('http://') && !url.startsWith('https://')) {
            url = 'file://' + path.resolve(url);
        }
        const window = new Window(uuid);
        this._windows.set(uuid, window);
        _actionui.appLoadAndPresentWindow(url, uuid, title ?? null);
        return window;
    }

    closeWindow(uuid) { _actionui.appCloseWindow(uuid); }

    loadMenuBar(source) {
        if (source == null) { _actionui.appLoadMenuBar(); return; }
        let json = source;
        if (!source.trimStart().startsWith('[')) {
            const fullPath = path.resolve(source);
            if (fs.existsSync(fullPath)) json = fs.readFileSync(fullPath, 'utf8');
        }
        _actionui.appLoadMenuBar(json);
    }

    openPanel({
        title, prompt, message, identifier,
        allowedTypes, allowsMultiple = false,
        canChooseFiles = true, canChooseDirectories = false,
        directory, showsHiddenFiles = false,
        treatsFilePackagesAsDirectories = false,
        canCreateDirectories = true, allowsOtherFileTypes = false,
    } = {}) {
        const cfg = _buildPanelConfig({ title, prompt, message, identifier, allowedTypes,
            directory, showsHiddenFiles, treatsFilePackagesAsDirectories,
            canCreateDirectories, allowsOtherFileTypes });
        if (allowsMultiple)       cfg.allowsMultipleSelection = true;
        if (!canChooseFiles)      cfg.canChooseFiles = false;
        if (canChooseDirectories) cfg.canChooseDirectories = true;
        const raw = _actionui.appRunOpenPanel(Object.keys(cfg).length ? JSON.stringify(cfg) : null);
        return raw != null ? JSON.parse(raw) : null;
    }

    savePanel({
        title, prompt, message, identifier,
        allowedTypes, filename, directory,
        showsHiddenFiles = false, treatsFilePackagesAsDirectories = false,
        canCreateDirectories = true, allowsOtherFileTypes = false,
    } = {}) {
        const cfg = _buildPanelConfig({ title, prompt, message, identifier, allowedTypes,
            directory, showsHiddenFiles, treatsFilePackagesAsDirectories,
            canCreateDirectories, allowsOtherFileTypes });
        if (filename != null) cfg.nameFieldStringValue = filename;
        return _actionui.appRunSavePanel(Object.keys(cfg).length ? JSON.stringify(cfg) : null);
    }

    alert({ title, message, style = 'informational', buttons } = {}) {
        const cfg = {};
        if (title   != null) cfg.title   = title;
        if (message != null) cfg.message = message;
        if (style   !== 'informational') cfg.style = style;
        if (buttons != null) cfg.buttons = buttons;
        return _actionui.appRunAlert(Object.keys(cfg).length ? JSON.stringify(cfg) : null);
    }
}

function _buildPanelConfig({ title, prompt, message, identifier, allowedTypes,
    directory, showsHiddenFiles, treatsFilePackagesAsDirectories,
    canCreateDirectories, allowsOtherFileTypes }) {
    const cfg = {};
    if (title      != null) cfg.title      = title;
    if (prompt     != null) cfg.prompt     = prompt;
    if (message    != null) cfg.message    = message;
    if (identifier != null) cfg.identifier = identifier;
    if (allowedTypes != null) cfg.allowedContentTypes = allowedTypes;
    if (directory  != null) cfg.directoryURL = directory;
    if (showsHiddenFiles) cfg.showsHiddenFiles = true;
    if (treatsFilePackagesAsDirectories) cfg.treatsFilePackagesAsDirectories = true;
    if (!canCreateDirectories) cfg.canCreateDirectories = false;
    if (allowsOtherFileTypes) cfg.allowsOtherFileTypes = true;
    return cfg;
}

// ---------------------------------------------------------------------------
// Module-level convenience functions
// ---------------------------------------------------------------------------

function getVersion()   { return _actionui.getVersion() ?? 'unknown'; }
function getLastError() { return _actionui.getLastError(); }
function clearError()   { _actionui.clearError(); }

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
    Application,
    Window,
    ActionContext,
    LogLevel,
    ModalStyle,
    ButtonRole,
    InsertPosition,
    getVersion,
    getLastError,
    clearError,
    // Expose raw native module for advanced use
    _native: _actionui,
};

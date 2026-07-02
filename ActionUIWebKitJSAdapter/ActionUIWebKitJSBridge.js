// ActionUIWebKitJSBridge.js
(function() {
    // Timestamp function
    window.getTimestamp = function() {
        return new Date().toISOString();
    };
    
    // Retain test functions for continuity
    window.testFromJS = function() {
        window.webkit.messageHandlers.actionUI.postMessage({method: 'testFromJS'});
    };
    window.testFromNative = function() {
        return 'Test from JS to Native';
    };
    
    // ActionUI API implementation
    window.ActionUI = {
        // Store logger function
        setLogger: function(loggerFunction) {
            window.actionUI_logger = loggerFunction;
        },
        
        // Store action handlers
        actionHandlers: {},
        defaultActionHandler: null,
        
        // Set element value
        setElementValue: function(windowUUID, viewID, viewPartID = 0, value) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'setElementValue',
                args: [windowUUID, viewID, viewPartID, value]
            });
        },
        
        // Set element value from string
        setElementValueFromString: function(windowUUID, viewID, viewPartID = 0, value, contentType = null) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'setElementValueFromString',
                args: [windowUUID, viewID, viewPartID, value, contentType]
            });
        },

        // Get element value (async)
        getElementValue: function(windowUUID, viewID, viewPartID = 0) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'getElementValue',
                    id: id,
                    args: [windowUUID, viewID, viewPartID]
                });
            });
        },
        
        // Get element value as string (async)
        getElementValueAsString: function(windowUUID, viewID, viewPartID = 0, contentType = null) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'getElementValueAsString',
                    id: id,
                    args: [windowUUID, viewID, viewPartID, contentType]
                });
            });
        },

        // Select a Table/List row by 0-based index (async; resolves to the selected row's
        // values, or null when the index is out of range / the view is not a Table/List).
        selectElementRow: function(windowUUID, viewID, index) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'selectElementRow',
                    id: id,
                    args: [windowUUID, viewID, index]
                });
            });
        },

        // Select the first Table/List row whose column matches text (async; resolves to the
        // 0-based row index, or -1 if no match). column is 0-based; pass -1 to match any column.
        selectElementRowWithContent: function(windowUUID, viewID, text, column = -1) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'selectElementRowWithContent',
                    id: id,
                    args: [windowUUID, viewID, text, column]
                });
            });
        },

        // Clear the Table/List selection (fire-and-forget)
        clearElementSelection: function(windowUUID, viewID) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'clearElementSelection',
                args: [windowUUID, viewID]
            });
        },

        // Get a single state value for a view (async; resolves to the value or null)
        getElementState: function(windowUUID, viewID, key) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'getElementState',
                    id: id,
                    args: [windowUUID, viewID, key]
                });
            });
        },

        // Get a single state value as a string (async; resolves to the string or '')
        getElementStateAsString: function(windowUUID, viewID, key) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'getElementStateAsString',
                    id: id,
                    args: [windowUUID, viewID, key]
                });
            });
        },

        // Set a single state value (fire-and-forget). Rejected natively if the new value's
        // type differs from the existing value's type for that key.
        setElementState: function(windowUUID, viewID, key, value) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'setElementState',
                args: [windowUUID, viewID, key, value]
            });
        },

        // Set a single state value by parsing a string into the existing value's type (fire-and-forget)
        setElementStateFromString: function(windowUUID, viewID, key, value) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'setElementStateFromString',
                args: [windowUUID, viewID, key, value]
            });
        },

        // Get a NON-VISUAL config value for a view element by key (async; resolves to the
        // value or null). Config is the element's operational settings block (the
        // document's "config" dictionary, sibling of "properties").
        getElementConfig: function(windowUUID, viewID, key) {
            return new Promise(function(resolve, reject) {
                const id = Math.random().toString(36).substring(2);
                window.addEventListener('message', function handler(event) {
                    if (event.data.id === id) {
                        window.removeEventListener('message', handler);
                        resolve(event.data.result);
                    }
                });
                window.webkit.messageHandlers.actionUI.postMessage({
                    method: 'getElementConfig',
                    id: id,
                    args: [windowUUID, viewID, key]
                });
            });
        },

        // Set a NON-VISUAL config value for a view element by key (fire-and-forget).
        // Stored verbatim; the element's buildView is the one consumer and checks what
        // it reads. Canonical use: inject runtime/session-specific settings into a
        // static document between loading it and showing it.
        setElementConfig: function(windowUUID, viewID, key, value) {
            window.webkit.messageHandlers.actionUI.postMessage({
                method: 'setElementConfig',
                args: [windowUUID, viewID, key, value]
            });
        },

        // Register action handler
        registerActionHandler: function(actionID, handlerFunction) {
            window.ActionUI.actionHandlers[actionID] = handlerFunction;
        },
        
        // Unregister action handler
        unregisterActionHandler: function(actionID) {
            delete window.ActionUI.actionHandlers[actionID];
        },
        
        // Set default action handler
        setDefaultActionHandler: function(handlerFunction) {
            window.ActionUI.defaultActionHandler = handlerFunction;
        },
        
        // Remove default action handler
        removeDefaultActionHandler: function() {
            window.ActionUI.defaultActionHandler = null;
        }
    };
    
    // Dispatch action to registered handler or default
    window.actionUIDispatch = function(type, actionID, args) {
        if (type === 'action') {
            const handler = window.ActionUI.actionHandlers[actionID] || window.ActionUI.defaultActionHandler;
            if (handler) {
                handler(actionID, args.windowUUID, args.viewID, args.viewPartID, args.context);
            }
        }
    };
    
    // Redirect console.log to native
    console.log = function(message) {
        window.webkit.messageHandlers.consoleLog.postMessage({ message: String(message) });
    };
    
    // Log bridge injection with timestamp
    console.log('[' + window.getTimestamp() + '] Bridge: Injected ActionUI bridge');
    
    return 'injected';
})();

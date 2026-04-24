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

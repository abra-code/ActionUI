// BusinessLogic.js
try {
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Script started');
    
    // Check if ActionUI is available
    if (typeof ActionUI === 'undefined') {
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: ActionUI not yet available');
        throw new Error('ActionUI not defined');
    }
    
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: ActionUI available');
    
    // Set logger
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Setting logger');
    ActionUI.setLogger(function(message, level) {
        const logLevels = [ "error", "warning", "info", "debug", "verbose"];
        let levelString;
        //level is 1-based, values in <1-5> range
        if ((level >= 1) && (level <= 5)) {
            levelString = logLevels[level-1];
        } else {
            levelString = "unknown"
        }
        console.log('[' + new Date().toISOString() + '] [ActionUI][' + levelString + '] ' + message);
    });
    
    // Test logger
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Logger initialized');
    
    // Call testFromJS
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Calling testFromJS');
    window.testFromJS();
    
    // Register action handler for Button (action.handle)
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Registering action.handle');
    ActionUI.registerActionHandler("action.handle", function(actionID, windowUUID, viewID, viewPartID, context) {
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Button action: ' + actionID + ', Window: ' + windowUUID + ', ViewID: ' + viewID + ', Part: ' + viewPartID + ', Context: ' + JSON.stringify(context));
        // Set TextField value (ID 3)
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Setting TextField value');
        ActionUI.setElementValue(windowUUID, 3, "Button clicked!", 0);
    });
    
    // Register action handler for TextField submission (text.submit)
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Registering text.submit');
    ActionUI.registerActionHandler("text.submit", function(actionID, windowUUID, viewID, viewPartID, context) {
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: TextField submitted: ' + actionID + ', Window: ' + windowUUID + ', ViewID: ' + viewID + ', Part: ' + viewPartID + ', Context: ' + JSON.stringify(context));
        // Get current TextField value
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Getting TextField value');
        ActionUI.getElementValue(windowUUID, 3, 0).then(value => {
            console.log('[' + new Date().toISOString() + '] BusinessLogic.js: TextField value: ' + value);
        }).catch(err => {
            console.error('[' + new Date().toISOString() + '] BusinessLogic.js: Error getting TextField value: ' + err);
        });
    });
    
    // Set initial TextField value (ID 3)
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Setting initial TextField value');
    ActionUI.setElementValue("window-12345", 3, "Initial text", 0);
    
    // Test getting TextField value
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Getting initial TextField value');
    ActionUI.getElementValue("window-12345", 3, 0).then(value => {
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Initial TextField value: ' + value);
    }).catch(err => {
        console.error('[' + new Date().toISOString() + '] BusinessLogic.js: Error getting initial TextField value: ' + err);
    });
    
    // Set default action handler
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Setting default action handler');
    ActionUI.setDefaultActionHandler(function(actionID, windowUUID, viewID, viewPartID, context) {
        console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Default action: ' + actionID + ', Window: ' + windowUUID + ', ViewID: ' + viewID + ', Part: ' + viewPartID + ', Context: ' + JSON.stringify(context));
    });
    
    // Log script completion
    console.log('[' + new Date().toISOString() + '] BusinessLogic.js: Script completed');
} catch (err) {
    console.error('[' + new Date().toISOString() + '] BusinessLogic.js: Fatal error: ' + err);
}

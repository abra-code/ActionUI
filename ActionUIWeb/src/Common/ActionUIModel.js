// ActionUIModel.js — per-window value store, DOM bindings, action routing.
// Web analog of ActionUI/Common/ActionUIModel.swift (PoC subset).
//
// Instead of a virtual DOM, each value-bearing rendered view registers a
// binding record { getValue, setValue } keyed by viewID. Programmatic
// setElementValue calls update the DOM directly through the binding; reads go
// through the binding so they always reflect live UI state.
//
// Element **states** (the Apple ViewModel.states dictionary — named keys like
// DisclosureGroup's "isExpanded", as opposed to the single element value) work
// the same way: a state-bearing view registers a { getState(key),
// setState(key, value) } record, with a per-view key/value map as the fallback
// for unbound keys.

export class ActionUIModel {
    constructor(windowUUID, logger) {
        this.windowUUID = windowUUID;
        this.logger = logger;
        this.values = new Map();        // viewID -> last known value (fallback when unbound)
        this.bindings = new Map();      // viewID -> { getValue(), setValue(value) }
        this.states = new Map();        // viewID -> { key: value } (fallback when unbound)
        this.stateBindings = new Map(); // viewID -> { getState(key), setState(key, value) }
        this.actionDispatcher = null;   // set by Application
    }

    seedValue(viewID, value) {
        this.values.set(viewID, value);
    }

    bind(viewID, binding) {
        this.bindings.set(viewID, binding);
    }

    seedStates(viewID, states) {
        this.states.set(viewID, { ...states });
    }

    bindState(viewID, binding) {
        this.stateBindings.set(viewID, binding);
    }

    getElementValue(viewID, viewPartID = 0) {
        const binding = this.bindings.get(viewID);
        if (binding) return binding.getValue(viewPartID);
        if (this.values.has(viewID)) return this.values.get(viewID);
        this.logger.log(`getElementValue: no element with id ${viewID}`, "warning");
        return null;
    }

    setElementValue(viewID, viewPartID = 0, value) {
        this.values.set(viewID, value);
        const binding = this.bindings.get(viewID);
        if (binding) {
            binding.setValue(value, viewPartID);
        } else {
            this.logger.log(`setElementValue: no element with id ${viewID}`, "warning");
        }
    }

    getElementState(viewID, key) {
        const binding = this.stateBindings.get(viewID);
        if (binding) {
            const value = binding.getState(key);
            if (value !== undefined) return value;
        }
        const states = this.states.get(viewID);
        if (states && key in states) return states[key];
        this.logger.log(`getElementState: no state "${key}" on element ${viewID}`, "warning");
        return null;
    }

    setElementState(viewID, key, value) {
        const states = this.states.get(viewID) ?? {};
        states[key] = value;
        this.states.set(viewID, states);
        const binding = this.stateBindings.get(viewID);
        if (!binding) {
            this.logger.log(`setElementState: no element with id ${viewID}`, "warning");
            return;
        }
        binding.setState(key, value);
    }

    // User interaction entry point called by view implementations.
    // Mirrors the Swift action callback signature:
    // (actionID, windowUUID, viewID, viewPartID, context)
    dispatchAction(actionID, viewID, viewPartID = 0, context = null) {
        if (!actionID) return;
        this.actionDispatcher?.(actionID, this.windowUUID, viewID, viewPartID, context);
    }
}

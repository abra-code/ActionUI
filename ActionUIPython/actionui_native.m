/*
 * actionui_native.m
 * Python C extension module for ActionUI
 *
 * Wraps the C interface of ActionUICAdapter.framework.
 *
 * This file is compiled as Objective-C (.m) so that the Clang front-end
 * defines __OBJC__ automatically.  The Swift-generated bridging header
 * (ActionUICAdapter-Swift.h) guards all @_cdecl function declarations with
 *   #if defined(__OBJC__)
 * which is entered naturally in ObjC compilation mode.
 *
 */

#define PY_SSIZE_T_CLEAN
#include <Python.h>

#import <ActionUICAdapter/ActionUICAdapter-Swift.h>
#import <ActionUIAppKitApplication/ActionUIAppKitApplication-Swift.h>

// MARK: - Module State

typedef struct {
    PyObject* logger_callback;
    PyObject* action_handlers;  // dict: actionID (str) -> callable
    PyObject* default_handler;
    // App lifecycle callbacks (ActionUIAppKitApplication)
    PyObject* app_will_finish_launching;
    PyObject* app_did_finish_launching;
    PyObject* app_will_become_active;
    PyObject* app_did_become_active;
    PyObject* app_will_resign_active;
    PyObject* app_did_resign_active;
    PyObject* app_will_terminate;
    PyObject* app_should_terminate;
    PyObject* app_window_will_close;
    PyObject* app_window_will_present;
} ActionUIModuleState;

static inline ActionUIModuleState* get_state(PyObject* module) {
    return (ActionUIModuleState*)PyModule_GetState(module);
}

// MARK: - Logger Bridge

static void logger_callback_bridge(const char* message, ActionUILogLevel level) {
    PyGILState_STATE gstate = PyGILState_Ensure();

    PyObject* modules = PyImport_GetModuleDict();
    PyObject* module  = PyDict_GetItemString(modules, "_actionui");
    if (module == NULL) { PyGILState_Release(gstate); return; }

    ActionUIModuleState* state = get_state(module);
    if (state == NULL || state->logger_callback == NULL) { PyGILState_Release(gstate); return; }

    PyObject* result = PyObject_CallFunction(state->logger_callback, "si",
                                             message, (int)level);
    Py_XDECREF(result);
    PyGILState_Release(gstate);
}

// MARK: - Action Handler Bridge

static void action_handler_bridge(const char* actionID,
                                   const char* windowUUID,
                                   int64_t     viewID,
                                   int64_t     viewPartID,
                                   const char* contextJSON)
{
    PyGILState_STATE gstate = PyGILState_Ensure();

    PyObject* modules = PyImport_GetModuleDict();
    PyObject* module  = PyDict_GetItemString(modules, "_actionui");
    if (module == NULL) { PyGILState_Release(gstate); return; }

    ActionUIModuleState* state = get_state(module);
    if (state == NULL) { PyGILState_Release(gstate); return; }

    /* Look up handler for this actionID, fall back to default. */
    PyObject* py_actionID = PyUnicode_FromString(actionID);
    PyObject* handler     = NULL;
    if (state->action_handlers != NULL)
        handler = PyDict_GetItem(state->action_handlers, py_actionID);
    if (handler == NULL)
        handler = state->default_handler;

    if (handler != NULL) {
        PyObject* py_context;
        if (contextJSON != NULL) {
            py_context = PyUnicode_FromString(contextJSON);
        } else {
            py_context = Py_None;
            Py_INCREF(Py_None);
        }
        PyObject* result = PyObject_CallFunction(handler, "ssLLO",
                                                 actionID, windowUUID,
                                                 (long long)viewID,
                                                 (long long)viewPartID,
                                                 py_context);
        Py_XDECREF(result);
        Py_DECREF(py_context);
    }

    Py_DECREF(py_actionID);
    PyGILState_Release(gstate);
}

// MARK: - App Lifecycle Bridges

/*
 * Generic bridge for void app lifecycle callbacks.
 * Acquires the GIL, looks up the matching PyObject in module state, and calls it.
 */
#define APP_LIFECYCLE_BRIDGE(func_name, state_field) \
static void func_name(void) { \
    PyGILState_STATE gstate = PyGILState_Ensure(); \
    PyObject* modules = PyImport_GetModuleDict(); \
    PyObject* module  = PyDict_GetItemString(modules, "_actionui"); \
    if (module != NULL) { \
        ActionUIModuleState* state = get_state(module); \
        if (state != NULL && state->state_field != NULL) { \
            PyObject* r = PyObject_CallObject(state->state_field, NULL); \
            Py_XDECREF(r); \
        } \
    } \
    PyGILState_Release(gstate); \
}

APP_LIFECYCLE_BRIDGE(app_will_finish_launching_bridge, app_will_finish_launching)
APP_LIFECYCLE_BRIDGE(app_did_finish_launching_bridge,  app_did_finish_launching)
APP_LIFECYCLE_BRIDGE(app_will_become_active_bridge,    app_will_become_active)
APP_LIFECYCLE_BRIDGE(app_did_become_active_bridge,     app_did_become_active)
APP_LIFECYCLE_BRIDGE(app_will_resign_active_bridge,    app_will_resign_active)
APP_LIFECYCLE_BRIDGE(app_did_resign_active_bridge,     app_did_resign_active)
APP_LIFECYCLE_BRIDGE(app_will_terminate_bridge,        app_will_terminate)

static bool app_should_terminate_bridge(void) {
    PyGILState_STATE gstate = PyGILState_Ensure();
    PyObject* modules = PyImport_GetModuleDict();
    PyObject* module  = PyDict_GetItemString(modules, "_actionui");
    bool result = true;  // default: allow termination
    if (module != NULL) {
        ActionUIModuleState* state = get_state(module);
        if (state != NULL && state->app_should_terminate != NULL) {
            PyObject* py_result = PyObject_CallObject(state->app_should_terminate, NULL);
            if (py_result != NULL) {
                result = (PyObject_IsTrue(py_result) != 0);
                Py_DECREF(py_result);
            }
        }
    }
    PyGILState_Release(gstate);
    return result;
}

static void app_window_will_close_bridge(const char* windowUUID) {
    PyGILState_STATE gstate = PyGILState_Ensure();
    PyObject* modules = PyImport_GetModuleDict();
    PyObject* module  = PyDict_GetItemString(modules, "_actionui");
    if (module != NULL) {
        ActionUIModuleState* state = get_state(module);
        if (state != NULL && state->app_window_will_close != NULL) {
            PyObject* r = PyObject_CallFunction(state->app_window_will_close, "s", windowUUID);
            Py_XDECREF(r);
        }
    }
    PyGILState_Release(gstate);
}

static void app_window_will_present_bridge(const char* windowUUID) {
    PyGILState_STATE gstate = PyGILState_Ensure();
    PyObject* modules = PyImport_GetModuleDict();
    PyObject* module  = PyDict_GetItemString(modules, "_actionui");
    if (module != NULL) {
        ActionUIModuleState* state = get_state(module);
        if (state != NULL && state->app_window_will_present != NULL) {
            PyObject* r = PyObject_CallFunction(state->app_window_will_present, "s", windowUUID);
            Py_XDECREF(r);
        }
    }
    PyGILState_Release(gstate);
}

// MARK: - Python API: App Lifecycle

/*
 * Setter factory for void lifecycle handlers.
 * Stores callback in module state (keeping a Python reference) and wires the C bridge.
 */
#define APP_LIFECYCLE_SETTER(py_func, state_field, c_setter, bridge) \
static PyObject* py_func(PyObject* self, PyObject* args) { \
    PyObject* callback; \
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL; \
    ActionUIModuleState* state = get_state(self); \
    if (callback == Py_None) { \
        Py_CLEAR(state->state_field); \
        c_setter(NULL); \
    } else { \
        if (PyCallable_Check(callback) == 0) { \
            PyErr_SetString(PyExc_TypeError, "callback must be callable"); \
            return NULL; \
        } \
        Py_XDECREF(state->state_field); \
        Py_INCREF(callback); \
        state->state_field = callback; \
        c_setter(bridge); \
    } \
    Py_RETURN_NONE; \
}

APP_LIFECYCLE_SETTER(py_app_set_will_finish_launching, app_will_finish_launching,
                     actionUIAppSetWillFinishLaunchingHandler, app_will_finish_launching_bridge)
APP_LIFECYCLE_SETTER(py_app_set_did_finish_launching,  app_did_finish_launching,
                     actionUIAppSetDidFinishLaunchingHandler,  app_did_finish_launching_bridge)
APP_LIFECYCLE_SETTER(py_app_set_will_become_active,    app_will_become_active,
                     actionUIAppSetWillBecomeActiveHandler,    app_will_become_active_bridge)
APP_LIFECYCLE_SETTER(py_app_set_did_become_active,     app_did_become_active,
                     actionUIAppSetDidBecomeActiveHandler,     app_did_become_active_bridge)
APP_LIFECYCLE_SETTER(py_app_set_will_resign_active,    app_will_resign_active,
                     actionUIAppSetWillResignActiveHandler,    app_will_resign_active_bridge)
APP_LIFECYCLE_SETTER(py_app_set_did_resign_active,     app_did_resign_active,
                     actionUIAppSetDidResignActiveHandler,     app_did_resign_active_bridge)
APP_LIFECYCLE_SETTER(py_app_set_will_terminate,        app_will_terminate,
                     actionUIAppSetWillTerminateHandler,       app_will_terminate_bridge)

static PyObject* py_app_set_should_terminate(PyObject* self, PyObject* args) {
    PyObject* callback;
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL;
    ActionUIModuleState* state = get_state(self);
    if (callback == Py_None) {
        Py_CLEAR(state->app_should_terminate);
        actionUIAppSetShouldTerminateHandler(NULL);
    } else {
        if (PyCallable_Check(callback) == 0) {
            PyErr_SetString(PyExc_TypeError, "callback must be callable");
            return NULL;
        }
        Py_XDECREF(state->app_should_terminate);
        Py_INCREF(callback);
        state->app_should_terminate = callback;
        actionUIAppSetShouldTerminateHandler(app_should_terminate_bridge);
    }
    Py_RETURN_NONE;
}

static PyObject* py_app_set_window_will_close(PyObject* self, PyObject* args) {
    PyObject* callback;
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL;
    ActionUIModuleState* state = get_state(self);
    if (callback == Py_None) {
        Py_CLEAR(state->app_window_will_close);
        actionUIAppSetWindowWillCloseHandler(NULL);
    } else {
        if (PyCallable_Check(callback) == 0) {
            PyErr_SetString(PyExc_TypeError, "callback must be callable");
            return NULL;
        }
        Py_XDECREF(state->app_window_will_close);
        Py_INCREF(callback);
        state->app_window_will_close = callback;
        actionUIAppSetWindowWillCloseHandler(app_window_will_close_bridge);
    }
    Py_RETURN_NONE;
}

static PyObject* py_app_set_window_will_present(PyObject* self, PyObject* args) {
    PyObject* callback;
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL;
    ActionUIModuleState* state = get_state(self);
    if (callback == Py_None) {
        Py_CLEAR(state->app_window_will_present);
        actionUIAppSetWindowWillPresentHandler(NULL);
    } else {
        if (PyCallable_Check(callback) == 0) {
            PyErr_SetString(PyExc_TypeError, "callback must be callable");
            return NULL;
        }
        Py_XDECREF(state->app_window_will_present);
        Py_INCREF(callback);
        state->app_window_will_present = callback;
        actionUIAppSetWindowWillPresentHandler(app_window_will_present_bridge);
    }
    Py_RETURN_NONE;
}

static PyObject* py_app_set_name(PyObject* self, PyObject* args) {
    const char* name;
    if (PyArg_ParseTuple(args, "s", &name) == 0) return NULL;
    actionUIAppSetName(name);
    Py_RETURN_NONE;
}

static PyObject* py_app_run(PyObject* self, PyObject* args) {
    Py_BEGIN_ALLOW_THREADS
    actionUIAppRun();
    Py_END_ALLOW_THREADS
    Py_RETURN_NONE;
}

static PyObject* py_app_terminate(PyObject* self, PyObject* args) {
    actionUIAppTerminate();
    Py_RETURN_NONE;
}

static PyObject* py_app_load_and_present_window(PyObject* self, PyObject* args) {
    const char* urlString;
    const char* windowUUID;
    const char* title = NULL;
    if (PyArg_ParseTuple(args, "ss|z", &urlString, &windowUUID, &title) == 0) return NULL;
    actionUIAppLoadAndPresentWindow(urlString, windowUUID, title);
    Py_RETURN_NONE;
}

static PyObject* py_app_close_window(PyObject* self, PyObject* args) {
    const char* windowUUID;
    if (PyArg_ParseTuple(args, "s", &windowUUID) == 0) return NULL;
    actionUIAppCloseWindow(windowUUID);
    Py_RETURN_NONE;
}

static PyObject* py_app_load_menu_bar(PyObject* self, PyObject* args) {
    const char* jsonString = NULL;
    if (PyArg_ParseTuple(args, "|z", &jsonString) == 0) return NULL;
    actionUIAppLoadMenuBar(jsonString);
    Py_RETURN_NONE;
}

static PyObject* py_app_run_open_panel(PyObject* self, PyObject* args) {
    const char* configJSON = NULL;
    if (PyArg_ParseTuple(args, "|z", &configJSON) == 0) return NULL;
    char* result = actionUIAppRunOpenPanel(configJSON);
    if (result == NULL) Py_RETURN_NONE;
    PyObject* py_result = PyUnicode_FromString(result);
    actionUIFreeString(result);
    return py_result;
}

static PyObject* py_app_run_save_panel(PyObject* self, PyObject* args) {
    const char* configJSON = NULL;
    if (PyArg_ParseTuple(args, "|z", &configJSON) == 0) return NULL;
    char* result = actionUIAppRunSavePanel(configJSON);
    if (result == NULL) Py_RETURN_NONE;
    PyObject* py_result = PyUnicode_FromString(result);
    actionUIFreeString(result);
    return py_result;
}

// MARK: - Python API: Version

static PyObject* py_get_version(PyObject* self, PyObject* args) {
    char* version = actionUIGetVersion();
    if (version == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(version);
    actionUIFreeString(version);
    return result;
}

// MARK: - Python API: Logging

static PyObject* py_set_logger(PyObject* self, PyObject* args) {
    PyObject* callback;
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL;

    ActionUIModuleState* state = get_state(self);

    if (callback == Py_None) {
        Py_XDECREF(state->logger_callback);
        state->logger_callback = NULL;
        actionUISetLogger(NULL);
    } else {
        if (PyCallable_Check(callback) == 0) {
            PyErr_SetString(PyExc_TypeError, "callback must be callable");
            return NULL;
        }
        Py_XDECREF(state->logger_callback);
        Py_INCREF(callback);
        state->logger_callback = callback;
        actionUISetLogger(logger_callback_bridge);
    }
    Py_RETURN_NONE;
}

static PyObject* py_log(PyObject* self, PyObject* args) {
    const char* message;
    int level;
    if (PyArg_ParseTuple(args, "si", &message, &level) == 0) return NULL;
    actionUILog(message, (ActionUILogLevel)level);
    Py_RETURN_NONE;
}

// MARK: - Python API: Action Handlers

static PyObject* py_register_action_handler(PyObject* self, PyObject* args) {
    const char* actionID;
    PyObject*   callback;
    if (PyArg_ParseTuple(args, "sO", &actionID, &callback) == 0) return NULL;

    if (PyCallable_Check(callback) == 0) {
        PyErr_SetString(PyExc_TypeError, "callback must be callable");
        return NULL;
    }

    ActionUIModuleState* state    = get_state(self);
    PyObject*            py_aid   = PyUnicode_FromString(actionID);
    Py_INCREF(callback);
    PyDict_SetItem(state->action_handlers, py_aid, callback);
    Py_DECREF(py_aid);

    bool ok = actionUIRegisterActionHandler(actionID, action_handler_bridge);
    return PyBool_FromLong(ok);
}

static PyObject* py_unregister_action_handler(PyObject* self, PyObject* args) {
    const char* actionID;
    if (PyArg_ParseTuple(args, "s", &actionID) == 0) return NULL;

    ActionUIModuleState* state  = get_state(self);
    PyObject*            py_aid = PyUnicode_FromString(actionID);
    PyDict_DelItem(state->action_handlers, py_aid);
    Py_DECREF(py_aid);

    bool ok = actionUIUnregisterActionHandler(actionID);
    return PyBool_FromLong(ok);
}

static PyObject* py_set_default_action_handler(PyObject* self, PyObject* args) {
    PyObject* callback;
    if (PyArg_ParseTuple(args, "O", &callback) == 0) return NULL;

    ActionUIModuleState* state = get_state(self);

    if (callback == Py_None) {
        Py_XDECREF(state->default_handler);
        state->default_handler = NULL;
        actionUIRemoveDefaultActionHandler();
    } else {
        if (PyCallable_Check(callback) == 0) {
            PyErr_SetString(PyExc_TypeError, "callback must be callable");
            return NULL;
        }
        Py_XDECREF(state->default_handler);
        Py_INCREF(callback);
        state->default_handler = callback;
        actionUISetDefaultActionHandler(action_handler_bridge);
    }
    Py_RETURN_NONE;
}

// MARK: - Python API: Error Handling

static PyObject* py_get_last_error(PyObject* self, PyObject* args) {
    char* err = actionUIGetLastError();
    if (err == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(err);
    actionUIFreeString(err);
    return result;
}

static PyObject* py_clear_error(PyObject* self, PyObject* args) {
    actionUIClearError();
    Py_RETURN_NONE;
}

// MARK: - Python API: Element Values — Type-specific Setters

static PyObject* py_set_int_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID, value;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLL|L", &windowUUID, &viewID, &value, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetIntValue(windowUUID, viewID, value, viewPartID));
}

static PyObject* py_set_double_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    double value;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLd|L", &windowUUID, &viewID, &value, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetDoubleValue(windowUUID, viewID, value, viewPartID));
}

static PyObject* py_set_bool_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    int value;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLp|L", &windowUUID, &viewID, &value, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetBoolValue(windowUUID, viewID, value != 0, viewPartID));
}

static PyObject* py_set_string_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* value;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLs|L", &windowUUID, &viewID, &value, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetStringValue(windowUUID, viewID, value, viewPartID));
}

// MARK: - Python API: Element Values — Type-specific Getters

static PyObject* py_get_int_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    int64_t out;
    if (actionUIGetIntValue(windowUUID, viewID, viewPartID, &out))
        return PyLong_FromLongLong(out);
    Py_RETURN_NONE;
}

static PyObject* py_get_double_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    double out;
    if (actionUIGetDoubleValue(windowUUID, viewID, viewPartID, &out))
        return PyFloat_FromDouble(out);
    Py_RETURN_NONE;
}

static PyObject* py_get_bool_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    bool out;
    if (actionUIGetBoolValue(windowUUID, viewID, viewPartID, &out))
        return PyBool_FromLong(out);
    Py_RETURN_NONE;
}

static PyObject* py_get_string_value(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    char* val = actionUIGetStringValue(windowUUID, viewID, viewPartID);
    if (val == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(val);
    actionUIFreeString(val);
    return result;
}

// MARK: - Python API: Element Values — Generic (string / JSON)

static PyObject* py_set_value_from_string(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* valueString;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLs|L", &windowUUID, &viewID, &valueString, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementValueString(windowUUID, viewID, valueString, viewPartID));
}

static PyObject* py_get_value_as_string(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    char* val = actionUIGetElementValueString(windowUUID, viewID, viewPartID);
    if (val == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(val);
    actionUIFreeString(val);
    return result;
}

static PyObject* py_set_value_from_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* jsonString;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sLs|L", &windowUUID, &viewID, &jsonString, &viewPartID) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementValueJSON(windowUUID, viewID, jsonString, viewPartID));
}

static PyObject* py_get_value_as_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    long long viewPartID = 0;
    if (PyArg_ParseTuple(args, "sL|L", &windowUUID, &viewID, &viewPartID) == 0)
        return NULL;
    char* val = actionUIGetElementValueJSON(windowUUID, viewID, viewPartID);
    if (val == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(val);
    actionUIFreeString(val);
    return result;
}

// MARK: - Python API: Element Column Count

static PyObject* py_get_element_column_count(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    if (PyArg_ParseTuple(args, "sL", &windowUUID, &viewID) == 0)
        return NULL;
    int64_t count = actionUIGetElementColumnCount(windowUUID, viewID);
    return PyLong_FromLongLong(count);
}

// MARK: - Python API: Element Rows

static PyObject* py_get_element_rows_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    if (PyArg_ParseTuple(args, "sL", &windowUUID, &viewID) == 0)
        return NULL;
    char* json = actionUIGetElementRowsJSON(windowUUID, viewID);
    if (json == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(json);
    actionUIFreeString(json);
    return result;
}

static PyObject* py_clear_element_rows(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    if (PyArg_ParseTuple(args, "sL", &windowUUID, &viewID) == 0)
        return NULL;
    actionUIClearElementRows(windowUUID, viewID);
    Py_RETURN_NONE;
}

static PyObject* py_set_element_rows_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* rowsJSON;
    if (PyArg_ParseTuple(args, "sLs", &windowUUID, &viewID, &rowsJSON) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementRowsJSON(windowUUID, viewID, rowsJSON));
}

static PyObject* py_append_element_rows_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* rowsJSON;
    if (PyArg_ParseTuple(args, "sLs", &windowUUID, &viewID, &rowsJSON) == 0)
        return NULL;
    return PyBool_FromLong(actionUIAppendElementRowsJSON(windowUUID, viewID, rowsJSON));
}

// MARK: - Python API: Element Properties

static PyObject* py_get_element_property_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* propertyName;
    if (PyArg_ParseTuple(args, "sLs", &windowUUID, &viewID, &propertyName) == 0)
        return NULL;
    char* json = actionUIGetElementPropertyJSON(windowUUID, viewID, propertyName);
    if (json == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(json);
    actionUIFreeString(json);
    return result;
}

static PyObject* py_set_element_property_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* propertyName;
    const char* valueJSON;
    if (PyArg_ParseTuple(args, "sLss", &windowUUID, &viewID, &propertyName, &valueJSON) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementPropertyJSON(windowUUID, viewID, propertyName, valueJSON));
}

// MARK: - Python API: Element State

static PyObject* py_get_element_state_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* key;
    if (PyArg_ParseTuple(args, "sLs", &windowUUID, &viewID, &key) == 0)
        return NULL;
    char* json = actionUIGetElementStateJSON(windowUUID, viewID, key);
    if (json == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(json);
    actionUIFreeString(json);
    return result;
}

static PyObject* py_get_element_state_string(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* key;
    if (PyArg_ParseTuple(args, "sLs", &windowUUID, &viewID, &key) == 0)
        return NULL;
    char* val = actionUIGetElementStateString(windowUUID, viewID, key);
    if (val == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(val);
    actionUIFreeString(val);
    return result;
}

static PyObject* py_set_element_state_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* key;
    const char* valueJSON;
    if (PyArg_ParseTuple(args, "sLss", &windowUUID, &viewID, &key, &valueJSON) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementStateJSON(windowUUID, viewID, key, valueJSON));
}

static PyObject* py_set_element_state_from_string(PyObject* self, PyObject* args) {
    const char* windowUUID;
    long long viewID;
    const char* key;
    const char* value;
    if (PyArg_ParseTuple(args, "sLss", &windowUUID, &viewID, &key, &value) == 0)
        return NULL;
    return PyBool_FromLong(actionUISetElementStateFromString(windowUUID, viewID, key, value));
}

// MARK: - Python API: Element Info

static PyObject* py_get_element_info_json(PyObject* self, PyObject* args) {
    const char* windowUUID;
    if (PyArg_ParseTuple(args, "s", &windowUUID) == 0)
        return NULL;
    char* json = actionUIGetElementInfoJSON(windowUUID);
    if (json == NULL) Py_RETURN_NONE;
    PyObject* result = PyUnicode_FromString(json);
    actionUIFreeString(json);
    return result;
}

// MARK: - Python API: UI Loading

/*
 * actionUILoadHostingControllerFromURL handles both file:// and http(s)://
 * URLs, returning an opaque pointer to the platform hosting controller/view.
 * Returns NULL on error (call get_last_error() for details).
 */
static PyObject* py_load_hosting_controller(PyObject* self, PyObject* args) {
    const char* urlString;
    const char* windowUUID;
    int isContentView;
    if (PyArg_ParseTuple(args, "ssp", &urlString, &windowUUID, &isContentView) == 0)
        return NULL;

    void* ptr = actionUILoadHostingControllerFromURL(urlString, windowUUID, isContentView != 0);
    if (ptr != NULL)
        return PyLong_FromVoidPtr(ptr);

    char* err = actionUIGetLastError();
    if (err != NULL) {
        PyErr_SetString(PyExc_RuntimeError, err);
        actionUIFreeString(err);
    } else {
        PyErr_SetString(PyExc_RuntimeError, "actionUILoadHostingControllerFromURL failed");
    }
    return NULL;
}

// MARK: - Module Definition

static PyMethodDef ActionUIMethods[] = {
    /* Version */
    {"get_version",                 py_get_version,                 METH_NOARGS,  "Get ActionUI version string."},

    /* Logging */
    {"set_logger",                  py_set_logger,                  METH_VARARGS, "set_logger(callback|None) — set or clear the log callback."},
    {"log",                         py_log,                         METH_VARARGS, "log(message, level) — emit a log message."},

    /* Error handling */
    {"get_last_error",              py_get_last_error,              METH_NOARGS,  "get_last_error() -> str|None — last adapter error, or None."},
    {"clear_error",                 py_clear_error,                 METH_NOARGS,  "clear_error() — clear the stored last error."},

    /* Action handlers */
    {"register_action_handler",     py_register_action_handler,     METH_VARARGS, "register_action_handler(actionID, callback)"},
    {"unregister_action_handler",   py_unregister_action_handler,   METH_VARARGS, "unregister_action_handler(actionID)"},
    {"set_default_action_handler",  py_set_default_action_handler,  METH_VARARGS, "set_default_action_handler(callback|None)"},

    /* Type-specific setters */
    {"set_int_value",               py_set_int_value,               METH_VARARGS, "set_int_value(windowUUID, viewID, value[, viewPartID])"},
    {"set_double_value",            py_set_double_value,            METH_VARARGS, "set_double_value(windowUUID, viewID, value[, viewPartID])"},
    {"set_bool_value",              py_set_bool_value,              METH_VARARGS, "set_bool_value(windowUUID, viewID, value[, viewPartID])"},
    {"set_string_value",            py_set_string_value,            METH_VARARGS, "set_string_value(windowUUID, viewID, value[, viewPartID])"},

    /* Type-specific getters */
    {"get_int_value",               py_get_int_value,               METH_VARARGS, "get_int_value(windowUUID, viewID[, viewPartID]) -> int|None"},
    {"get_double_value",            py_get_double_value,            METH_VARARGS, "get_double_value(windowUUID, viewID[, viewPartID]) -> float|None"},
    {"get_bool_value",              py_get_bool_value,              METH_VARARGS, "get_bool_value(windowUUID, viewID[, viewPartID]) -> bool|None"},
    {"get_string_value",            py_get_string_value,            METH_VARARGS, "get_string_value(windowUUID, viewID[, viewPartID]) -> str|None"},

    /* Generic value access */
    {"set_value_from_string",       py_set_value_from_string,       METH_VARARGS, "set_value_from_string(windowUUID, viewID, value[, viewPartID])"},
    {"get_value_as_string",         py_get_value_as_string,         METH_VARARGS, "get_value_as_string(windowUUID, viewID[, viewPartID]) -> str|None"},
    {"set_value_from_json",         py_set_value_from_json,         METH_VARARGS, "set_value_from_json(windowUUID, viewID, jsonStr[, viewPartID])"},
    {"get_value_as_json",           py_get_value_as_json,           METH_VARARGS, "get_value_as_json(windowUUID, viewID[, viewPartID]) -> str|None"},

    /* Element column count */
    {"get_element_column_count",    py_get_element_column_count,    METH_VARARGS, "get_element_column_count(windowUUID, viewID) -> int"},

    /* Element rows */
    {"get_element_rows_json",       py_get_element_rows_json,       METH_VARARGS, "get_element_rows_json(windowUUID, viewID) -> str|None"},
    {"clear_element_rows",          py_clear_element_rows,          METH_VARARGS, "clear_element_rows(windowUUID, viewID)"},
    {"set_element_rows_json",       py_set_element_rows_json,       METH_VARARGS, "set_element_rows_json(windowUUID, viewID, rowsJSON)"},
    {"append_element_rows_json",    py_append_element_rows_json,    METH_VARARGS, "append_element_rows_json(windowUUID, viewID, rowsJSON)"},

    /* Element properties */
    {"get_element_property_json",   py_get_element_property_json,   METH_VARARGS, "get_element_property_json(windowUUID, viewID, name) -> str|None"},
    {"set_element_property_json",   py_set_element_property_json,   METH_VARARGS, "set_element_property_json(windowUUID, viewID, name, valueJSON)"},

    /* Element state */
    {"get_element_state_json",      py_get_element_state_json,      METH_VARARGS, "get_element_state_json(windowUUID, viewID, key) -> str|None"},
    {"get_element_state_string",    py_get_element_state_string,    METH_VARARGS, "get_element_state_string(windowUUID, viewID, key) -> str|None"},
    {"set_element_state_json",      py_set_element_state_json,      METH_VARARGS, "set_element_state_json(windowUUID, viewID, key, valueJSON)"},
    {"set_element_state_from_string", py_set_element_state_from_string, METH_VARARGS, "set_element_state_from_string(windowUUID, viewID, key, value)"},

    /* Element info */
    {"get_element_info_json",       py_get_element_info_json,       METH_VARARGS, "get_element_info_json(windowUUID) -> str|None"},

    /* UI loading */
    {"load_hosting_controller",     py_load_hosting_controller,     METH_VARARGS,
     "load_hosting_controller(urlString, windowUUID, isContentView) -> int\n"
     "Accepts file:// or http(s):// URLs.  Returns opaque pointer as int."},

    /* App lifecycle — handler registration */
    {"app_set_will_finish_launching", py_app_set_will_finish_launching, METH_VARARGS,
     "app_set_will_finish_launching(callback|None)"},
    {"app_set_did_finish_launching",  py_app_set_did_finish_launching,  METH_VARARGS,
     "app_set_did_finish_launching(callback|None)"},
    {"app_set_will_become_active",    py_app_set_will_become_active,    METH_VARARGS,
     "app_set_will_become_active(callback|None)"},
    {"app_set_did_become_active",     py_app_set_did_become_active,     METH_VARARGS,
     "app_set_did_become_active(callback|None)"},
    {"app_set_will_resign_active",    py_app_set_will_resign_active,    METH_VARARGS,
     "app_set_will_resign_active(callback|None)"},
    {"app_set_did_resign_active",     py_app_set_did_resign_active,     METH_VARARGS,
     "app_set_did_resign_active(callback|None)"},
    {"app_set_will_terminate",        py_app_set_will_terminate,        METH_VARARGS,
     "app_set_will_terminate(callback|None)"},
    {"app_set_should_terminate",      py_app_set_should_terminate,      METH_VARARGS,
     "app_set_should_terminate(callback|None) — callback() -> bool"},
    {"app_set_window_will_close",     py_app_set_window_will_close,     METH_VARARGS,
     "app_set_window_will_close(callback|None) — callback(windowUUID: str)"},
    {"app_set_window_will_present",   py_app_set_window_will_present,   METH_VARARGS,
     "app_set_window_will_present(callback|None) — callback(windowUUID: str); fires before makeKeyAndOrderFront"},

    /* App name and control */
    {"app_set_name",                  py_app_set_name,                  METH_VARARGS,
     "app_set_name(name) — set the application name for the menu bar."},
    {"app_run",                       py_app_run,                       METH_NOARGS,
     "app_run() — start NSApplication run loop; blocks until the app terminates."},
    {"app_terminate",                 py_app_terminate,                 METH_NOARGS,
     "app_terminate() — request graceful termination (equivalent to Cmd-Q)."},
    {"app_load_and_present_window",   py_app_load_and_present_window,   METH_VARARGS,
     "app_load_and_present_window(url, windowUUID[, title]) — load JSON and open a window."},
    {"app_close_window",              py_app_close_window,              METH_VARARGS,
     "app_close_window(windowUUID) — close the window identified by windowUUID."},
    {"app_load_menu_bar",             py_app_load_menu_bar,             METH_VARARGS,
     "app_load_menu_bar([jsonString]) — install default menu bar and optionally apply commands JSON."},
    {"app_run_open_panel",            py_app_run_open_panel,            METH_VARARGS,
     "app_run_open_panel([configJSON]) -> str|None — run NSOpenPanel; returns JSON array of paths or None."},
    {"app_run_save_panel",            py_app_run_save_panel,            METH_VARARGS,
     "app_run_save_panel([configJSON]) -> str|None — run NSSavePanel; returns path or None."},

    {NULL, NULL, 0, NULL}
};

static int actionui_traverse(PyObject* module, visitproc visit, void* arg) {
    ActionUIModuleState* state = get_state(module);
    Py_VISIT(state->logger_callback);
    Py_VISIT(state->action_handlers);
    Py_VISIT(state->default_handler);
    Py_VISIT(state->app_will_finish_launching);
    Py_VISIT(state->app_did_finish_launching);
    Py_VISIT(state->app_will_become_active);
    Py_VISIT(state->app_did_become_active);
    Py_VISIT(state->app_will_resign_active);
    Py_VISIT(state->app_did_resign_active);
    Py_VISIT(state->app_will_terminate);
    Py_VISIT(state->app_should_terminate);
    Py_VISIT(state->app_window_will_close);
    Py_VISIT(state->app_window_will_present);
    return 0;
}

static int actionui_clear(PyObject* module) {
    ActionUIModuleState* state = get_state(module);
    Py_CLEAR(state->logger_callback);
    Py_CLEAR(state->action_handlers);
    Py_CLEAR(state->default_handler);
    Py_CLEAR(state->app_will_finish_launching);
    Py_CLEAR(state->app_did_finish_launching);
    Py_CLEAR(state->app_will_become_active);
    Py_CLEAR(state->app_did_become_active);
    Py_CLEAR(state->app_will_resign_active);
    Py_CLEAR(state->app_did_resign_active);
    Py_CLEAR(state->app_will_terminate);
    Py_CLEAR(state->app_should_terminate);
    Py_CLEAR(state->app_window_will_close);
    Py_CLEAR(state->app_window_will_present);
    return 0;
}

static void actionui_free(void* module) {
    actionui_clear((PyObject*)module);
}

static struct PyModuleDef actionui_module = {
    PyModuleDef_HEAD_INIT,
    "_actionui",
    "Native ActionUI C extension module.\n\n"
    "Wraps the ActionUICAdapter C interface (ActionUIC.h).  Use the higher-level\n"
    "actionui.py module for a Pythonic API.",
    sizeof(ActionUIModuleState),
    ActionUIMethods,
    NULL,
    actionui_traverse,
    actionui_clear,
    actionui_free
};

PyMODINIT_FUNC PyInit__actionui(void) {
    PyObject* module = PyModule_Create(&actionui_module);
    if (module == NULL) return NULL;

    ActionUIModuleState* state = get_state(module);
    state->logger_callback           = NULL;
    state->action_handlers           = PyDict_New();
    state->default_handler           = NULL;
    state->app_will_finish_launching = NULL;
    state->app_did_finish_launching  = NULL;
    state->app_will_become_active    = NULL;
    state->app_did_become_active     = NULL;
    state->app_will_resign_active    = NULL;
    state->app_did_resign_active     = NULL;
    state->app_will_terminate        = NULL;
    state->app_should_terminate      = NULL;
    state->app_window_will_close     = NULL;
    state->app_window_will_present   = NULL;

    /* Log-level constants */
    PyModule_AddIntConstant(module, "LOG_ERROR",   ActionUILogLevelError);
    PyModule_AddIntConstant(module, "LOG_WARNING", ActionUILogLevelWarning);
    PyModule_AddIntConstant(module, "LOG_INFO",    ActionUILogLevelInfo);
    PyModule_AddIntConstant(module, "LOG_DEBUG",   ActionUILogLevelDebug);
    PyModule_AddIntConstant(module, "LOG_VERBOSE", ActionUILogLevelVerbose);

    return module;
}

/*
 * actionui_node.m
 * Node.js N-API addon for ActionUI
 *
 * Wraps the C interface of ActionUICAdapter.framework and
 * ActionUIAppKitApplication.framework using raw N-API (node_api.h).
 *
 * This file is compiled as Objective-C (.m) so that the Clang front-end
 * defines __OBJC__ automatically.  The Swift-generated bridging headers
 * (ActionUICAdapter-Swift.h, ActionUIAppKitApplication-Swift.h) guard all
 * @_cdecl function declarations with:
 *   #if defined(__OBJC__)
 * which is entered naturally in ObjC compilation mode.
 * The code itself is plain C — only the compilation mode is ObjC.
 *
 * Threading model:
 *   appRun() blocks the Node.js main thread inside [NSApp run].
 *   AppKit/Swift callbacks are dispatched on the main thread (@MainActor).
 *   Since that is the same thread V8 ran on, napi_call_function is safe
 *   inside callbacks — no napi_threadsafe_function needed.
 *   JS callbacks are stored as napi_ref (strong GC roots).
 */

#include <node_api.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#import <ActionUICAdapter/ActionUICAdapter-Swift.h>
#import <ActionUIAppKitApplication/ActionUIAppKitApplication-Swift.h>

// MARK: - Addon State

typedef struct {
    napi_env env;
    napi_ref logger_callback;
    napi_ref action_handlers;       // JS plain object: actionID -> Function
    napi_ref default_handler;
    // App lifecycle
    napi_ref app_will_finish_launching;
    napi_ref app_did_finish_launching;
    napi_ref app_will_become_active;
    napi_ref app_did_become_active;
    napi_ref app_will_resign_active;
    napi_ref app_did_resign_active;
    napi_ref app_will_terminate;
    napi_ref app_should_terminate;
    napi_ref app_window_will_close;
    napi_ref app_window_will_present;
} ActionUIAddonState;

static ActionUIAddonState* g_state = NULL;

static void addon_state_finalizer(napi_env env, void* data, void* hint) {
    ActionUIAddonState* state = (ActionUIAddonState*)data;
    if (state == NULL) return;

#define DELETE_REF(field) \
    if (state->field != NULL) { napi_delete_reference(env, state->field); state->field = NULL; }

    DELETE_REF(logger_callback)
    DELETE_REF(action_handlers)
    DELETE_REF(default_handler)
    DELETE_REF(app_will_finish_launching)
    DELETE_REF(app_did_finish_launching)
    DELETE_REF(app_will_become_active)
    DELETE_REF(app_did_become_active)
    DELETE_REF(app_will_resign_active)
    DELETE_REF(app_did_resign_active)
    DELETE_REF(app_will_terminate)
    DELETE_REF(app_should_terminate)
    DELETE_REF(app_window_will_close)
    DELETE_REF(app_window_will_present)
#undef DELETE_REF

    free(state);
    g_state = NULL;
}

// MARK: - Callback helpers

/* Call a no-arg JS callback stored as a napi_ref. */
static void call_void_callback(napi_ref ref) {
    if (ref == NULL || g_state == NULL) return;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    napi_value fn;
    if (napi_get_reference_value(env, ref, &fn) == napi_ok) {
        napi_value global, result;
        napi_get_global(env, &global);
        napi_call_function(env, global, fn, 0, NULL, &result);
    }

    napi_close_handle_scope(env, scope);
}

/* Call a JS callback that takes one string argument. */
static void call_string_callback(napi_ref ref, const char* str) {
    if (ref == NULL || g_state == NULL) return;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    napi_value fn;
    if (napi_get_reference_value(env, ref, &fn) == napi_ok) {
        napi_value global, result, arg;
        napi_get_global(env, &global);
        napi_create_string_utf8(env, str ? str : "", NAPI_AUTO_LENGTH, &arg);
        napi_call_function(env, global, fn, 1, &arg, &result);
    }

    napi_close_handle_scope(env, scope);
}

/* Safely store a JS function as a napi_ref; clears any existing ref. */
static napi_status store_callback(napi_env env, napi_value fn, napi_ref* out_ref) {
    if (*out_ref != NULL) {
        napi_delete_reference(env, *out_ref);
        *out_ref = NULL;
    }
    napi_valuetype type;
    napi_typeof(env, fn, &type);
    if (type == napi_null || type == napi_undefined) {
        return napi_ok;
    }
    if (type != napi_function) {
        napi_throw_type_error(env, NULL, "callback must be a function");
        return napi_function_expected;
    }
    return napi_create_reference(env, fn, 1, out_ref);
}

// MARK: - Logger Bridge

static void logger_callback_bridge(const char* message, ActionUILogLevel level) {
    if (g_state == NULL || g_state->logger_callback == NULL) return;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    napi_value fn;
    if (napi_get_reference_value(env, g_state->logger_callback, &fn) == napi_ok) {
        napi_value global, result, argv[2];
        napi_get_global(env, &global);
        napi_create_string_utf8(env, message ? message : "", NAPI_AUTO_LENGTH, &argv[0]);
        napi_create_int32(env, (int32_t)level, &argv[1]);
        napi_call_function(env, global, fn, 2, argv, &result);
    }

    napi_close_handle_scope(env, scope);
}

// MARK: - Action Handler Bridge

static void action_handler_bridge(const char* actionID,
                                   const char* windowUUID,
                                   int64_t     viewID,
                                   int64_t     viewPartID,
                                   const char* contextJSON)
{
    if (g_state == NULL) return;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    napi_value fn = NULL;
    bool found = false;

    /* Look up specific handler in action_handlers object. */
    if (g_state->action_handlers != NULL) {
        napi_value handlers_obj;
        if (napi_get_reference_value(env, g_state->action_handlers, &handlers_obj) == napi_ok) {
            napi_value js_key;
            napi_create_string_utf8(env, actionID, NAPI_AUTO_LENGTH, &js_key);
            napi_value handler_val;
            if (napi_get_property(env, handlers_obj, js_key, &handler_val) == napi_ok) {
                napi_valuetype vtype;
                napi_typeof(env, handler_val, &vtype);
                if (vtype == napi_function) {
                    fn = handler_val;
                    found = true;
                }
            }
        }
    }

    /* Fall back to default handler. */
    if (!found && g_state->default_handler != NULL) {
        napi_value default_fn;
        if (napi_get_reference_value(env, g_state->default_handler, &default_fn) == napi_ok) {
            fn = default_fn;
            found = true;
        }
    }

    if (found && fn != NULL) {
        napi_value global, result, argv[5];
        napi_get_global(env, &global);
        napi_create_string_utf8(env, actionID,    NAPI_AUTO_LENGTH, &argv[0]);
        napi_create_string_utf8(env, windowUUID,  NAPI_AUTO_LENGTH, &argv[1]);
        napi_create_int64(env,  viewID,   &argv[2]);
        napi_create_int64(env,  viewPartID, &argv[3]);
        if (contextJSON != NULL) {
            napi_create_string_utf8(env, contextJSON, NAPI_AUTO_LENGTH, &argv[4]);
        } else {
            napi_get_null(env, &argv[4]);
        }
        napi_call_function(env, global, fn, 5, argv, &result);
    }

    napi_close_handle_scope(env, scope);
}

// MARK: - App Lifecycle Bridges

#define APP_LIFECYCLE_BRIDGE(func_name, state_field) \
static void func_name(void) { call_void_callback(g_state ? g_state->state_field : NULL); }

APP_LIFECYCLE_BRIDGE(app_will_finish_launching_bridge, app_will_finish_launching)
APP_LIFECYCLE_BRIDGE(app_did_finish_launching_bridge,  app_did_finish_launching)
APP_LIFECYCLE_BRIDGE(app_will_become_active_bridge,    app_will_become_active)
APP_LIFECYCLE_BRIDGE(app_did_become_active_bridge,     app_did_become_active)
APP_LIFECYCLE_BRIDGE(app_will_resign_active_bridge,    app_will_resign_active)
APP_LIFECYCLE_BRIDGE(app_did_resign_active_bridge,     app_did_resign_active)
APP_LIFECYCLE_BRIDGE(app_will_terminate_bridge,        app_will_terminate)

static bool app_should_terminate_bridge(void) {
    if (g_state == NULL || g_state->app_should_terminate == NULL) return true;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    bool result = true;
    napi_value fn;
    if (napi_get_reference_value(env, g_state->app_should_terminate, &fn) == napi_ok) {
        napi_value global, ret;
        napi_get_global(env, &global);
        if (napi_call_function(env, global, fn, 0, NULL, &ret) == napi_ok) {
            napi_coerce_to_bool(env, ret, &ret);
            napi_get_value_bool(env, ret, &result);
        }
    }

    napi_close_handle_scope(env, scope);
    return result;
}

static void app_window_will_close_bridge(const char* windowUUID) {
    call_string_callback(g_state ? g_state->app_window_will_close : NULL, windowUUID);
}

static void app_window_will_present_bridge(const char* windowUUID) {
    call_string_callback(g_state ? g_state->app_window_will_present : NULL, windowUUID);
}

// MARK: - Lifecycle Setter Macro

#define APP_LIFECYCLE_SETTER(func_name, state_field, c_setter, bridge) \
static napi_value func_name(napi_env env, napi_callback_info info) { \
    size_t argc = 1; napi_value argv[1]; \
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL); \
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; } \
    if (store_callback(env, argv[0], &g_state->state_field) != napi_ok) return NULL; \
    c_setter(g_state->state_field != NULL ? bridge : NULL); \
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined; \
}

APP_LIFECYCLE_SETTER(node_app_set_will_finish_launching, app_will_finish_launching,
                     actionUIAppSetWillFinishLaunchingHandler, app_will_finish_launching_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_finish_launching,  app_did_finish_launching,
                     actionUIAppSetDidFinishLaunchingHandler,  app_did_finish_launching_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_become_active,    app_will_become_active,
                     actionUIAppSetWillBecomeActiveHandler,    app_will_become_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_become_active,     app_did_become_active,
                     actionUIAppSetDidBecomeActiveHandler,     app_did_become_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_resign_active,    app_will_resign_active,
                     actionUIAppSetWillResignActiveHandler,    app_will_resign_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_resign_active,     app_did_resign_active,
                     actionUIAppSetDidResignActiveHandler,     app_did_resign_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_terminate,        app_will_terminate,
                     actionUIAppSetWillTerminateHandler,       app_will_terminate_bridge)

static napi_value node_app_set_should_terminate(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->app_should_terminate) != napi_ok) return NULL;
    actionUIAppSetShouldTerminateHandler(g_state->app_should_terminate != NULL
                                         ? app_should_terminate_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_window_will_close(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->app_window_will_close) != napi_ok) return NULL;
    actionUIAppSetWindowWillCloseHandler(g_state->app_window_will_close != NULL
                                          ? app_window_will_close_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_window_will_present(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->app_window_will_present) != napi_ok) return NULL;
    actionUIAppSetWindowWillPresentHandler(g_state->app_window_will_present != NULL
                                           ? app_window_will_present_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: Version

static napi_value node_get_version(napi_env env, napi_callback_info info) {
    char* version = actionUIGetVersion();
    if (version == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, version, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(version);
    return result;
}

// MARK: - N-API: Logging

static napi_value node_set_logger(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->logger_callback) != napi_ok) return NULL;
    actionUISetLogger(g_state->logger_callback != NULL ? logger_callback_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_log(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char message[4096]; size_t len;
    napi_get_value_string_utf8(env, argv[0], message, sizeof(message), &len);
    int32_t level = 0;
    napi_get_value_int32(env, argv[1], &level);
    actionUILog(message, (ActionUILogLevel)level);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: Error Handling

static napi_value node_get_last_error(napi_env env, napi_callback_info info) {
    char* err = actionUIGetLastError();
    if (err == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, err, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(err);
    return result;
}

static napi_value node_clear_error(napi_env env, napi_callback_info info) {
    actionUIClearError();
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: Action Handlers

static napi_value node_register_action_handler(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char actionID[256]; size_t len;
    napi_get_value_string_utf8(env, argv[0], actionID, sizeof(actionID), &len);

    napi_valuetype vtype;
    napi_typeof(env, argv[1], &vtype);
    if (vtype != napi_function) {
        napi_throw_type_error(env, NULL, "callback must be a function");
        return NULL;
    }

    napi_value handlers_obj;
    napi_get_reference_value(env, g_state->action_handlers, &handlers_obj);
    napi_value key;
    napi_create_string_utf8(env, actionID, NAPI_AUTO_LENGTH, &key);
    napi_set_property(env, handlers_obj, key, argv[1]);

    bool ok = actionUIRegisterActionHandler(actionID, action_handler_bridge);
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

static napi_value node_unregister_action_handler(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char actionID[256]; size_t len;
    napi_get_value_string_utf8(env, argv[0], actionID, sizeof(actionID), &len);

    napi_value handlers_obj;
    napi_get_reference_value(env, g_state->action_handlers, &handlers_obj);
    napi_value key;
    napi_create_string_utf8(env, actionID, NAPI_AUTO_LENGTH, &key);
    napi_delete_property(env, handlers_obj, key, NULL);

    bool ok = actionUIUnregisterActionHandler(actionID);
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

static napi_value node_set_default_action_handler(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }

    napi_valuetype vtype;
    napi_typeof(env, argv[0], &vtype);
    if (vtype == napi_null || vtype == napi_undefined) {
        if (g_state->default_handler != NULL) {
            napi_delete_reference(env, g_state->default_handler);
            g_state->default_handler = NULL;
        }
        actionUIRemoveDefaultActionHandler();
    } else {
        if (store_callback(env, argv[0], &g_state->default_handler) != napi_ok) return NULL;
        actionUISetDefaultActionHandler(action_handler_bridge);
    }
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: Element Values — Setters

static napi_value node_set_int_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0, value = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    if (argc >= 4) napi_get_value_int64(env, argv[3], &value);
    napi_value result;
    napi_get_boolean(env, actionUISetIntValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_double_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0; double value = 0.0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    if (argc >= 4) napi_get_value_double(env, argv[3], &value);
    napi_value result;
    napi_get_boolean(env, actionUISetDoubleValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_bool_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0; bool value = false;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    if (argc >= 4) napi_get_value_bool(env, argv[3], &value);
    napi_value result;
    napi_get_boolean(env, actionUISetBoolValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_string_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    char value[4096];
    if (argc >= 4) {
        napi_get_value_string_utf8(env, argv[3], value, sizeof(value), &len);
    } else {
        value[0] = '\0';
    }
    napi_value result;
    napi_get_boolean(env, actionUISetStringValue(uuid, viewID, partID, value), &result);
    return result;
}

// MARK: - N-API: Element Values — Getters

static napi_value node_get_int_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    int64_t out = 0;
    if (actionUIGetIntValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_create_int64(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_double_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    double out = 0.0;
    if (actionUIGetDoubleValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_create_double(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_bool_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    bool out = false;
    if (actionUIGetBoolValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_get_boolean(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_string_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    char* val = actionUIGetStringValue(uuid, viewID, partID);
    if (val == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, val, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(val);
    return result;
}

// MARK: - N-API: Generic Value Access

static napi_value node_set_value_from_string(napi_env env, napi_callback_info info) {
    size_t argc = 5; napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], value[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    if (argc >= 4) {
        napi_get_value_string_utf8(env, argv[3], value, sizeof(value), &len);
    } else {
        value[0] = '\0';
    }
    const char* contentTypePtr = NULL;
    char contentTypeBuf[64] = {0};
    if (argc >= 5) {
        napi_valuetype ct_type;
        napi_typeof(env, argv[4], &ct_type);
        if (ct_type == napi_string) {
            napi_get_value_string_utf8(env, argv[4], contentTypeBuf, sizeof(contentTypeBuf), &len);
            contentTypePtr = contentTypeBuf;
        }
    }
    napi_value result;
    napi_get_boolean(env, actionUISetElementValueString(uuid, viewID, partID, value, contentTypePtr), &result);
    return result;
}

static napi_value node_get_value_as_string(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    const char* contentTypePtr = NULL;
    char contentTypeBuf[64] = {0};
    if (argc >= 4) {
        napi_valuetype ct_type;
        napi_typeof(env, argv[3], &ct_type);
        if (ct_type == napi_string) {
            napi_get_value_string_utf8(env, argv[3], contentTypeBuf, sizeof(contentTypeBuf), &len);
            contentTypePtr = contentTypeBuf;
        }
    }
    char* val = actionUIGetElementValueString(uuid, viewID, partID, contentTypePtr);
    if (val == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, val, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(val);
    return result;
}

static napi_value node_set_value_from_json(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], json[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    if (argc >= 4) {
        napi_get_value_string_utf8(env, argv[3], json, sizeof(json), &len);
    } else {
        json[0] = '\0';
    }
    napi_value result;
    napi_get_boolean(env, actionUISetElementValueJSON(uuid, viewID, partID, json), &result);
    return result;
}

static napi_value node_get_value_as_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, partID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    if (argc >= 3) napi_get_value_int64(env, argv[2], &partID);
    char* val = actionUIGetElementValueJSON(uuid, viewID, partID);
    if (val == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, val, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(val);
    return result;
}

// MARK: - N-API: Element Column Count

static napi_value node_get_element_column_count(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_value result;
    napi_create_int64(env, actionUIGetElementColumnCount(uuid, viewID), &result);
    return result;
}

// MARK: - N-API: Element Rows

static napi_value node_get_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    char* json = actionUIGetElementRowsJSON(uuid, viewID);
    if (json == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

static napi_value node_clear_element_rows(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    actionUIClearElementRows(uuid, viewID);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_set_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], json[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], json, sizeof(json), &len);
    napi_value result;
    napi_get_boolean(env, actionUISetElementRowsJSON(uuid, viewID, json), &result);
    return result;
}

static napi_value node_append_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], json[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], json, sizeof(json), &len);
    napi_value result;
    napi_get_boolean(env, actionUIAppendElementRowsJSON(uuid, viewID, json), &result);
    return result;
}

// MARK: - N-API: Element Properties

static napi_value node_get_element_property_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], name[256]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], name, sizeof(name), &len);
    char* json = actionUIGetElementPropertyJSON(uuid, viewID, name);
    if (json == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

static napi_value node_set_element_property_json(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], name[256], json[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], name, sizeof(name), &len);
    napi_get_value_string_utf8(env, argv[3], json, sizeof(json), &len);
    napi_value result;
    napi_get_boolean(env, actionUISetElementPropertyJSON(uuid, viewID, name, json), &result);
    return result;
}

// MARK: - N-API: Element State

static napi_value node_get_element_state_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], key[256]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], key, sizeof(key), &len);
    char* json = actionUIGetElementStateJSON(uuid, viewID, key);
    if (json == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

static napi_value node_get_element_state_string(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], key[256]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], key, sizeof(key), &len);
    char* val = actionUIGetElementStateString(uuid, viewID, key);
    if (val == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, val, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(val);
    return result;
}

static napi_value node_set_element_state_json(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], key[256], json[65536]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], key, sizeof(key), &len);
    napi_get_value_string_utf8(env, argv[3], json, sizeof(json), &len);
    napi_value result;
    napi_get_boolean(env, actionUISetElementStateJSON(uuid, viewID, key, json), &result);
    return result;
}

static napi_value node_set_element_state_from_string(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], key[256], value[4096]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], key, sizeof(key), &len);
    napi_get_value_string_utf8(env, argv[3], value, sizeof(value), &len);
    napi_value result;
    napi_get_boolean(env, actionUISetElementStateFromString(uuid, viewID, key, value), &result);
    return result;
}

// MARK: - N-API: Element Info

static napi_value node_get_element_info_json(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    char* json = actionUIGetElementInfoJSON(uuid);
    if (json == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

// MARK: - N-API: Modal Presentation

static napi_value node_present_modal(napi_env env, napi_callback_info info) {
    size_t argc = 5; napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], json[65536], format[32], style[32]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid,   sizeof(uuid),   &len);
    napi_get_value_string_utf8(env, argv[1], json,   sizeof(json),   &len);
    napi_get_value_string_utf8(env, argv[2], format, sizeof(format), &len);
    napi_get_value_string_utf8(env, argv[3], style,  sizeof(style),  &len);

    char dismiss_action[256]; const char* dismiss_ptr = NULL;
    if (argc >= 5) {
        napi_valuetype vtype; napi_typeof(env, argv[4], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[4], dismiss_action, sizeof(dismiss_action), &len);
            dismiss_ptr = dismiss_action;
        }
    }

    ActionUIModalStyle modal_style = (strcmp(style, "fullScreenCover") == 0)
        ? ActionUIModalStyleFullScreenCover : ActionUIModalStyleSheet;

    bool ok = actionUIPresentModal(uuid, json, format, modal_style, dismiss_ptr);
    if (!ok) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUIPresentModal failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_dismiss_modal(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    actionUIDismissModal(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_present_alert(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], title[512]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid,  sizeof(uuid),  &len);
    napi_get_value_string_utf8(env, argv[1], title, sizeof(title), &len);

    char message[4096]; const char* message_ptr = NULL;
    if (argc >= 3) {
        napi_valuetype vtype; napi_typeof(env, argv[2], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[2], message, sizeof(message), &len);
            message_ptr = message;
        }
    }
    char buttons[65536]; const char* buttons_ptr = NULL;
    if (argc >= 4) {
        napi_valuetype vtype; napi_typeof(env, argv[3], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[3], buttons, sizeof(buttons), &len);
            buttons_ptr = buttons;
        }
    }
    (void)actionUIPresentAlert(uuid, title, message_ptr, buttons_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_present_confirmation_dialog(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], title[512]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid,  sizeof(uuid),  &len);
    napi_get_value_string_utf8(env, argv[1], title, sizeof(title), &len);

    char message[4096]; const char* message_ptr = NULL;
    if (argc >= 3) {
        napi_valuetype vtype; napi_typeof(env, argv[2], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[2], message, sizeof(message), &len);
            message_ptr = message;
        }
    }
    char buttons_buf[65536]; const char* buttons_ptr = "[]";
    if (argc >= 4) {
        napi_valuetype vtype; napi_typeof(env, argv[3], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[3], buttons_buf, sizeof(buttons_buf), &len);
            buttons_ptr = buttons_buf;
        }
    }
    (void)actionUIPresentConfirmationDialog(uuid, title, message_ptr, buttons_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_dismiss_dialog(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    actionUIDismissDialog(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: UI Loading

static napi_value node_load_hosting_controller(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char url[4096], uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], url,  sizeof(url),  &len);
    napi_get_value_string_utf8(env, argv[1], uuid, sizeof(uuid), &len);
    bool is_content_view = false;
    napi_get_value_bool(env, argv[2], &is_content_view);

    void* ptr = actionUILoadHostingControllerFromURL(url, uuid, is_content_view);
    if (ptr == NULL) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUILoadHostingControllerFromURL failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    // Return pointer as BigInt to avoid 32-bit truncation
    napi_value result;
    napi_create_bigint_uint64(env, (uint64_t)(uintptr_t)ptr, &result);
    return result;
}

// MARK: - N-API: App Control

static napi_value node_app_set_name(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char name[512]; size_t len;
    napi_get_value_string_utf8(env, argv[0], name, sizeof(name), &len);
    actionUIAppSetName(name);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_icon(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char path[4096]; size_t len;
    napi_get_value_string_utf8(env, argv[0], path, sizeof(path), &len);
    actionUIAppSetIcon(path);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_run(napi_env env, napi_callback_info info) {
    /* Blocks main thread; AppKit run loop takes over. */
    actionUIAppRun();
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_terminate(napi_env env, napi_callback_info info) {
    actionUIAppTerminate();
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_load_and_present_window(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char url[4096], uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], url,  sizeof(url),  &len);
    napi_get_value_string_utf8(env, argv[1], uuid, sizeof(uuid), &len);

    char title[512]; const char* title_ptr = NULL;
    if (argc >= 3) {
        napi_valuetype vtype; napi_typeof(env, argv[2], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[2], title, sizeof(title), &len);
            title_ptr = title;
        }
    }
    actionUIAppLoadAndPresentWindow(url, uuid, title_ptr);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_close_window(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    actionUIAppCloseWindow(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_load_menu_bar(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* json_ptr = NULL;
    char json[65536]; size_t len;
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[0], json, sizeof(json), &len);
            json_ptr = json;
        }
    }
    actionUIAppLoadMenuBar(json_ptr);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_run_open_panel(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* cfg_ptr = NULL;
    char cfg[65536]; size_t len;
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[0], cfg, sizeof(cfg), &len);
            cfg_ptr = cfg;
        }
    }
    char* result = actionUIAppRunOpenPanel(cfg_ptr);
    if (result == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value ret;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &ret);
    actionUIFreeString(result);
    return ret;
}

static napi_value node_app_run_save_panel(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* cfg_ptr = NULL;
    char cfg[65536]; size_t len;
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[0], cfg, sizeof(cfg), &len);
            cfg_ptr = cfg;
        }
    }
    char* result = actionUIAppRunSavePanel(cfg_ptr);
    if (result == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value ret;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &ret);
    actionUIFreeString(result);
    return ret;
}

static napi_value node_app_run_alert(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* cfg_ptr = NULL;
    char cfg[65536]; size_t len;
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[0], cfg, sizeof(cfg), &len);
            cfg_ptr = cfg;
        }
    }
    char* result = actionUIAppRunAlert(cfg_ptr);
    if (result == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value ret;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &ret);
    actionUIFreeString(result);
    return ret;
}

// MARK: - Module Init

#define EXPORT_FN(exports, name, fn) do { \
    napi_value _fn; \
    napi_create_function(env, name, NAPI_AUTO_LENGTH, fn, NULL, &_fn); \
    napi_set_named_property(env, exports, name, _fn); \
} while (0)

#define EXPORT_INT(exports, name, val) do { \
    napi_value _v; \
    napi_create_int32(env, (int32_t)(val), &_v); \
    napi_set_named_property(env, exports, name, _v); \
} while (0)

static napi_value Init(napi_env env, napi_value exports) {
    ActionUIAddonState* state = (ActionUIAddonState*)calloc(1, sizeof(ActionUIAddonState));
    state->env = env;

    /* action_handlers is a plain JS object used as a string-keyed map. */
    napi_value handlers_obj;
    napi_create_object(env, &handlers_obj);
    napi_create_reference(env, handlers_obj, 1, &state->action_handlers);

    napi_set_instance_data(env, state, addon_state_finalizer, NULL);
    if (g_state == NULL) g_state = state;

    /* Version */
    EXPORT_FN(exports, "getVersion",               node_get_version);

    /* Logging */
    EXPORT_FN(exports, "setLogger",                node_set_logger);
    EXPORT_FN(exports, "log",                      node_log);

    /* Error handling */
    EXPORT_FN(exports, "getLastError",             node_get_last_error);
    EXPORT_FN(exports, "clearError",               node_clear_error);

    /* Action handlers */
    EXPORT_FN(exports, "registerActionHandler",    node_register_action_handler);
    EXPORT_FN(exports, "unregisterActionHandler",  node_unregister_action_handler);
    EXPORT_FN(exports, "setDefaultActionHandler",  node_set_default_action_handler);

    /* Type-specific setters */
    EXPORT_FN(exports, "setIntValue",              node_set_int_value);
    EXPORT_FN(exports, "setDoubleValue",           node_set_double_value);
    EXPORT_FN(exports, "setBoolValue",             node_set_bool_value);
    EXPORT_FN(exports, "setStringValue",           node_set_string_value);

    /* Type-specific getters */
    EXPORT_FN(exports, "getIntValue",              node_get_int_value);
    EXPORT_FN(exports, "getDoubleValue",           node_get_double_value);
    EXPORT_FN(exports, "getBoolValue",             node_get_bool_value);
    EXPORT_FN(exports, "getStringValue",           node_get_string_value);

    /* Generic value access */
    EXPORT_FN(exports, "setValueFromString",       node_set_value_from_string);   /* (uuid, viewID, partID, value, contentType=null) */
    EXPORT_FN(exports, "getValueAsString",         node_get_value_as_string);    /* (uuid, viewID, partID=0, contentType=null) -> string|null */
    EXPORT_FN(exports, "setValueFromJSON",         node_set_value_from_json);
    EXPORT_FN(exports, "getValueAsJSON",           node_get_value_as_json);

    /* Content-type aware value access */

    /* Element column count */
    EXPORT_FN(exports, "getElementColumnCount",    node_get_element_column_count);

    /* Element rows */
    EXPORT_FN(exports, "getElementRowsJSON",       node_get_element_rows_json);
    EXPORT_FN(exports, "clearElementRows",         node_clear_element_rows);
    EXPORT_FN(exports, "setElementRowsJSON",       node_set_element_rows_json);
    EXPORT_FN(exports, "appendElementRowsJSON",    node_append_element_rows_json);

    /* Element properties */
    EXPORT_FN(exports, "getElementPropertyJSON",   node_get_element_property_json);
    EXPORT_FN(exports, "setElementPropertyJSON",   node_set_element_property_json);

    /* Element state */
    EXPORT_FN(exports, "getElementStateJSON",      node_get_element_state_json);
    EXPORT_FN(exports, "getElementStateString",    node_get_element_state_string);
    EXPORT_FN(exports, "setElementStateJSON",      node_set_element_state_json);
    EXPORT_FN(exports, "setElementStateFromString",node_set_element_state_from_string);

    /* Element info */
    EXPORT_FN(exports, "getElementInfoJSON",       node_get_element_info_json);

    /* Modal presentation */
    EXPORT_FN(exports, "presentModal",             node_present_modal);
    EXPORT_FN(exports, "dismissModal",             node_dismiss_modal);
    EXPORT_FN(exports, "presentAlert",             node_present_alert);
    EXPORT_FN(exports, "presentConfirmationDialog",node_present_confirmation_dialog);
    EXPORT_FN(exports, "dismissDialog",            node_dismiss_dialog);

    /* UI loading */
    EXPORT_FN(exports, "loadHostingController",    node_load_hosting_controller);

    /* App lifecycle setters */
    EXPORT_FN(exports, "appSetWillFinishLaunching",node_app_set_will_finish_launching);
    EXPORT_FN(exports, "appSetDidFinishLaunching", node_app_set_did_finish_launching);
    EXPORT_FN(exports, "appSetWillBecomeActive",   node_app_set_will_become_active);
    EXPORT_FN(exports, "appSetDidBecomeActive",    node_app_set_did_become_active);
    EXPORT_FN(exports, "appSetWillResignActive",   node_app_set_will_resign_active);
    EXPORT_FN(exports, "appSetDidResignActive",    node_app_set_did_resign_active);
    EXPORT_FN(exports, "appSetWillTerminate",      node_app_set_will_terminate);
    EXPORT_FN(exports, "appSetShouldTerminate",    node_app_set_should_terminate);
    EXPORT_FN(exports, "appSetWindowWillClose",    node_app_set_window_will_close);
    EXPORT_FN(exports, "appSetWindowWillPresent",  node_app_set_window_will_present);

    /* App control */
    EXPORT_FN(exports, "appSetName",               node_app_set_name);
    EXPORT_FN(exports, "appSetIcon",               node_app_set_icon);
    EXPORT_FN(exports, "appRun",                   node_app_run);
    EXPORT_FN(exports, "appTerminate",             node_app_terminate);
    EXPORT_FN(exports, "appLoadAndPresentWindow",  node_app_load_and_present_window);
    EXPORT_FN(exports, "appCloseWindow",           node_app_close_window);
    EXPORT_FN(exports, "appLoadMenuBar",           node_app_load_menu_bar);
    EXPORT_FN(exports, "appRunOpenPanel",          node_app_run_open_panel);
    EXPORT_FN(exports, "appRunSavePanel",          node_app_run_save_panel);
    EXPORT_FN(exports, "appRunAlert",              node_app_run_alert);

    /* Log level constants */
    EXPORT_INT(exports, "LOG_ERROR",   ActionUILogLevelError);
    EXPORT_INT(exports, "LOG_WARNING", ActionUILogLevelWarning);
    EXPORT_INT(exports, "LOG_INFO",    ActionUILogLevelInfo);
    EXPORT_INT(exports, "LOG_DEBUG",   ActionUILogLevelDebug);
    EXPORT_INT(exports, "LOG_VERBOSE", ActionUILogLevelVerbose);

    return exports;
}

NAPI_MODULE(actionui, Init)

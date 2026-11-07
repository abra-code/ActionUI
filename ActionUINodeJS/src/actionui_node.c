/*
 * actionui_node.c
 * Node.js N-API addon for ActionUI
 *
 * Wraps the C interface of ActionUICAdapter.framework and
 * ActionUIAppKitApplication.framework, declared in their plain C headers,
 * using raw N-API (node_api.h).
 *
 * Threading model:
 *   appRun() installs a CFRunLoopObserver, a CFRunLoopTimer and a CFRunLoopSource on the
 *   main CFRunLoop, then calls actionUIAppRun() which blocks in [NSApp run].
 *   The observer pumps libuv (uv_run NOWAIT) before every source pass and
 *   before every sleep, arming the timer when libuv has a future deadline; a
 *   thread watching libuv's backend (kqueue) file descriptor signals the source
 *   when libuv has I/O, and the source pumps libuv on the main thread.
 *   On Linux, appRun() adds a GLib source to the main context instead, then
 *   calls actionUIAppRun(), which blocks in the GTK main loop: the source
 *   watches libuv's backend (epoll) file descriptor, lets GLib sleep only as
 *   long as libuv's next timer allows, and pumps libuv the same way.
 *   AppKit/Swift callbacks are dispatched on the main thread (@MainActor),
 *   which is still V8's owning thread, so no napi_threadsafe_function is
 *   needed.  JS lifecycle callbacks are invoked with napi_make_callback
 *   (≡ node::MakeCallback) with a proper napi_async_context so that
 *   process.nextTick and Promise microtask queues are drained on close.
 */

#if !defined(__APPLE__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE   /* gettid, before the first system header */
#endif

#include <node_api.h>
#include <uv.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#else
#include <glib.h>
#endif
#include <ActionUICAdapter/ActionUIC.h>
#include <ActionUIAppKitApplication/ActionUIApp.h>
#include <ActionUIHostSurface/ActionUIHostSurface.h>

/* Whether the calling thread is the process's main thread (pthread_main_np is Apple and BSD
 * only; on Linux the main thread's ID is the process ID). */
static bool is_main_thread(void) {
#if defined(__APPLE__)
    return pthread_main_np() != 0;
#else
    return gettid() == getpid();
#endif
}

#if !defined(__APPLE__)
/* Linux: the libdispatch inside libActionUI.so binds its main queue to the thread that loads the
 * library, not to the process's main thread (Apple's libdispatch knows the main thread). Loaded
 * first by a worker, ActionUI would take that worker for its main thread: the real main thread's
 * calls would wait for a main queue that only the running application drains (measured: its
 * logger was not called), and one such run crashed. This constructor runs on the loading thread,
 * after libActionUI.so's own; Init refuses the module in every environment when that was not the
 * main thread, so the failure is a clear error instead. */
static bool s_loaded_on_main_thread = false;

__attribute__((constructor))
static void note_loading_thread(void) {
    s_loaded_on_main_thread = is_main_thread();
}
#endif


#define ACTIONUI_DIAGNOSTIC 0

/* Verbosity level for [actionui:diag] logging:
 *   0 = off
 *   1 = errors only
 *   2 = + detailed diagnostics */
#ifndef ACTIONUI_LOG_LEVEL
	#define ACTIONUI_LOG_LEVEL 1
#endif

#if ACTIONUI_LOG_LEVEL >= 2
#define DIAGNOSTIC_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
#define DIAGNOSTIC_LOG(...) ((void)0)
#endif

// MARK: - Addon State

typedef struct {
    napi_env     env;
    uv_loop_t*   uv_loop;
    napi_ref     logger_callback;
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
    napi_async_context async_ctx;   /* proper scope for nextTick/microtask drain */
#if ACTIONUI_DIAGNOSTIC
    napi_ref drain_fn_ref;          /* no-op JS fn called after each uv_run(NOWAIT) */
    napi_ref diag_nexttick_ref;     /* process.nextTick — for sentinel probe */
    napi_ref diag_sentinel_ref;     /* C fn queued as nextTick inside noop to test drain */
#endif
    napi_ref process_tick_ref;      /* _tickCallback */
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
#if ACTIONUI_DIAGNOSTIC
    DELETE_REF(drain_fn_ref)
    DELETE_REF(diag_nexttick_ref)
    DELETE_REF(diag_sentinel_ref)
#endif
    DELETE_REF(process_tick_ref)
#undef DELETE_REF

    if (state->async_ctx != NULL) {
        napi_async_destroy(env, state->async_ctx);
        state->async_ctx = NULL;
    }

    /* Each environment (the main thread and every worker that loads the addon) has its own
     * state, but only the main thread's is g_state. A worker exiting must not clear it: the run
     * loop pump is still reading it. */
    if (g_state == state) g_state = NULL;
    free(state);
}

// MARK: - Callback helpers

/* Call a no-arg JS callback stored as a napi_ref.
 *
 * napi_make_callback (≡ node::MakeCallback) is used instead of
 * napi_call_function so that the process.nextTick and Promise microtask
 * queues are drained before this function returns.  This matters because
 * async APIs like fetch() / undici schedule their internal TCP connection
 * setup via process.nextTick; if that queue is not drained immediately,
 * no libuv handles are registered yet and uv_run(NOWAIT) has nothing to
 * poll — the I/O never completes. */
static void call_void_callback(napi_ref ref) {
    if (ref == NULL || g_state == NULL) return;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);

    napi_value fn;
    if (napi_get_reference_value(env, ref, &fn) == napi_ok) {
        napi_value global, result;
        napi_get_global(env, &global);
        __attribute__((unused)) napi_status s = napi_make_callback(env, g_state->async_ctx, global, fn, 0, NULL, &result);
        DIAGNOSTIC_LOG("[actionui:diag] call_void_callback: make_callback status=%d async_ctx=%p\n",
                (int)s, (void*)g_state->async_ctx);
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
        napi_make_callback(env, g_state->async_ctx, global, fn, 1, &arg, &result);
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

/* ActionUI calls every stored callback on the main thread, through g_state->env, and appRun
 * runs the main thread's event loop. A worker has an environment of its own: storing a callback
 * or running the app from it would mix the two, so those calls throw there instead. */
static bool require_main_env(napi_env env, const char* name) {
    if (g_state != NULL && g_state->env == env) return true;
    char message[160];
    snprintf(message, sizeof(message), "%s must be called on the main thread, not in a worker", name);
    napi_throw_error(env, NULL, message);
    return false;
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

#define APP_LIFECYCLE_SETTER(func_name, js_name, state_field, c_setter, bridge) \
static napi_value func_name(napi_env env, napi_callback_info info) { \
    if (!require_main_env(env, js_name)) return NULL; \
    size_t argc = 1; napi_value argv[1]; \
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL); \
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; } \
    if (store_callback(env, argv[0], &g_state->state_field) != napi_ok) return NULL; \
    c_setter(g_state->state_field != NULL ? bridge : NULL); \
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined; \
}

APP_LIFECYCLE_SETTER(node_app_set_will_finish_launching, "appSetWillFinishLaunching",                     app_will_finish_launching, actionUIAppSetWillFinishLaunchingHandler,  app_will_finish_launching_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_finish_launching,  "appSetDidFinishLaunching",                     app_did_finish_launching,  actionUIAppSetDidFinishLaunchingHandler,   app_did_finish_launching_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_become_active,    "appSetWillBecomeActive",                     app_will_become_active,    actionUIAppSetWillBecomeActiveHandler,     app_will_become_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_become_active,     "appSetDidBecomeActive",                     app_did_become_active,     actionUIAppSetDidBecomeActiveHandler,      app_did_become_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_resign_active,    "appSetWillResignActive",                     app_will_resign_active,    actionUIAppSetWillResignActiveHandler,     app_will_resign_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_did_resign_active,     "appSetDidResignActive",                     app_did_resign_active,     actionUIAppSetDidResignActiveHandler,      app_did_resign_active_bridge)
APP_LIFECYCLE_SETTER(node_app_set_will_terminate,        "appSetWillTerminate",                     app_will_terminate,        actionUIAppSetWillTerminateHandler,        app_will_terminate_bridge)

static napi_value node_app_set_should_terminate(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "appSetShouldTerminate")) return NULL;
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->app_should_terminate) != napi_ok) return NULL;
    actionUIAppSetShouldTerminateHandler(g_state->app_should_terminate != NULL
                                         ? app_should_terminate_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_window_will_close(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "appSetWindowWillClose")) return NULL;
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 1) { napi_throw_error(env, NULL, "expected 1 argument"); return NULL; }
    if (store_callback(env, argv[0], &g_state->app_window_will_close) != napi_ok) return NULL;
    actionUIAppSetWindowWillCloseHandler(g_state->app_window_will_close != NULL
                                          ? app_window_will_close_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_window_will_present(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "appSetWindowWillPresent")) return NULL;
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
    if (!require_main_env(env, "setLogger")) return NULL;
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
    if (!require_main_env(env, "registerActionHandler")) return NULL;
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
    if (!require_main_env(env, "unregisterActionHandler")) return NULL;
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
    if (!require_main_env(env, "setDefaultActionHandler")) return NULL;
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

// MARK: - N-API: Element Selection

static napi_value node_select_element_row_by_index(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, index = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_int64(env, argv[2], &index);
    napi_value result;
    napi_get_boolean(env, actionUISelectElementRowByIndex(uuid, viewID, index), &result);
    return result;
}

static napi_value node_select_element_row_with_content(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], text[4096]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0, column = -1;
    napi_get_value_int64(env, argv[1], &viewID);
    napi_get_value_string_utf8(env, argv[2], text, sizeof(text), &len);
    napi_get_value_int64(env, argv[3], &column);
    napi_value result;
    napi_create_int64(env, actionUISelectElementRowWithContent(uuid, viewID, text, column), &result);
    return result;
}

static napi_value node_clear_element_selection(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    int64_t viewID = 0;
    napi_get_value_int64(env, argv[1], &viewID);
    actionUIClearElementSelection(uuid, viewID);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
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

// MARK: - N-API: Runtime Structural Mutations

/*
 * insert_element(windowUUID, parentID, json, container, position, positionParam)
 *   container         : string | null  — pass null to auto-derive
 *   position     : int  — 0=append, 1=prepend, 2=at(index), 3=before(siblingID), 4=after(siblingID)
 *   positionParam: int  — index for position=2; siblingID for position=3/4; ignored otherwise
 * Returns: Number — inserted element id, or throws on failure.
 */
static napi_value node_insert_element(napi_env env, napi_callback_info info) {
    size_t argc = 6; napi_value argv[6];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 3) { napi_throw_error(env, NULL, "insert_element requires (windowUUID, parentID, json[, container, position, positionParam])"); return NULL; }

    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);

    int64_t parentID;
    napi_get_value_int64(env, argv[1], &parentID);

    char json[65536];
    napi_get_value_string_utf8(env, argv[2], json, sizeof(json), &len);

    const char* container_ptr = NULL; char container_buf[256];
    if (argc >= 4) {
        napi_valuetype vtype; napi_typeof(env, argv[3], &vtype);
        if (vtype == napi_string) { napi_get_value_string_utf8(env, argv[3], container_buf, sizeof(container_buf), &len); container_ptr = container_buf; }
    }

    int64_t position = 0, positionParam = 0;
    if (argc >= 5) napi_get_value_int64(env, argv[4], &position);
    if (argc >= 6) napi_get_value_int64(env, argv[5], &positionParam);

    int64_t inserted_id = actionUIInsertElement(uuid, parentID, json, container_ptr,
                                                (ActionUIInsertPosition)position, positionParam);
    // Only -1 is a failure: an element without an "id" gets an auto-assigned id of -2 or below.
    if (inserted_id == -1) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUIInsertElement failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    napi_value result; napi_create_int64(env, inserted_id, &result); return result;
}

/*
 * insert_row(windowUUID, parentID, json, container, position, positionIndex)
 *   json         : string — JSON array of cell objects
 *   container         : string | null
 *   position     : int  — 0=append, 1=prepend, 2=at(index). 3/4 invalid for rows.
 *   positionIndex: int  — row index for position=2; ignored otherwise
 * Returns: Array<Number> — inserted cell ids, or throws on failure.
 */
static napi_value node_insert_row(napi_env env, napi_callback_info info) {
    size_t argc = 6; napi_value argv[6];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 3) { napi_throw_error(env, NULL, "insert_row requires (windowUUID, parentID, json[, container, position, positionIndex])"); return NULL; }

    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);

    int64_t parentID;
    napi_get_value_int64(env, argv[1], &parentID);

    char json[65536];
    napi_get_value_string_utf8(env, argv[2], json, sizeof(json), &len);

    const char* container_ptr = NULL; char container_buf[256];
    if (argc >= 4) {
        napi_valuetype vtype; napi_typeof(env, argv[3], &vtype);
        if (vtype == napi_string) { napi_get_value_string_utf8(env, argv[3], container_buf, sizeof(container_buf), &len); container_ptr = container_buf; }
    }

    int64_t position = 0, positionIndex = 0;
    if (argc >= 5) napi_get_value_int64(env, argv[4], &position);
    if (argc >= 6) napi_get_value_int64(env, argv[5], &positionIndex);

    char* ids_json = actionUIInsertRow(uuid, parentID, json, container_ptr,
                                       (ActionUIInsertPosition)position, positionIndex);
    if (ids_json == NULL) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUIInsertRow failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    /* Parse the JSON array string "[5,6,...]" into a JS array */
    napi_value global, json_obj, parse_fn, json_str, result;
    napi_get_global(env, &global);
    napi_get_named_property(env, global, "JSON", &json_obj);
    napi_get_named_property(env, json_obj, "parse", &parse_fn);
    napi_create_string_utf8(env, ids_json, NAPI_AUTO_LENGTH, &json_str);
    actionUIFreeString(ids_json);
    napi_call_function(env, json_obj, parse_fn, 1, &json_str, &result);
    return result;
}

/*
 * remove_element(windowUUID, viewID)
 * Returns: true on success, or throws on failure.
 */
static napi_value node_remove_element(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 2) { napi_throw_error(env, NULL, "remove_element requires (windowUUID, viewID)"); return NULL; }

    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);

    int64_t viewID;
    napi_get_value_int64(env, argv[1], &viewID);

    bool ok = actionUIRemoveElement(uuid, viewID);
    if (!ok) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUIRemoveElement failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    napi_value t; napi_get_boolean(env, true, &t); return t;
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

/* presentToast(windowUUID, message[, duration[, actionTitle[, actionID]]]) -> true
   duration is a number (seconds, default 4.0); actionTitle/actionID are optional
   strings supplied together to add one inline action button. */
static napi_value node_present_toast(napi_env env, napi_callback_info info) {
    size_t argc = 5; napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128], message[4096]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid,    sizeof(uuid),    &len);
    napi_get_value_string_utf8(env, argv[1], message, sizeof(message), &len);

    double duration = 4.0;
    if (argc >= 3) {
        napi_valuetype vtype; napi_typeof(env, argv[2], &vtype);
        if (vtype == napi_number) {
            napi_get_value_double(env, argv[2], &duration);
        }
    }
    char actionTitle[512]; const char* actionTitle_ptr = NULL;
    if (argc >= 4) {
        napi_valuetype vtype; napi_typeof(env, argv[3], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[3], actionTitle, sizeof(actionTitle), &len);
            actionTitle_ptr = actionTitle;
        }
    }
    char actionID[512]; const char* actionID_ptr = NULL;
    if (argc >= 5) {
        napi_valuetype vtype; napi_typeof(env, argv[4], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[4], actionID, sizeof(actionID), &len);
            actionID_ptr = actionID;
        }
    }
    (void)actionUIPresentToast(uuid, message, duration, actionTitle_ptr, actionID_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_dismiss_toast(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    actionUIDismissToast(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: UI Loading

// Apple only: this hands out a native view; the Linux library has no such function.
#if defined(__APPLE__)

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

#endif // defined(__APPLE__)

// MARK: - N-API: Content Size Limits

/*
 * Returns the size limits of a window's root element content as
 * { minWidth, minHeight, maxWidth, maxHeight }. Flexible axes report a very
 * large maximum; a fixed root frame reports min == max. Throws when the
 * window is unknown, or on Linux not on screen (GTK measures a window it shows).
 */
static napi_value node_get_content_size_limits(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);

    double minW = 0, minH = 0, maxW = 0, maxH = 0;
    if (!actionUIGetContentSizeLimits(uuid, &minW, &minH, &maxW, &maxH)) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUIGetContentSizeLimits failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }

    napi_value result, v;
    napi_create_object(env, &result);
    napi_create_double(env, minW, &v); napi_set_named_property(env, result, "minWidth",  v);
    napi_create_double(env, minH, &v); napi_set_named_property(env, result, "minHeight", v);
    napi_create_double(env, maxW, &v); napi_set_named_property(env, result, "maxWidth",  v);
    napi_create_double(env, maxH, &v); napi_set_named_property(env, result, "maxHeight", v);
    return result;
}

// MARK: - N-API: Window Model

/*
 * removeWindow(windowUUID)
 * Forgets the window's model (loaded description, element values and states)
 * once the host is done with the window. An unknown windowUUID is ignored.
 */
static napi_value node_remove_window(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char uuid[128]; size_t len;
    napi_get_value_string_utf8(env, argv[0], uuid, sizeof(uuid), &len);
    actionUIRemoveWindow(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - CFRunLoop / libuv Integration (GLib on Linux, below)
//
// [NSApp run] blocks the main thread inside CFRunLoop.  We install:
//   1. A CFRunLoopObserver — pumps libuv before every source pass and before
//      every sleep; arms the timer when libuv has a future timer deadline.
//   2. A CFRunLoopTimer, armed at libuv's next timer deadline.
//   3. A CFRunLoopSource, signaled by a thread watching libuv's backend descriptor
//      (uv_io_watch) when libuv has I/O, that pumps libuv.
//
// Microtask / nextTick drain (Fix for the "5 s stall"):
//   uv_run(NOWAIT) runs libuv callbacks but provides no InternalCallbackScope,
//   so process.nextTick and Promise microtasks queued inside those callbacks
//   (e.g. undici's TCP connect scheduled via nextTick) stagnate until the
//   next callback that happens to open a scope.  After every uv_run we call
//   a pre-stored no-op JS function through napi_make_callback; closing that
//   scope drains both queues — the same drain Node.js's SpinEventLoop
//   normally provides.  Wrapping uv_run itself in napi_open_callback_scope
//   is NOT safe: libuv callbacks call napi_make_callback internally, which
//   creates nested scopes that trigger assertions in Node.js internals.
//   A NULL async_context in napi_make_callback produces a trivial scope that
//   may skip the drain, so a real napi_async_context is required.
//
// uv_backend_timeout() returns:
//   0   → work ready now → prevent CFRunLoop from sleeping
//   N>0 → next timer in N ms → arm CFRunLoopTimer to that deadline
//   -1  → active I/O handles, no timer → the I/O watcher (uv_io_watch) wakes us

static bool                 s_app_running = false;   /* appRun is on the stack */
#if defined(__APPLE__)
static CFRunLoopObserverRef s_cf_observer = NULL;
static CFRunLoopTimerRef    s_cf_timer    = NULL;
/* The I/O watcher (uv_io_watch): a thread that waits for libuv's backend descriptor to become
 * readable, and the main run loop's source it signals. */
static CFRunLoopSourceRef   s_uv_io_src    = NULL;
static pthread_t            s_uv_io_thread;
static bool                 s_uv_io_thread_running = false;
static int                  s_uv_io_stop[2] = { -1, -1 };   /* a byte written to [1] ends it */
static dispatch_semaphore_t s_uv_io_pumped = NULL;          /* signaled after each I/O pump */
/* Note: kqueue code disabled */
#if KQUEUE_ENABLED
static CFFileDescriptorRef  s_kq_fdref    = NULL;
static CFRunLoopSourceRef   s_kq_src      = NULL;
#endif // KQUEUE_ENABLED
#endif // defined(__APPLE__)

/* Queued via process.nextTick from inside noop_callback.
 * If this fires before napi_make_callback returns to C, the drain works. */
#if ACTIONUI_DIAGNOSTIC
static napi_value diag_sentinel(napi_env env, napi_callback_info info) {
    static uint32_t s_sentinel_count = 0;
    DIAGNOSTIC_LOG("[actionui:diag] sentinel nextTick #%u RAN — tick drain IS working\n",
            ++s_sentinel_count);
    napi_value u; napi_get_undefined(env, &u); return u;
}

static napi_value noop_callback(napi_env env, napi_callback_info info) {
    static uint32_t s_noop_count = 0;
    uint32_t n = ++s_noop_count;
    if (n <= 5 && g_state &&
        g_state->diag_nexttick_ref != NULL && g_state->diag_sentinel_ref != NULL) {
        napi_value nexttick, sentinel, global, result;
        napi_get_reference_value(env, g_state->diag_nexttick_ref, &nexttick);
        napi_get_reference_value(env, g_state->diag_sentinel_ref, &sentinel);
        napi_get_global(env, &global);
        napi_call_function(env, global, nexttick, 1, &sentinel, &result);
        DIAGNOSTIC_LOG("[actionui:diag] noop#%u: queued sentinel via process.nextTick\n", n);
    }

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}
#endif // ACTIONUI_DIAGNOSTIC

/* Pump one libuv iteration then drain nextTick + microtask queues. */
static void uv_pump(void) {
    if (g_state == NULL || g_state->uv_loop == NULL) return;

    int alive   = uv_loop_alive(g_state->uv_loop);
    int timeout = uv_backend_timeout(g_state->uv_loop);
    (void)alive; (void)timeout;  /* reserved for future debugging */

    uv_run(g_state->uv_loop, UV_RUN_NOWAIT);

    napi_env env = g_state->env;
    bool has_exception = false;
    napi_is_exception_pending(env, &has_exception);
    if (has_exception) {
        return;
    }

    napi_handle_scope hs;
    if (napi_open_handle_scope(env, &hs) != napi_ok) {
        return;
    }

    napi_value global;
    napi_get_global(env, &global);

    /* This is critical: call _tickCallback directly via napi_call_function. */
    if (g_state->process_tick_ref != NULL) {
        napi_value ptick, result;
        napi_status s = napi_get_reference_value(env, g_state->process_tick_ref, &ptick);
        if (s == napi_ok) {
            napi_call_function(env, global, ptick, 0, NULL, &result);
            bool exc = false;
            napi_is_exception_pending(env, &exc);
            if (exc) {
                napi_value _ignored;
                napi_get_and_clear_last_exception(env, &_ignored);
            }
        }
    }

#if ACTIONUI_DIAGNOSTIC
    /* napi_make_callback with a no-op JS function to trigger drain. */
    if (g_state->drain_fn_ref != NULL) {
        napi_value fn, result;
        if (napi_get_reference_value(env, g_state->drain_fn_ref, &fn) == napi_ok) {
            napi_make_callback(env, g_state->async_ctx, global, fn, 0, NULL, &result);
        }
    }
#endif // ACTIONUI_DIAGNOSTIC

    napi_close_handle_scope(env, hs);
}

/* A referenced, never-sent handle that keeps libuv's loop alive while appRun runs. Without one,
 * a loop with nothing in it reports uv_backend_timeout 0 ("work ready now"), so the pump woke the
 * run loop over and over (100% of a CPU, measured on both platforms), and uv_run(NOWAIT) returned
 * at once without polling for I/O. */
static uv_async_t* s_uv_keepalive = NULL;

static void free_uv_handle(uv_handle_t* handle) {
    free(handle);
}

static void uv_keepalive_start(uv_loop_t* loop) {
    s_uv_keepalive = (uv_async_t*)calloc(1, sizeof(uv_async_t));
    if (s_uv_keepalive != NULL && uv_async_init(loop, s_uv_keepalive, NULL) != 0) {
        free(s_uv_keepalive);
        s_uv_keepalive = NULL;
    }
}

static void uv_keepalive_stop(void) {
    if (s_uv_keepalive != NULL) {
        /* Freed by its close callback, on Node's next loop iteration after appRun returns. */
        uv_close((uv_handle_t*)s_uv_keepalive, free_uv_handle);
        s_uv_keepalive = NULL;
    }
}

/* libuv's next timer in ms (0: work ready now; -1: none), from a fresh clock: uv_backend_timeout
 * reads the loop's cached time, which only uv_run refreshes, so a timer started from a UI callback
 * would otherwise always look N ms away. */
static int uv_next_timeout(uv_loop_t* loop) {
    uv_update_time(loop);
    return uv_backend_timeout(loop);
}

#if defined(__APPLE__)

static void uv_cf_timer_cb(CFRunLoopTimerRef timer, void* info) {
    uv_pump();
    /* Disarm: the kCFRunLoopBeforeWaiting observer will re-arm as needed. */
    if (timer != NULL) {
        CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + 1e10);
    }
}

/* kqueue source callback: fires when libuv's backend fd is readable (I/O ready). */
#if KQUEUE_ENABLED
static void uv_kq_callback(CFFileDescriptorRef fdref,
                           CFOptionFlags       callbackTypes,
                           void*               info) {
   uv_pump();
   /* Re-arm so CFRunLoop keeps watching for the next I/O readiness event.
    * CFFileDescriptor callbacks are one-shot and must be re-enabled. */
   CFFileDescriptorEnableCallBacks(fdref, kCFFileDescriptorReadCallBack);
}
#endif // KQUEUE_ENABLED

/* I/O wakeup. libuv's kqueue descriptor (uv_backend_fd) turns readable when libuv has I/O to
 * handle; nothing else wakes the run loop for it, so with no libuv timer pending a child's output
 * or a socket's data waited for some unrelated event (two writes 1 s and 3 s after launch arrived
 * together after 5 s, measured). A thread polls the descriptor, which reports readiness without
 * taking libuv's events, and signals a run loop source; the main thread pumps libuv in that
 * source's callout, between AppKit's own callouts. The thread then waits for the pump, since the
 * descriptor stays readable until libuv has read it. This is the CFFileDescriptor source's job
 * done without its callbacks, which ran on any kqueue activity (see uv_pump_setup). An I/O callback
 * that runs a modal (an alert, a file panel) holds its pump until the modal ends, so meanwhile the
 * thread waits and I/O runs only when the observer pumps. */
static void* uv_io_watch(void* info) {
    int backend_fd = (int)(intptr_t)info;
    for (;;) {
        struct pollfd fds[2] = {
            { .fd = backend_fd, .events = POLLIN, .revents = 0 },
            { .fd = s_uv_io_stop[0], .events = POLLIN, .revents = 0 },
        };
        int ready = poll(fds, 2, -1);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0 || fds[1].revents != 0) break;
        if (fds[0].revents != 0) {
            CFRunLoopSourceSignal(s_uv_io_src);
            CFRunLoopWakeUp(CFRunLoopGetMain());
            dispatch_semaphore_wait(s_uv_io_pumped, DISPATCH_TIME_FOREVER);
        }
    }
    return NULL;
}

static void uv_io_perform(void* info) {
    (void)info;
    uv_pump();
    dispatch_semaphore_signal(s_uv_io_pumped);
}

static void uv_io_watch_start(uv_loop_t* loop) {
    int backend_fd = uv_backend_fd(loop);
    if (backend_fd < 0 || pipe(s_uv_io_stop) != 0) return;
    /* Not inherited by child processes (libuv's fork path keeps every descriptor without it). */
    fcntl(s_uv_io_stop[0], F_SETFD, FD_CLOEXEC);
    fcntl(s_uv_io_stop[1], F_SETFD, FD_CLOEXEC);
    s_uv_io_pumped = dispatch_semaphore_create(0);
    CFRunLoopSourceContext context = { 0 };
    context.perform = uv_io_perform;
    s_uv_io_src = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetMain(), s_uv_io_src, kCFRunLoopCommonModes);
    s_uv_io_thread_running =
        pthread_create(&s_uv_io_thread, NULL, uv_io_watch, (void*)(intptr_t)backend_fd) == 0;
}

static void uv_io_watch_stop(void) {
    if (s_uv_io_thread_running) {
        char byte = 0;
        ssize_t written = write(s_uv_io_stop[1], &byte, 1);
        (void)written;
        dispatch_semaphore_signal(s_uv_io_pumped);   /* in case it waits for a pump */
        pthread_join(s_uv_io_thread, NULL);
        s_uv_io_thread_running = false;
    }
    if (s_uv_io_src != NULL) {
        CFRunLoopSourceInvalidate(s_uv_io_src);
        CFRelease(s_uv_io_src);
        s_uv_io_src = NULL;
    }
    if (s_uv_io_pumped != NULL) {
        dispatch_release(s_uv_io_pumped);
        s_uv_io_pumped = NULL;
    }
    for (int i = 0; i < 2; i++) {
        if (s_uv_io_stop[i] >= 0) close(s_uv_io_stop[i]);
        s_uv_io_stop[i] = -1;
    }
}

static void uv_cf_observer_cb(CFRunLoopObserverRef obs,
                               CFRunLoopActivity   activity,
                               void*               info) {
    uv_pump();
    if (g_state == NULL || g_state->uv_loop == NULL) return;
    if (activity != kCFRunLoopBeforeWaiting) return;

    int timeout_ms = uv_next_timeout(g_state->uv_loop);
    if (timeout_ms == 0) {
        /* libuv has more work ready; prevent CFRunLoop from sleeping. */
        CFRunLoopWakeUp(CFRunLoopGetMain());
    } else if (timeout_ms > 0 && s_cf_timer != NULL) {
        double secs = timeout_ms / 1000.0;
        if (secs > 0.5) secs = 0.5;  /* cap: stay responsive to AppKit events */
        CFRunLoopTimerSetNextFireDate(s_cf_timer,
                                      CFAbsoluteTimeGetCurrent() + secs);
    }
    /* timeout_ms == -1: no timer deadline; the I/O watcher wakes the run loop for I/O. */
}

static void uv_pump_setup(uv_loop_t* loop) {
    if (loop != NULL) {
        uv_keepalive_start(loop);
        uv_io_watch_start(loop);
    }

    /* CFRunLoopObserver: pumps libuv before sources, before waiting, and after waiting.
     * This is sufficient to keep Node.js async work running interleaved with AppKit. */
    CFRunLoopObserverContext obs_ctx = { 0, NULL, NULL, NULL, NULL };
    s_cf_observer = CFRunLoopObserverCreate(
        kCFAllocatorDefault,
        kCFRunLoopBeforeSources | kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting,
        true,  /* repeats */
        0,     /* order */
        uv_cf_observer_cb, &obs_ctx);
    CFRunLoopAddObserver(CFRunLoopGetMain(), s_cf_observer, kCFRunLoopCommonModes);

    /* CFRunLoopTimer: fires at libuv's next timer deadline to wake CFRunLoop
     * when libuv has pending timers. It repeats, with an interval that never comes: CFRunLoop
     * invalidates a one-shot timer once it has fired, after which re-arming it did nothing, and
     * a later libuv timer waited for some other event to wake the run loop (a 1500 ms timeout
     * fired after about 5 s, measured). */
    CFRunLoopTimerContext timer_ctx = { 0, NULL, NULL, NULL, NULL };
    s_cf_timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 1e10,  /* disarmed initially */
        1e10,  /* repeating, so it stays valid; re-armed manually */
        0, 0,
        uv_cf_timer_cb, &timer_ctx);
    CFRunLoopAddTimer(CFRunLoopGetMain(), s_cf_timer, kCFRunLoopCommonModes);

    /* DISABLED: kqueue source for immediate I/O wakeup.
     *
     * Wrapping uv_backend_fd() (libuv's kqueue fd on macOS) as a
     * CFFileDescriptor source was supposed to wake CFRunLoop immediately
     * when any I/O is ready, replacing the ~50ms polling interval.
     *
     * HOWEVER, this causes spurious re-entrant uv_pump() calls that
     * interfere with AppKit's normal event delivery, specifically:
     *   - TextField: pressing Return clears the text field
     *   - Other text controls may exhibit similar glitches
     *
     * The problem is the kqueue callback fires on ANY kqueue activity,
     * including internal libuv state changes, not just real I/O readiness.
     * This causes uv_pump() to run mid-delivery of AppKit events,
     * corrupting the responder chain.
     *
     * The I/O watcher (uv_io_watch) does this job instead: its thread only signals a run loop
     * source, whose callout pumps libuv between AppKit's callouts, as the observer does.
     *
     * If you reinstate this, expect text edit fields to misbehave.
     */

#if KQUEUE_ENABLED
    if (loop != NULL) {
        int backend_fd = uv_backend_fd(loop);
        fprintf(stderr, "[actionui:diag] uv_backend_fd=%d — kqueue source %s\n",
                backend_fd, backend_fd >= 0 ? "WILL be installed" : "NOT available");
        if (backend_fd >= 0) {
            CFFileDescriptorContext kq_ctx = { 0, NULL, NULL, NULL, NULL };
            s_kq_fdref = CFFileDescriptorCreate(
                kCFAllocatorDefault, backend_fd, false, uv_kq_callback, &kq_ctx);
            CFFileDescriptorEnableCallBacks(s_kq_fdref, kCFFileDescriptorReadCallBack);
            s_kq_src = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, s_kq_fdref, 0);
            CFRunLoopAddSource(CFRunLoopGetMain(), s_kq_src, kCFRunLoopCommonModes);
        }
    }
#endif // KQUEUE_ENABLED
}

static void uv_pump_teardown(void) {

#if KQUEUE_ENABLED
    if (s_kq_src != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), s_kq_src, kCFRunLoopCommonModes);
        CFRelease(s_kq_src);
        s_kq_src = NULL;
    }
    if (s_kq_fdref != NULL) {
        CFFileDescriptorInvalidate(s_kq_fdref);
        CFRelease(s_kq_fdref);
        s_kq_fdref = NULL;
    }
#endif // KQUEUE_ENABLED

    if (s_cf_observer != NULL) {
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), s_cf_observer, kCFRunLoopCommonModes);
        CFRelease(s_cf_observer);
        s_cf_observer = NULL;
    }
    if (s_cf_timer != NULL) {
        CFRunLoopRemoveTimer(CFRunLoopGetMain(), s_cf_timer, kCFRunLoopCommonModes);
        CFRelease(s_cf_timer);
        s_cf_timer = NULL;
    }
    uv_io_watch_stop();
    uv_keepalive_stop();

    if (g_state != NULL) g_state->uv_loop = NULL;
}

#else // GLib: actionUIAppRun blocks in the GTK main loop, which runs the default main context

/* A GLib source over libuv's loop, the usual way to run libuv inside GLib. GLib polls libuv's
 * backend file descriptor (an epoll descriptor, readable when libuv has I/O to handle) with its
 * own, sleeps no longer than libuv's next timer (prepare), and dispatches the source when
 * either is due: one libuv iteration and the nextTick/microtask drain (uv_pump). Prepare runs
 * before every sleep, so work a JS callback queued meanwhile is seen at once. The source is
 * dispatched by the main loop between GTK's own sources, never inside one, so it cannot run in
 * the middle of an event's delivery (what made the kqueue source above misbehave on macOS).
 * libuv reads its cached loop time in uv_backend_timeout, and only uv_run refreshes it, so
 * prepare and check refresh it first: otherwise a timer started from a GTK callback stays N ms
 * away forever and never fires (measured). A referenced uv_async_t keeps the loop alive while
 * appRun runs: with no referenced handle, uv_backend_timeout returns 0 (the source spun at 100%
 * of a CPU, measured), and uv_run(NOWAIT) does nothing at all, so a readable backend descriptor
 * would never be drained. */
typedef struct {
    GSource  source;
    gpointer backend_tag;   /* libuv's backend descriptor, as added to the source */
} UvSource;

static GSource* s_uv_source = NULL;

static gboolean uv_source_prepare(GSource* source, gint* timeout) {
    (void)source;
    if (g_state == NULL || g_state->uv_loop == NULL) {
        *timeout = -1;
        return FALSE;
    }
    /* 0: work ready now; N > 0: the next timer in N ms; -1: only I/O, which the descriptor wakes. */
    int next = uv_next_timeout(g_state->uv_loop);
    *timeout = next;
    return next == 0;
}

static gboolean uv_source_check(GSource* source) {
    if (g_state == NULL || g_state->uv_loop == NULL) return FALSE;
    UvSource* uv_source = (UvSource*)source;
    if ((g_source_query_unix_fd(source, uv_source->backend_tag) & G_IO_IN) != 0) return TRUE;
    return uv_next_timeout(g_state->uv_loop) == 0;   /* a timer came due */
}

static gboolean uv_source_dispatch(GSource* source, GSourceFunc callback, gpointer user_data) {
    (void)source;
    (void)callback;
    (void)user_data;
    uv_pump();
    return G_SOURCE_CONTINUE;
}

static GSourceFuncs s_uv_source_funcs = {
    .prepare  = uv_source_prepare,
    .check    = uv_source_check,
    .dispatch = uv_source_dispatch,
};

static void uv_pump_setup(uv_loop_t* loop) {
    if (loop == NULL) return;
    uv_keepalive_start(loop);
    GSource* source = g_source_new(&s_uv_source_funcs, sizeof(UvSource));
    ((UvSource*)source)->backend_tag = g_source_add_unix_fd(source, uv_backend_fd(loop), G_IO_IN);
    g_source_attach(source, NULL);   /* the default main context, which GTK's main loop runs */
    s_uv_source = source;
}

static void uv_pump_teardown(void) {
    if (s_uv_source != NULL) {
        g_source_destroy(s_uv_source);
        g_source_unref(s_uv_source);
        s_uv_source = NULL;
    }
    uv_keepalive_stop();
    if (g_state != NULL) g_state->uv_loop = NULL;
}

#endif // defined(__APPLE__)

// MARK: - N-API: App Control

static napi_value node_app_set_name(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char name[512]; size_t len;
    napi_get_value_string_utf8(env, argv[0], name, sizeof(name), &len);
    actionUIAppSetName(name);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_application_id(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char applicationID[512]; size_t len;
    if (argc < 1 || napi_get_value_string_utf8(env, argv[0], applicationID, sizeof(applicationID), &len) != napi_ok) {
        napi_throw_type_error(env, NULL, "appSetApplicationID: expected a string");
        return NULL;
    }
    actionUIAppSetApplicationID(applicationID);
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

static napi_value node_app_set_resource_folder(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    napi_valuetype vtype = napi_undefined;
    if (argc >= 1) napi_typeof(env, argv[0], &vtype);
    if (vtype == napi_null || vtype == napi_undefined) {
        actionUIAppSetResourceFolder(NULL);
    } else {
        char path[4096]; size_t len;
        if (napi_get_value_string_utf8(env, argv[0], path, sizeof(path), &len) != napi_ok) {
            napi_throw_type_error(env, NULL, "appSetResourceFolder: expected a string or null");
            return NULL;
        }
        actionUIAppSetResourceFolder(path);
    }
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_run(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "appRun")) return NULL;
    /* A second appRun from inside a callback would set up the pump a second time, leaking the
     * first observer and timer, and tear it down on return while the first run goes on. */
    if (s_app_running) {
        napi_throw_error(env, NULL, "appRun is already running");
        return NULL;
    }
    s_app_running = true;
    uv_loop_t* loop = NULL;
    napi_get_uv_event_loop(env, &loop);
    g_state->uv_loop = loop;
    uv_pump_setup(loop);
    actionUIAppRun();   /* blocks until NSApp terminates */
    uv_pump_teardown();
    s_app_running = false;
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_terminate(napi_env env, napi_callback_info info) {
    actionUIAppTerminate();
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_start_remote_server(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* path_ptr = NULL;   // NULL asks the framework for its per-process default
    char path[1024]; size_t len;
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            napi_get_value_string_utf8(env, argv[0], path, sizeof(path), &len);
            path_ptr = path;
        }
    }
    if (actionUIAppStartRemoteServer(path_ptr) == false) {
        napi_throw_error(env, NULL, "could not start the ActionUI remote server (already "
                                    "running, or the socket could not be created); see the log");
        return NULL;
    }
    const char* endpoint = actionUIAppRemoteServerEndpoint();
    if (endpoint == NULL) {
        napi_throw_error(env, NULL, "the ActionUI remote server reported no endpoint");
        return NULL;
    }
    napi_value ret;
    napi_create_string_utf8(env, endpoint, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value node_app_stop_remote_server(napi_env env, napi_callback_info info) {
    actionUIAppStopRemoteServer();
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_remote_server_endpoint(napi_env env, napi_callback_info info) {
    const char* endpoint = actionUIAppRemoteServerEndpoint();
    if (endpoint == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value ret;
    napi_create_string_utf8(env, endpoint, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

// The token the running server requires, or null when it requires none.
//
// This exists because a Node host cannot find the token any other way: the framework publishes
// it with setenv, and process.env is a snapshot taken at startup that a later setenv never
// reaches. Without this binding, a host that starts the server gets one that demands a token it
// cannot name, and every child it spawns is refused with 1006.
//
// The copying accessor rather than the pointer one. Node calls this only from its own thread, so
// the race the copy closes is not reachable here today - but the pointer form is only safe while
// that stays true, and one binding using the safe call and the other not would be the harder
// thing to keep right. The copy is made under the framework's own lock.
static napi_value node_app_remote_server_token(napi_env env, napi_callback_info info) {
    char token[128];    // the token is 65 bytes; 128 is what the framework documents as enough
    if (actionUIAppRemoteCopyServerToken(token, sizeof(token)) == false) {
        napi_value n; napi_get_null(env, &n); return n;
    }
    napi_value ret;
    napi_create_string_utf8(env, token, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

// Turns on the running server's actionui.performAction (a test harness's click); false when no
// server runs.
static napi_value node_app_remote_enable_perform_action(napi_env env, napi_callback_info info) {
    napi_value ret;
    napi_get_boolean(env, actionUIAppRemoteEnablePerformAction(), &ret);
    return ret;
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

// MARK: - HostSurface (ActionUIHostSurface.h)

/*
 * A HostSurface client: the JS bridge the surface events, frames, input and renders of one binding go to
 * (index.js dispatches them to the delegate's methods). One per actionUIHostSurfaceSetDelegate call, on the
 * main environment.
 *
 * The add-on applies a binding change made inside one of its callbacks after the outermost callback returns,
 * and may still call the outgoing client then (its "destroyed"). So an unbound client is not freed at once:
 * it waits in a retired list, freed on a later main-loop turn when no callback is running (as the Rust crate
 * and the Python module do). All of this is on the main thread.
 */
typedef struct HostSurfaceClient {
    napi_ref bridge;
    struct HostSurfaceClient* next_retired;
} HostSurfaceClient;

typedef struct HostSurfaceBound {
    char* name;
    HostSurfaceClient* client;
    struct HostSurfaceBound* next;
} HostSurfaceBound;

static HostSurfaceBound* s_host_surface_bound = NULL;
static int s_host_surface_depth = 0;
static HostSurfaceClient* s_host_surface_retired = NULL;
static bool s_host_surface_free_scheduled = false;

/* Frees the retired clients, unless a callback is running (its end schedules this again). Main thread. */
static void host_surface_free_retired(void) {
    s_host_surface_free_scheduled = false;
    if (s_host_surface_depth > 0 || s_host_surface_retired == NULL || g_state == NULL) {
        return;
    }
    HostSurfaceClient* client = s_host_surface_retired;
    s_host_surface_retired = NULL;
    while (client != NULL) {
        HostSurfaceClient* next = client->next_retired;
        if (client->bridge != NULL) {
            napi_delete_reference(g_state->env, client->bridge);
        }
        free(client);
        client = next;
    }
}

#if defined(__APPLE__)
static void host_surface_free_retired_dispatch(void* unused) {
    (void)unused;
    host_surface_free_retired();
}
#else
static gboolean host_surface_free_retired_idle(gpointer unused) {
    (void)unused;
    host_surface_free_retired();
    return G_SOURCE_REMOVE;
}
#endif

static void host_surface_schedule_free(void) {
    if (s_host_surface_free_scheduled || s_host_surface_retired == NULL) {
        return;
    }
    s_host_surface_free_scheduled = true;
#if defined(__APPLE__)
    dispatch_async_f(dispatch_get_main_queue(), NULL, host_surface_free_retired_dispatch);
#else
    g_idle_add(host_surface_free_retired_idle, NULL);
#endif
}

static void host_surface_retire(HostSurfaceClient* client) {
    if (client == NULL) {
        return;
    }
    client->next_retired = s_host_surface_retired;
    s_host_surface_retired = client;
    host_surface_schedule_free();
}

/* Records `client` (or, NULL, no client) as the binding of `name`, and returns the client it replaces. False in
 * *stored when the record could not be made (out of memory). */
static HostSurfaceClient* host_surface_replace_bound(const char* name, HostSurfaceClient* client, bool* stored) {
    *stored = true;
    HostSurfaceBound** link = &s_host_surface_bound;
    while (*link != NULL && strcmp((*link)->name, name) != 0) {
        link = &(*link)->next;
    }
    HostSurfaceClient* old = NULL;
    if (*link != NULL) {
        old = (*link)->client;
        if (client != NULL) {
            (*link)->client = client;
        } else {
            HostSurfaceBound* gone = *link;
            *link = gone->next;
            free(gone->name);
            free(gone);
        }
    } else if (client != NULL) {
        HostSurfaceBound* entry = calloc(1, sizeof(HostSurfaceBound));
        char* copy = strdup(name);
        if (entry == NULL || copy == NULL) {
            free(entry);
            free(copy);
            *stored = false;
            return NULL;
        }
        entry->name = copy;
        entry->client = client;
        entry->next = s_host_surface_bound;
        s_host_surface_bound = entry;
    }
    return old;
}

/* Builds the last argument of a bridge call, inside the call's handle scope. */
typedef napi_value (*HostSurfacePayloadBuilder)(napi_env env, const void* data);

/* Calls client->bridge(kind, surfaceId, windowUUID, viewId, payload) through napi_make_callback, so nextTick
 * and Promise queues drain after it. An exception the bridge lets through is reported, never left pending.
 * Called from the add-on on the main thread. */
static void host_surface_call(void* user_data, const char* kind, uint64_t surface_id, const char* window_uuid,
                              int64_t view_id, HostSurfacePayloadBuilder build, const void* data) {
    HostSurfaceClient* client = (HostSurfaceClient*)user_data;
    if (client == NULL || client->bridge == NULL || g_state == NULL) {
        return;
    }
    napi_env env = g_state->env;
    s_host_surface_depth += 1;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);
    napi_value fn;
    if (napi_get_reference_value(env, client->bridge, &fn) == napi_ok && fn != NULL) {
        napi_value argv[5];
        napi_create_string_utf8(env, kind, NAPI_AUTO_LENGTH, &argv[0]);
        napi_create_double(env, (double)surface_id, &argv[1]);
        napi_create_string_utf8(env, window_uuid != NULL ? window_uuid : "", NAPI_AUTO_LENGTH, &argv[2]);
        napi_create_int64(env, view_id, &argv[3]);
        argv[4] = build(env, data);
        napi_value global, result;
        napi_get_global(env, &global);
        napi_make_callback(env, g_state->async_ctx, global, fn, 5, argv, &result);
        bool pending = false;
        napi_is_exception_pending(env, &pending);
        if (pending) {
            napi_value error;
            napi_get_and_clear_last_exception(env, &error);
            napi_value text;
            char message[512] = "";
            if (napi_coerce_to_string(env, error, &text) == napi_ok) {
                napi_get_value_string_utf8(env, text, message, sizeof(message), NULL);
            } else {
                /* A Symbol, or a toString that throws: clear that exception too, or it stays pending and the
                 * next callback's napi_make_callback refuses to run. */
                napi_value ignored;
                napi_get_and_clear_last_exception(env, &ignored);
                snprintf(message, sizeof(message), "(a value that cannot be shown as text)");
            }
            fprintf(stderr, "actionui: a HostSurface delegate threw: %s\n", message);
        }
    }
    napi_close_handle_scope(env, scope);
    s_host_surface_depth -= 1;
    if (s_host_surface_depth == 0) {
        host_surface_schedule_free();
    }
}

static napi_value host_surface_number_array(napi_env env, const double* values, size_t count) {
    napi_value array;
    napi_create_array_with_length(env, count, &array);
    for (size_t index = 0; index < count; index++) {
        napi_value value;
        napi_create_double(env, values[index], &value);
        napi_set_element(env, array, (uint32_t)index, value);
    }
    return array;
}

/* [kind, handle (BigInt) | null, widthPoints, heightPoints, scale, widthPixels, heightPixels] */
static napi_value host_surface_info_payload(napi_env env, const void* data) {
    const AUIHostSurfaceInfo* info = (const AUIHostSurfaceInfo*)data;
    double values[7] = {info->kind, 0, info->widthPoints, info->heightPoints, info->scale, info->widthPixels,
                        info->heightPixels};
    napi_value array = host_surface_number_array(env, values, 7);
    napi_value handle;
    if (info->handle != NULL) {
        napi_create_bigint_uint64(env, (uint64_t)(uintptr_t)info->handle, &handle);
    } else {
        napi_get_null(env, &handle);
    }
    napi_set_element(env, array, 1, handle);
    return array;
}

static napi_value host_surface_number_payload(napi_env env, const void* data) {
    napi_value value;
    napi_create_double(env, *(const double*)data, &value);
    return value;
}

static napi_value host_surface_undefined_payload(napi_env env, const void* data) {
    (void)data;
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

/* The fields of AUIHostInputEvent in order (index.js names them): 16 numbers, then code, text (or null),
 * timestampSeconds. */
static napi_value host_surface_input_payload(napi_env env, const void* data) {
    const AUIHostInputEvent* event = (const AUIHostInputEvent*)data;
    double values[16] = {event->kind, event->pointerType, event->button, (double)event->pointerID, event->modifiers,
                         event->clickCount, event->x, event->y, event->deltaX, event->deltaY, event->scrollUnit,
                         event->scrollPhase, event->pressure, event->tiltX, event->tiltY, event->keyCode};
    napi_value array = host_surface_number_array(env, values, 16);
    napi_value code, text, timestamp;
    napi_create_string_utf8(env, event->code != NULL ? event->code : "", NAPI_AUTO_LENGTH, &code);
    if (event->text != NULL) {
        napi_create_string_utf8(env, event->text, NAPI_AUTO_LENGTH, &text);
    } else {
        napi_get_null(env, &text);
    }
    napi_create_double(env, event->timestampSeconds, &timestamp);
    napi_set_element(env, array, 16, code);
    napi_set_element(env, array, 17, text);
    napi_set_element(env, array, 18, timestamp);
    return array;
}

static const char* host_surface_event_name(int32_t event) {
    switch (event) {
        case AUIHostSurfaceCreated: return "created";
        case AUIHostSurfaceChanged: return "changed";
        case AUIHostSurfaceSuspended: return "suspended";
        case AUIHostSurfaceResumed: return "resumed";
        case AUIHostSurfaceDestroyed: return "destroyed";
        default: return NULL;
    }
}

static void host_surface_on_surface(uint64_t surface_id, const char* window_uuid, int64_t view_id, int32_t event,
                                    const AUIHostSurfaceInfo* info, void* user_data) {
    const char* name = host_surface_event_name(event);
    if (name == NULL || info == NULL) {
        return;
    }
    host_surface_call(user_data, name, surface_id, window_uuid, view_id, host_surface_info_payload, info);
}

static void host_surface_on_frame(uint64_t surface_id, const char* window_uuid, int64_t view_id, double timestamp,
                                  void* user_data) {
    host_surface_call(user_data, "frame", surface_id, window_uuid, view_id, host_surface_number_payload, &timestamp);
}

static void host_surface_on_input(uint64_t surface_id, const char* window_uuid, int64_t view_id,
                                  const AUIHostInputEvent* event, void* user_data) {
    if (event == NULL) {
        return;
    }
    host_surface_call(user_data, "input", surface_id, window_uuid, view_id, host_surface_input_payload, event);
}

static void host_surface_on_render(uint64_t surface_id, const char* window_uuid, int64_t view_id, void* user_data) {
    host_surface_call(user_data, "render", surface_id, window_uuid, view_id, host_surface_undefined_payload, NULL);
}

/* A surface ID argument: a non-negative integer Number (IDs stay far below 2^53). Throws otherwise. */
static bool host_surface_get_id(napi_env env, napi_value value, uint64_t* id) {
    double number = -1;
    if (napi_get_value_double(env, value, &number) != napi_ok || !(number >= 0) || number > 9007199254740991.0 ||
        number != (double)(uint64_t)number) {
        napi_throw_type_error(env, NULL, "the surface ID must be a non-negative integer");
        return false;
    }
    *id = (uint64_t)number;
    return true;
}

static napi_value node_host_surface_register(napi_env env, napi_callback_info info) {
    (void)info;
    if (!require_main_env(env, "hostSurfaceRegister")) return NULL;
    ActionUIHostSurface_register();
    return NULL;
}

/* hostSurfaceSetDelegate(name, bridge|null): binds (or unbinds) the HostSurface elements named name. */
static napi_value node_host_surface_set_delegate(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "hostSurfaceSetDelegate")) return NULL;
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    char name[256];
    size_t length = 0;
    if (argc < 2 || napi_get_value_string_utf8(env, argv[0], name, sizeof(name), &length) != napi_ok ||
        length == 0 || length >= sizeof(name) - 1) {
        napi_throw_type_error(env, NULL, "hostSurfaceSetDelegate(name, bridge|null): name must be a non-empty string");
        return NULL;
    }
    napi_valuetype type;
    napi_typeof(env, argv[1], &type);
    if (type != napi_function && type != napi_null && type != napi_undefined) {
        napi_throw_type_error(env, NULL, "hostSurfaceSetDelegate(name, bridge|null): bridge must be a function or null");
        return NULL;
    }
    HostSurfaceClient* client = NULL;
    if (type == napi_function) {
        client = calloc(1, sizeof(HostSurfaceClient));
        if (client == NULL || napi_create_reference(env, argv[1], 1, &client->bridge) != napi_ok) {
            free(client);
            napi_throw_error(env, NULL, "out of memory");
            return NULL;
        }
    }
    /* The table is updated before the add-on call: the outgoing client's "destroyed", sent during it, may bind
     * the name again, and the add-on applies that change after this one, so it must win here too. */
    bool stored = true;
    HostSurfaceClient* old = host_surface_replace_bound(name, client, &stored);
    if (!stored) {
        napi_delete_reference(env, client->bridge);
        free(client);
        napi_throw_error(env, NULL, "out of memory");
        return NULL;
    }
    AUIHostSurfaceDelegate delegate = {
        .structSize = sizeof(AUIHostSurfaceDelegate),
        .surface = host_surface_on_surface,
        .frame = host_surface_on_frame,
        .input = host_surface_on_input,
        .render = host_surface_on_render,
    };
    bool bound = actionUIHostSurfaceSetDelegate(name, client != NULL ? &delegate : NULL, client);
    if (!bound) {
        /* Nothing happened on the add-on's side: put the old client back. */
        host_surface_replace_bound(name, old, &stored);
        if (client != NULL) {
            napi_delete_reference(env, client->bridge);
            free(client);
        }
        napi_throw_error(env, NULL, "HostSurface refused the delegate");
        return NULL;
    }
    host_surface_retire(old);
    return NULL;
}

static napi_value node_host_surface_request_frame(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    uint64_t id = 0;
    if (argc < 1 || !host_surface_get_id(env, argv[0], &id)) return NULL;
    actionUIHostSurfaceRequestFrame(id);
    return NULL;
}

static napi_value node_host_surface_set_continuous(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    uint64_t id = 0;
    bool on = false;
    if (argc < 2 || !host_surface_get_id(env, argv[0], &id)) return NULL;
    napi_get_value_bool(env, argv[1], &on);
    actionUIHostSurfaceSetContinuous(id, on);
    return NULL;
}

static napi_value node_host_surface_set_cursor(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "hostSurfaceSetCursor")) return NULL;
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    uint64_t id = 0;
    int32_t cursor = 0;
    if (argc < 2 || !host_surface_get_id(env, argv[0], &id)) return NULL;
    napi_get_value_int32(env, argv[1], &cursor);
    napi_value result;
    napi_get_boolean(env, actionUIHostSurfaceSetCursor(id, cursor), &result);
    return result;
}

/* The bytes of a Buffer, a typed array, a DataView or an ArrayBuffer. */
static bool host_surface_get_bytes(napi_env env, napi_value value, const void** data, size_t* length) {
    bool is = false;
    napi_is_typedarray(env, value, &is);
    if (is) {
        napi_typedarray_type type;
        size_t count = 0, offset = 0;
        void* bytes = NULL;
        napi_value buffer;
        if (napi_get_typedarray_info(env, value, &type, &count, &bytes, &buffer, &offset) != napi_ok) return false;
        size_t size = 1;
        switch (type) {
            case napi_int16_array: case napi_uint16_array: size = 2; break;
            case napi_int32_array: case napi_uint32_array: case napi_float32_array: size = 4; break;
            case napi_float64_array: case napi_bigint64_array: case napi_biguint64_array: size = 8; break;
            default: size = 1; break;
        }
        *data = bytes;
        *length = count * size;
        return true;
    }
    napi_is_dataview(env, value, &is);
    if (is) {
        void* bytes = NULL;
        size_t count = 0, offset = 0;
        napi_value buffer;
        if (napi_get_dataview_info(env, value, &count, &bytes, &buffer, &offset) != napi_ok) return false;
        *data = bytes;
        *length = count;
        return true;
    }
    napi_is_arraybuffer(env, value, &is);
    if (is) {
        void* bytes = NULL;
        size_t count = 0;
        if (napi_get_arraybuffer_info(env, value, &bytes, &count) != napi_ok) return false;
        *data = bytes;
        *length = count;
        return true;
    }
    return false;
}

/* hostSurfacePresentPixels(surfaceId, pixels, width, height, stride, format) -> boolean. Any thread (a worker
 * included): the add-on copies the pixels before it returns. */
static napi_value node_host_surface_present_pixels(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value argv[6];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 6) {
        napi_throw_type_error(env, NULL, "hostSurfacePresentPixels(surfaceId, pixels, width, height, stride, format)");
        return NULL;
    }
    uint64_t id = 0;
    if (!host_surface_get_id(env, argv[0], &id)) return NULL;
    const void* bytes = NULL;
    size_t length = 0;
    if (!host_surface_get_bytes(env, argv[1], &bytes, &length)) {
        napi_throw_type_error(env, NULL, "pixels must be a Buffer, a typed array, a DataView or an ArrayBuffer");
        return NULL;
    }
    uint32_t width = 0, height = 0, stride = 0;
    int32_t format = 0;
    napi_get_value_uint32(env, argv[2], &width);
    napi_get_value_uint32(env, argv[3], &height);
    napi_get_value_uint32(env, argv[4], &stride);
    napi_get_value_int32(env, argv[5], &format);
    if (width == 0 || height == 0 || (uint64_t)stride < (uint64_t)width * 4) {
        napi_throw_range_error(env, NULL, "width and height must be positive, and stride at least width * 4");
        return NULL;
    }
    uint64_t needed = (uint64_t)stride * (height - 1) + (uint64_t)width * 4;
    if ((uint64_t)length < needed) {
        char message[160];
        snprintf(message, sizeof(message), "the pixels hold %zu bytes; the frame needs %llu", length,
                 (unsigned long long)needed);
        napi_throw_range_error(env, NULL, message);
        return NULL;
    }
    napi_value result;
    napi_get_boolean(env, actionUIHostSurfacePresentPixels(id, width, height, stride, format, bytes), &result);
    return result;
}

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
#if !defined(__APPLE__)
    if (!s_loaded_on_main_thread) {
        napi_throw_error(env, NULL,
            "actionui was first loaded by a worker thread; on Linux it must be loaded on the main "
            "thread before any worker loads it (require it at the start of the main script)");
        return NULL;
    }
#endif
    ActionUIAddonState* state = (ActionUIAddonState*)calloc(1, sizeof(ActionUIAddonState));
    state->env = env;

    /* action_handlers is a plain JS object used as a string-keyed map. */
    napi_value handlers_obj;
    napi_create_object(env, &handlers_obj);
    napi_create_reference(env, handlers_obj, 1, &state->action_handlers);

    napi_set_instance_data(env, state, addon_state_finalizer, NULL);
    /* Only the main thread's environment can receive ActionUI's callbacks, so only its state is
     * g_state, even when a worker loads the addon first. */
    if (g_state == NULL && is_main_thread()) g_state = state;

    /* Async context for napi_make_callback — a proper context (not NULL)
     * ensures Node.js creates a real InternalCallbackScope that drains
     * process.nextTick and Promise microtask queues on close. */
    napi_value async_resource, async_resource_name;
    napi_create_object(env, &async_resource);
    napi_create_string_utf8(env, "actionui:pump", NAPI_AUTO_LENGTH, &async_resource_name);
    __attribute__((unused)) napi_status ainit_status = napi_async_init(env, async_resource, async_resource_name, &state->async_ctx);
    DIAGNOSTIC_LOG("[actionui:diag] napi_async_init status=%d async_ctx=%p\n",
            (int)ainit_status, (void*)state->async_ctx);

    /* No-op JS function invoked after each uv_run(NOWAIT) to trigger drain. */
#if ACTIONUI_DIAGNOSTIC
    napi_value drain_fn;
    napi_create_function(env, "drain", NAPI_AUTO_LENGTH, noop_callback, NULL, &drain_fn);
    napi_status dref_status = napi_create_reference(env, drain_fn, 1, &state->drain_fn_ref);
    DIAGNOSTIC_LOG("[actionui:diag] drain_fn_ref=%p status=%d\n",
            (void*)state->drain_fn_ref, (int)dref_status);
#endif // ACTIONUI_DIAGNOSTIC

    /* Diagnostic: store process.nextTick + sentinel fn so noop_callback can
     * queue a sentinel nextTick and detect whether the drain actually runs it. */

	napi_value global_val, process_val;
    napi_get_global(env, &global_val);
    napi_get_named_property(env, global_val, "process", &process_val);
    
#if ACTIONUI_DIAGNOSTIC
    napi_value nexttick_val, sentinel_fn;
    napi_get_named_property(env, process_val, "nextTick", &nexttick_val);
    napi_create_reference(env, nexttick_val, 1, &state->diag_nexttick_ref);
    napi_create_function(env, "sentinel", NAPI_AUTO_LENGTH, diag_sentinel, NULL, &sentinel_fn);
    napi_create_reference(env, sentinel_fn, 1, &state->diag_sentinel_ref);
#endif // ACTIONUI_DIAGNOSTIC

    /* Setup process._tickCallback. This is key for functional uv runloop. 
     * In Node.js 19+ this is the working tick drain mechanism. */
    if (state->process_tick_ref == NULL) {
        napi_value ptick;
        napi_valuetype ptick_type;
        if (napi_get_named_property(env, process_val, "_tickCallback", &ptick) == napi_ok) {
            napi_typeof(env, ptick, &ptick_type);
            if (ptick_type == napi_function) {
                napi_create_reference(env, ptick, 1, &state->process_tick_ref);
            }
        }
    }

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

    /* Element selection */
    EXPORT_FN(exports, "selectElementRowByIndex",     node_select_element_row_by_index);
    EXPORT_FN(exports, "selectElementRowWithContent", node_select_element_row_with_content);
    EXPORT_FN(exports, "clearElementSelection",       node_clear_element_selection);

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

    /* Runtime structural mutations */
    EXPORT_FN(exports, "insertElement",            node_insert_element);
    EXPORT_FN(exports, "insertRow",                node_insert_row);
    EXPORT_FN(exports, "removeElement",            node_remove_element);

    /* Modal presentation */
    EXPORT_FN(exports, "presentModal",             node_present_modal);
    EXPORT_FN(exports, "dismissModal",             node_dismiss_modal);
    EXPORT_FN(exports, "presentAlert",             node_present_alert);
    EXPORT_FN(exports, "presentConfirmationDialog",node_present_confirmation_dialog);
    EXPORT_FN(exports, "dismissDialog",            node_dismiss_dialog);
    EXPORT_FN(exports, "presentToast",             node_present_toast);
    EXPORT_FN(exports, "dismissToast",             node_dismiss_toast);

    /* UI loading (Apple only) */
#if defined(__APPLE__)
    EXPORT_FN(exports, "loadHostingController",    node_load_hosting_controller);
#endif
    EXPORT_FN(exports, "getContentSizeLimits",     node_get_content_size_limits);

    /* Window model */
    EXPORT_FN(exports, "removeWindow",             node_remove_window);

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
    EXPORT_FN(exports, "appSetApplicationID",      node_app_set_application_id);
    EXPORT_FN(exports, "appSetIcon",               node_app_set_icon);
    EXPORT_FN(exports, "appSetResourceFolder",     node_app_set_resource_folder);
    EXPORT_FN(exports, "appRun",                   node_app_run);
    EXPORT_FN(exports, "appTerminate",             node_app_terminate);
    EXPORT_FN(exports, "appStartRemoteServer",     node_app_start_remote_server);
    EXPORT_FN(exports, "appStopRemoteServer",      node_app_stop_remote_server);
    EXPORT_FN(exports, "appRemoteServerEndpoint",  node_app_remote_server_endpoint);
    EXPORT_FN(exports, "appRemoteServerToken",     node_app_remote_server_token);
    EXPORT_FN(exports, "appRemoteEnablePerformAction", node_app_remote_enable_perform_action);
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

    /* HostSurface (ActionUIHostSurface.h) */
    EXPORT_FN(exports, "hostSurfaceRegister",       node_host_surface_register);
    EXPORT_FN(exports, "hostSurfaceSetDelegate",    node_host_surface_set_delegate);
    EXPORT_FN(exports, "hostSurfaceRequestFrame",   node_host_surface_request_frame);
    EXPORT_FN(exports, "hostSurfaceSetContinuous",  node_host_surface_set_continuous);
    EXPORT_FN(exports, "hostSurfaceSetCursor",      node_host_surface_set_cursor);
    EXPORT_FN(exports, "hostSurfacePresentPixels",  node_host_surface_present_pixels);
    EXPORT_INT(exports, "HOST_SURFACE_METAL_LAYER",   AUIHostSurfaceMetalLayer);
    EXPORT_INT(exports, "HOST_SURFACE_NATIVE_WINDOW", AUIHostSurfaceANativeWindow);
    EXPORT_INT(exports, "HOST_SURFACE_GL_AREA",       AUIHostSurfaceGLArea);
    EXPORT_INT(exports, "HOST_SURFACE_FRAME_SINK",    AUIHostSurfaceFrameSink);
    EXPORT_INT(exports, "PIXEL_BGRA8_PREMULTIPLIED",  AUIHostPixelBGRA8Premultiplied);
    EXPORT_INT(exports, "PIXEL_RGBA8_PREMULTIPLIED",  AUIHostPixelRGBA8Premultiplied);
    EXPORT_INT(exports, "PIXEL_BGRX8",                AUIHostPixelBGRX8);
    EXPORT_INT(exports, "PIXEL_RGBX8",                AUIHostPixelRGBX8);

    return exports;
}

NAPI_MODULE(actionui, Init)

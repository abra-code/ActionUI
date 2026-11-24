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

#if !defined(__APPLE__) && !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE   /* gettid, before the first system header */
#endif

#include <node_api.h>
#include <uv.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#if defined(_WIN32)
#include <windows.h>   /* after uv.h, which brings winsock2.h first */
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#elif !defined(_WIN32)
#include <glib.h>
#endif
#include <ActionUICAdapter/ActionUIC.h>
#include <ActionUIAppKitApplication/ActionUIApp.h>
#include <ActionUIHostSurface/ActionUIHostSurface.h>
#include "actionui_uv_pump.h"

/* Whether the calling thread is ActionUI's main thread: the one its main queue runs on (the C
 * adapter's answer, the same on every platform). */
static bool is_main_thread(void) {
    return actionUIIsMainThread();
}

#if defined(_WIN32)
/* Windows: whether an Init ran, and whether the first was the main environment's (the one on libuv's default loop).
 * Init refuses all others then, as Linux's note_loading_thread does: ActionUI's main queue may belong to the thread
 * that loaded ActionUI.dll. */
static bool s_first_init_seen = false;
static bool s_loaded_on_main_thread = false;
#endif

#if !defined(__APPLE__) && !defined(_WIN32)
/* Linux: the libdispatch inside libActionUI.so binds its main queue to the thread that loads the
 * library, not to the process's main thread (Apple's libdispatch knows the main thread). Loaded
 * first by a worker, ActionUI would take that worker for its main thread: the real main thread's
 * calls would wait for a main queue that only the running application drains (measured: its
 * logger was not called), and one such run crashed. This constructor runs on the loading thread,
 * after libActionUI.so's own; Init refuses the module in every environment when that was not the
 * main thread, so the failure is a clear error instead. It asks the system, not ActionUI, which
 * takes the loading thread for its main one: the main thread's ID is the process ID. */
static bool s_loaded_on_main_thread = false;

__attribute__((constructor))
static void note_loading_thread(void) {
    s_loaded_on_main_thread = gettid() == getpid();
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
    // Trust policy (setTrustPolicy)
    napi_ref trust_callback;
    napi_ref capability_callback;
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
    DELETE_REF(trust_callback)
    DELETE_REF(capability_callback)
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

/* After a call into JavaScript from a native callback: if the function threw, print the error
 * and clear it. A pending exception left behind makes Node-API refuse the next call into
 * JavaScript and is later thrown into an unrelated caller. `who` names the callback. */
static void report_callback_exception(napi_env env, const char* who) {
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    if (!pending) return;
    napi_value error;
    napi_get_and_clear_last_exception(env, &error);
    napi_value text;
    char message[512] = "";
    if (napi_coerce_to_string(env, error, &text) == napi_ok) {
        napi_get_value_string_utf8(env, text, message, sizeof(message), NULL);
    } else {
        /* A Symbol, or a toString that throws: clear that exception too. */
        napi_value ignored;
        napi_get_and_clear_last_exception(env, &ignored);
        snprintf(message, sizeof(message), "(a value that cannot be shown as text)");
    }
    fprintf(stderr, "actionui: %s threw: %s\n", who, message);
}

/* What every bridge calls after its JavaScript ran: reports an exception, and lets libuv see what the code queued. */
static void finish_callback(napi_env env, const char* who) {
    report_callback_exception(env, who);
    actionui_uv_pump_kick();
}

// MARK: - String arguments

/* String arguments are copied to the heap at their real length, so nothing is cut short, and are
 * freed when the variable goes out of scope: declare them with STRING_ARG(name). */
static void free_string_arg(char** string) {
    free(*string);
}
#define STRING_ARG(name) __attribute__((cleanup(free_string_arg))) char* name = NULL

/* Reads a number or boolean argument into *out. A value of another type throws a TypeError naming
 * the argument and returns false; the caller then returns NULL. An optional argument that is
 * undefined (left out) or null keeps *out as it is, as read_optional_string_arg does. */
static bool check_arg_type(napi_env env, napi_value value, napi_valuetype wanted, const char* name,
                           bool optional, bool* present) {
    napi_valuetype type = napi_undefined;
    napi_typeof(env, value, &type);
    *present = !optional || (type != napi_undefined && type != napi_null);
    if (!*present) return true;
    if (type != wanted) {
        char message[160];
        snprintf(message, sizeof(message), "%s must be a %s", name, wanted == napi_boolean ? "boolean" : "number");
        napi_throw_type_error(env, NULL, message);
        return false;
    }
    /* NaN and the infinities are numbers that read as 0 as integers (Number("abc") would act on
     * element 0): refused like a wrong type. A fraction is cut toward zero, as Node-API does. */
    double number = 0.0;
    if (wanted == napi_number && napi_get_value_double(env, value, &number) == napi_ok && !isfinite(number)) {
        char message[160];
        snprintf(message, sizeof(message), "%s must be a finite number", name);
        napi_throw_type_error(env, NULL, message);
        return false;
    }
    return true;
}

static bool read_int64_arg(napi_env env, napi_value value, int64_t* out, const char* name, bool optional) {
    bool present = false;
    if (!check_arg_type(env, value, napi_number, name, optional, &present)) return false;
    if (present && napi_get_value_int64(env, value, out) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a number argument");
        return false;
    }
    return true;
}

static bool read_int32_arg(napi_env env, napi_value value, int32_t* out, const char* name, bool optional) {
    bool present = false;
    if (!check_arg_type(env, value, napi_number, name, optional, &present)) return false;
    if (present && napi_get_value_int32(env, value, out) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a number argument");
        return false;
    }
    return true;
}

static bool read_uint32_arg(napi_env env, napi_value value, uint32_t* out, const char* name, bool optional) {
    bool present = false;
    if (!check_arg_type(env, value, napi_number, name, optional, &present)) return false;
    if (present && napi_get_value_uint32(env, value, out) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a number argument");
        return false;
    }
    return true;
}

static bool read_double_arg(napi_env env, napi_value value, double* out, const char* name, bool optional) {
    bool present = false;
    if (!check_arg_type(env, value, napi_number, name, optional, &present)) return false;
    if (present && napi_get_value_double(env, value, out) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a number argument");
        return false;
    }
    return true;
}

static bool read_bool_arg(napi_env env, napi_value value, bool* out, const char* name, bool optional) {
    bool present = false;
    if (!check_arg_type(env, value, napi_boolean, name, optional, &present)) return false;
    if (present && napi_get_value_bool(env, value, out) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a boolean argument");
        return false;
    }
    return true;
}

/* Copies a required string argument into *out. A value of any other type, including a missing
 * argument (Node-API passes undefined for it), throws a TypeError naming the argument and
 * returns false; the caller then returns NULL. */
static bool read_string_arg(napi_env env, napi_value value, char** out, const char* name) {
    napi_valuetype type = napi_undefined;
    napi_typeof(env, value, &type);
    if (type != napi_string) {
        char message[160];
        snprintf(message, sizeof(message), "%s must be a string", name);
        napi_throw_type_error(env, NULL, message);
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, NULL, 0, &length) != napi_ok) {
        napi_throw_type_error(env, NULL, "could not read a string argument");
        return false;
    }
    char* copy = (char*)malloc(length + 1);
    if (copy == NULL) {
        napi_throw_error(env, NULL, "out of memory");
        return false;
    }
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, copy, length + 1, &copied) != napi_ok) {
        free(copy);
        napi_throw_type_error(env, NULL, "could not read a string argument");
        return false;
    }
    copy[copied] = '\0';
    free(*out);
    *out = copy;
    return true;
}

/* An optional string argument: absent, undefined or null leaves *out NULL; a string is copied as
 * read_string_arg does; any other type throws a TypeError. */
static bool read_optional_string_arg(napi_env env, size_t argc, napi_value* argv, size_t index,
                                     char** out, const char* name) {
    if (index >= argc) return true;
    napi_valuetype type = napi_undefined;
    napi_typeof(env, argv[index], &type);
    if (type == napi_undefined || type == napi_null) return true;
    return read_string_arg(env, argv[index], out, name);
}

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
        finish_callback(env, "an app lifecycle callback");
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
        finish_callback(env, "a window callback");
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
        finish_callback(env, "the logger callback");
    }

    napi_close_handle_scope(env, scope);
}

// MARK: - Trust Policy Bridges

/* trust(sourceJSON, parentOriginJSON|null, byDefault) -> number. Only 1 (ActionUITrustTrusted)
 * means trusted: any other result, or an exception (reported), is less trusted. */
static ActionUITrust trust_callback_bridge(const char* sourceJSON, const char* parentOriginJSON, ActionUITrust byDefault) {
    if (g_state == NULL || g_state->trust_callback == NULL) return byDefault;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);
    ActionUITrust trust = ActionUITrustLessTrusted;
    napi_value fn = NULL;
    if (napi_get_reference_value(env, g_state->trust_callback, &fn) == napi_ok && fn != NULL) {
        napi_value global, result, argv[3];
        napi_get_global(env, &global);
        napi_create_string_utf8(env, sourceJSON, NAPI_AUTO_LENGTH, &argv[0]);
        if (parentOriginJSON != NULL) {
            napi_create_string_utf8(env, parentOriginJSON, NAPI_AUTO_LENGTH, &argv[1]);
        } else {
            napi_get_null(env, &argv[1]);
        }
        napi_create_int32(env, (int32_t)byDefault, &argv[2]);
        if (napi_call_function(env, global, fn, 3, argv, &result) == napi_ok) {
            napi_valuetype type;
            double value = 0;
            if (napi_typeof(env, result, &type) == napi_ok && type == napi_number
                && napi_get_value_double(env, result, &value) == napi_ok && value == (double)ActionUITrustTrusted) {
                trust = ActionUITrustTrusted;
            }
        }
        finish_callback(env, "the trust policy's trust callback");
    }
    napi_close_handle_scope(env, scope);
    return trust;
}

/* allows(capabilityJSON, originJSON, byDefault) -> boolean. Only true allows; an exception
 * (reported) refuses. */
static bool capability_callback_bridge(const char* capabilityJSON, const char* originJSON, bool byDefault) {
    if (g_state == NULL || g_state->capability_callback == NULL) return byDefault;
    napi_env env = g_state->env;
    napi_handle_scope scope;
    napi_open_handle_scope(env, &scope);
    bool allowed = false;
    napi_value fn = NULL;
    if (napi_get_reference_value(env, g_state->capability_callback, &fn) == napi_ok && fn != NULL) {
        napi_value global, result, argv[3];
        napi_get_global(env, &global);
        napi_create_string_utf8(env, capabilityJSON, NAPI_AUTO_LENGTH, &argv[0]);
        napi_create_string_utf8(env, originJSON, NAPI_AUTO_LENGTH, &argv[1]);
        napi_get_boolean(env, byDefault, &argv[2]);
        if (napi_call_function(env, global, fn, 3, argv, &result) == napi_ok) {
            napi_valuetype type;
            bool value = false;
            if (napi_typeof(env, result, &type) == napi_ok && type == napi_boolean
                && napi_get_value_bool(env, result, &value) == napi_ok) {
                allowed = value;
            }
        }
        finish_callback(env, "the trust policy's allows callback");
    }
    napi_close_handle_scope(env, scope);
    return allowed;
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
            /* Only the table's own entries: an action id comes from the document, and an id such
             * as "constructor" or "__defineGetter__" must not reach an inherited function. */
            bool own = false;
            napi_value handler_val;
            if (napi_has_own_property(env, handlers_obj, js_key, &own) == napi_ok && own &&
                napi_get_property(env, handlers_obj, js_key, &handler_val) == napi_ok) {
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
        finish_callback(env, "an action handler");
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
        finish_callback(env, "the should-terminate callback");
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

// MARK: - N-API: Origins and Trust Policy

/* setTrustPolicy(trust|null, allows|null): both are checked before either is stored, so a refused
 * call changes nothing. */
static napi_value node_set_trust_policy(napi_env env, napi_callback_info info) {
    if (!require_main_env(env, "setTrustPolicy")) return NULL;
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (argc < 2) { napi_throw_error(env, NULL, "expected 2 arguments"); return NULL; }
    for (size_t i = 0; i < 2; i++) {
        napi_valuetype type;
        napi_typeof(env, argv[i], &type);
        if (type != napi_null && type != napi_undefined && type != napi_function) {
            napi_throw_type_error(env, NULL, i == 0 ? "trust must be a function or null" : "allows must be a function or null");
            return NULL;
        }
    }
    if (store_callback(env, argv[0], &g_state->trust_callback) != napi_ok) return NULL;
    if (store_callback(env, argv[1], &g_state->capability_callback) != napi_ok) return NULL;
    actionUISetTrustPolicy(g_state->trust_callback != NULL ? trust_callback_bridge : NULL,
                           g_state->capability_callback != NULL ? capability_callback_bridge : NULL);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_get_element_origin_json(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    char* json = actionUIGetElementOrigin(uuid, viewID);
    if (json == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

// MARK: - N-API: Configuration

/* setConfigurationJSON(json): throws with the adapter's message when the configuration refuses it
 * (nothing changed then). Any thread: the configuration is behind a lock. */
static napi_value node_set_configuration_json(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &json, "configurationJSON")) return NULL;
    if (!actionUISetConfigurationJSON(json)) {
        char* err = actionUIGetLastError();
        napi_throw_error(env, NULL, err ? err : "actionUISetConfigurationJSON failed");
        if (err) actionUIFreeString(err);
        return NULL;
    }
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_get_configuration_json(napi_env env, napi_callback_info info) {
    char* json = actionUIGetConfigurationJSON();
    if (json == NULL) { napi_throw_error(env, NULL, "out of memory"); return NULL; }
    napi_value result;
    napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(json);
    return result;
}

static napi_value node_log(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(message);
    if (!read_string_arg(env, argv[0], &message, "message")) return NULL;
    int32_t level = 0;
    if (!read_int32_arg(env, argv[1], &level, "level", true)) return NULL;
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
    STRING_ARG(actionID);
    if (!read_string_arg(env, argv[0], &actionID, "actionID")) return NULL;

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
    STRING_ARG(actionID);
    if (!read_string_arg(env, argv[0], &actionID, "actionID")) return NULL;

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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0, value = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    if (argc >= 4 && !read_int64_arg(env, argv[3], &value, "value", true)) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetIntValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_double_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0; double value = 0.0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    if (argc >= 4 && !read_double_arg(env, argv[3], &value, "value", true)) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetDoubleValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_bool_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0; bool value = false;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    if (argc >= 4 && !read_bool_arg(env, argv[3], &value, "value", true)) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetBoolValue(uuid, viewID, partID, value), &result);
    return result;
}

static napi_value node_set_string_value(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    /* Required: a missing value arrives as undefined and throws. */
    STRING_ARG(value);
    if (!read_string_arg(env, argv[3], &value, "value")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetStringValue(uuid, viewID, partID, value), &result);
    return result;
}

// MARK: - N-API: Element Values — Getters

static napi_value node_get_int_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    int64_t out = 0;
    if (actionUIGetIntValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_create_int64(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_double_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    double out = 0.0;
    if (actionUIGetDoubleValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_create_double(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_bool_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    bool out = false;
    if (actionUIGetBoolValue(uuid, viewID, partID, &out)) {
        napi_value result; napi_get_boolean(env, out, &result); return result;
    }
    napi_value n; napi_get_null(env, &n); return n;
}

static napi_value node_get_string_value(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
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
    STRING_ARG(uuid); STRING_ARG(value);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    if (!read_optional_string_arg(env, argc, argv, 3, &value, "value")) return NULL;
    STRING_ARG(contentType);
    if (!read_optional_string_arg(env, argc, argv, 4, &contentType, "contentType")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementValueString(uuid, viewID, partID, value != NULL ? value : "", contentType), &result);
    return result;
}

static napi_value node_get_value_as_string(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    STRING_ARG(contentType);
    if (!read_optional_string_arg(env, argc, argv, 3, &contentType, "contentType")) return NULL;
    char* val = actionUIGetElementValueString(uuid, viewID, partID, contentType);
    if (val == NULL) { napi_value n; napi_get_null(env, &n); return n; }
    napi_value result;
    napi_create_string_utf8(env, val, NAPI_AUTO_LENGTH, &result);
    actionUIFreeString(val);
    return result;
}

static napi_value node_set_value_from_json(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
    /* Required: a missing value arrives as undefined and throws. */
    if (!read_string_arg(env, argv[3], &json, "json")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementValueJSON(uuid, viewID, partID, json), &result);
    return result;
}

static napi_value node_get_value_as_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, partID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (argc >= 3 && !read_int64_arg(env, argv[2], &partID, "viewPartID", true)) return NULL;
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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    napi_value result;
    napi_create_int64(env, actionUIGetElementColumnCount(uuid, viewID), &result);
    return result;
}

// MARK: - N-API: Element Rows

static napi_value node_get_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    actionUIClearElementRows(uuid, viewID);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_set_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &json, "json")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementRowsJSON(uuid, viewID, json), &result);
    return result;
}

static napi_value node_append_element_rows_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &json, "json")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUIAppendElementRowsJSON(uuid, viewID, json), &result);
    return result;
}

static napi_value node_append_element_text(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    STRING_ARG(text);
    if (!read_string_arg(env, argv[2], &text, "text")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUIAppendElementText(uuid, viewID, text), &result);
    return result;
}

// MARK: - N-API: Element Selection

static napi_value node_select_element_row_by_index(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, index = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_int64_arg(env, argv[2], &index, "index", false)) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISelectElementRowByIndex(uuid, viewID, index), &result);
    return result;
}

static napi_value node_select_element_row_with_content(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(text);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0, column = -1;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &text, "text")) return NULL;
    if (!read_int64_arg(env, argv[3], &column, "column", false)) return NULL;
    napi_value result;
    napi_create_int64(env, actionUISelectElementRowWithContent(uuid, viewID, text, column), &result);
    return result;
}

static napi_value node_clear_element_selection(napi_env env, napi_callback_info info) {
    size_t argc = 2; napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    actionUIClearElementSelection(uuid, viewID);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: Element Properties

static napi_value node_get_element_property_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(name);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &name, "name")) return NULL;
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
    STRING_ARG(uuid); STRING_ARG(name); STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &name, "name")) return NULL;
    if (!read_string_arg(env, argv[3], &json, "json")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementPropertyJSON(uuid, viewID, name, json), &result);
    return result;
}

// MARK: - N-API: Element State

static napi_value node_get_element_state_json(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(key);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &key, "key")) return NULL;
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
    STRING_ARG(uuid); STRING_ARG(key);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &key, "key")) return NULL;
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
    STRING_ARG(uuid); STRING_ARG(key); STRING_ARG(json);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &key, "key")) return NULL;
    if (!read_string_arg(env, argv[3], &json, "json")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementStateJSON(uuid, viewID, key, json), &result);
    return result;
}

static napi_value node_set_element_state_from_string(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(key); STRING_ARG(value);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;
    if (!read_string_arg(env, argv[2], &key, "key")) return NULL;
    if (!read_string_arg(env, argv[3], &value, "value")) return NULL;
    napi_value result;
    napi_get_boolean(env, actionUISetElementStateFromString(uuid, viewID, key, value), &result);
    return result;
}

// MARK: - N-API: Element Info

static napi_value node_get_element_info_json(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
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

    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;

    int64_t parentID = 0;
    if (!read_int64_arg(env, argv[1], &parentID, "parentID", false)) return NULL;

    STRING_ARG(json);
    if (!read_string_arg(env, argv[2], &json, "json")) return NULL;

    STRING_ARG(container);
    if (!read_optional_string_arg(env, argc, argv, 3, &container, "container")) return NULL;
    const char* container_ptr = container;

    int64_t position = 0, positionParam = 0;
    if (argc >= 5 && !read_int64_arg(env, argv[4], &position, "position", true)) return NULL;
    if (argc >= 6 && !read_int64_arg(env, argv[5], &positionParam, "positionParam", true)) return NULL;

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

    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;

    int64_t parentID = 0;
    if (!read_int64_arg(env, argv[1], &parentID, "parentID", false)) return NULL;

    STRING_ARG(json);
    if (!read_string_arg(env, argv[2], &json, "json")) return NULL;

    STRING_ARG(container);
    if (!read_optional_string_arg(env, argc, argv, 3, &container, "container")) return NULL;
    const char* container_ptr = container;

    int64_t position = 0, positionIndex = 0;
    if (argc >= 5 && !read_int64_arg(env, argv[4], &position, "position", true)) return NULL;
    if (argc >= 6 && !read_int64_arg(env, argv[5], &positionIndex, "positionIndex", true)) return NULL;

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

    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;

    int64_t viewID = 0;
    if (!read_int64_arg(env, argv[1], &viewID, "viewID", false)) return NULL;

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
    STRING_ARG(uuid); STRING_ARG(json); STRING_ARG(format); STRING_ARG(style);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    if (!read_string_arg(env, argv[1], &json, "json")) return NULL;
    if (!read_string_arg(env, argv[2], &format, "format")) return NULL;
    if (!read_string_arg(env, argv[3], &style, "style")) return NULL;

    STRING_ARG(dismiss_action);
    if (!read_optional_string_arg(env, argc, argv, 4, &dismiss_action, "dismissActionID")) return NULL;
    const char* dismiss_ptr = dismiss_action;

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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    actionUIDismissModal(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_present_alert(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(title);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    if (!read_string_arg(env, argv[1], &title, "title")) return NULL;

    STRING_ARG(message);
    if (!read_optional_string_arg(env, argc, argv, 2, &message, "message")) return NULL;
    const char* message_ptr = message;
    STRING_ARG(buttons);
    if (!read_optional_string_arg(env, argc, argv, 3, &buttons, "buttons")) return NULL;
    const char* buttons_ptr = buttons;
    (void)actionUIPresentAlert(uuid, title, message_ptr, buttons_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_present_confirmation_dialog(napi_env env, napi_callback_info info) {
    size_t argc = 4; napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(title);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    if (!read_string_arg(env, argv[1], &title, "title")) return NULL;

    STRING_ARG(message);
    if (!read_optional_string_arg(env, argc, argv, 2, &message, "message")) return NULL;
    const char* message_ptr = message;
    STRING_ARG(buttons_buf);
    if (!read_optional_string_arg(env, argc, argv, 3, &buttons_buf, "buttons")) return NULL;
    const char* buttons_ptr = buttons_buf != NULL ? buttons_buf : "[]";
    (void)actionUIPresentConfirmationDialog(uuid, title, message_ptr, buttons_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_dismiss_dialog(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    actionUIDismissDialog(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

/* presentToast(windowUUID, message[, duration[, actionTitle[, actionID]]]) -> true
   duration is a number (seconds, default 4.0); actionTitle/actionID are optional
   strings supplied together to add one inline action button. */
static napi_value node_present_toast(napi_env env, napi_callback_info info) {
    size_t argc = 5; napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid); STRING_ARG(message);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    if (!read_string_arg(env, argv[1], &message, "message")) return NULL;

    double duration = 4.0;
    if (argc >= 3) {
        napi_valuetype vtype; napi_typeof(env, argv[2], &vtype);
        if (vtype == napi_number) {
            napi_get_value_double(env, argv[2], &duration);
        }
    }
    STRING_ARG(actionTitle);
    if (!read_optional_string_arg(env, argc, argv, 3, &actionTitle, "actionTitle")) return NULL;
    const char* actionTitle_ptr = actionTitle;
    STRING_ARG(actionID);
    if (!read_optional_string_arg(env, argc, argv, 4, &actionID, "actionID")) return NULL;
    const char* actionID_ptr = actionID;
    (void)actionUIPresentToast(uuid, message, duration, actionTitle_ptr, actionID_ptr);
    napi_value t; napi_get_boolean(env, true, &t); return t;
}

static napi_value node_dismiss_toast(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    actionUIDismissToast(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - N-API: UI Loading

// Apple only: this hands out a native view; the Linux library has no such function.
#if defined(__APPLE__)

static napi_value node_load_hosting_controller(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(url); STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &url, "url")) return NULL;
    if (!read_string_arg(env, argv[1], &uuid, "windowUUID")) return NULL;
    bool is_content_view = false;
    /* By its truthiness, as JavaScript reads a condition: callers passed 1 and 0 before this
     * argument was checked (1 then read as false). */
    napi_value as_bool;
    if (napi_coerce_to_bool(env, argv[2], &as_bool) == napi_ok) napi_get_value_bool(env, as_bool, &is_content_view);

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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;

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
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    actionUIRemoveWindow(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

// MARK: - libuv Integration
//
// actionUIAppRun blocks the main thread in the platform's UI loop, so Node's own loop does not
// run. Each platform's pump runs libuv from inside that loop (actionui_uv_pump.h): a CFRunLoop
// observer, timer and source on macOS (actionui_uv_pump_apple.c), a GLib source on Linux
// (actionui_uv_pump_glib.c). What they share is here.
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

static bool                 s_app_running = false;   /* appRun is on the stack */

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

uv_loop_t* actionui_uv_loop(void) {
    return g_state != NULL ? g_state->uv_loop : NULL;
}

/* Pump one libuv iteration then drain nextTick + microtask queues. */
void actionui_uv_pump(void) {
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

void actionui_uv_keepalive_start(uv_loop_t* loop) {
    s_uv_keepalive = (uv_async_t*)calloc(1, sizeof(uv_async_t));
    if (s_uv_keepalive != NULL && uv_async_init(loop, s_uv_keepalive, NULL) != 0) {
        free(s_uv_keepalive);
        s_uv_keepalive = NULL;
    }
}

void actionui_uv_keepalive_stop(void) {
    if (s_uv_keepalive != NULL) {
        /* Freed by its close callback, on Node's next loop iteration after appRun returns. */
        uv_close((uv_handle_t*)s_uv_keepalive, free_uv_handle);
        s_uv_keepalive = NULL;
    }
}

/* libuv's next timer in ms (0: work ready now; -1: none), from a fresh clock: uv_backend_timeout
 * reads the loop's cached time, which only uv_run refreshes, so a timer started from a UI callback
 * would otherwise always look N ms away. */
int actionui_uv_next_timeout(uv_loop_t* loop) {
    uv_update_time(loop);
    return uv_backend_timeout(loop);
}

// MARK: - N-API: App Control

static napi_value node_app_set_name(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(name);
    if (!read_string_arg(env, argv[0], &name, "name")) return NULL;
    actionUIAppSetName(name);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_application_id(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(applicationID);
    if (!read_string_arg(env, argv[0], &applicationID, "applicationID")) return NULL;
    actionUIAppSetApplicationID(applicationID);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_set_icon(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(path);
    if (!read_string_arg(env, argv[0], &path, "path")) return NULL;
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
        STRING_ARG(path);
        if (!read_string_arg(env, argv[0], &path, "path")) return NULL;
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
    actionui_uv_pump_setup(loop);
    actionUIAppRun();   /* blocks until NSApp terminates */
    actionui_uv_pump_teardown();
    if (g_state != NULL) g_state->uv_loop = NULL;
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
    STRING_ARG(path);
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            if (!read_string_arg(env, argv[0], &path, "path")) return NULL;
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

// Removes ACTIONUI_REMOTE_TOKEN from the process environment (the token stays valid); false
// when there was nothing to remove.
static napi_value node_app_remote_unexport_token(napi_env env, napi_callback_info info) {
    napi_value ret;
    napi_get_boolean(env, actionUIAppRemoteUnexportToken(), &ret);
    return ret;
}

// A new token under the label, for one child; null when no server runs or the label is empty.
static napi_value node_app_remote_mint_token(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(label);
    if (!read_string_arg(env, argv[0], &label, "label")) return NULL;
    char token[128];    // the token is 65 bytes; 128 is what the framework documents as enough
    if (actionUIAppRemoteMintToken(label, token, sizeof(token)) == false) {
        napi_value n; napi_get_null(env, &n); return n;
    }
    napi_value ret;
    napi_create_string_utf8(env, token, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

// Withdraws every token minted under the label.
static napi_value node_app_remote_revoke_tokens(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(label);
    if (!read_string_arg(env, argv[0], &label, "label")) return NULL;
    actionUIAppRemoteRevokeTokensWithLabel(label);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_load_and_present_window(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(url); STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &url, "url")) return NULL;
    if (!read_string_arg(env, argv[1], &uuid, "windowUUID")) return NULL;

    STRING_ARG(title);
    if (!read_optional_string_arg(env, argc, argv, 2, &title, "title")) return NULL;
    const char* title_ptr = title;
    actionUIAppLoadAndPresentWindow(url, uuid, title_ptr);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_close_window(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    STRING_ARG(uuid);
    if (!read_string_arg(env, argv[0], &uuid, "windowUUID")) return NULL;
    actionUIAppCloseWindow(uuid);
    napi_value undefined; napi_get_undefined(env, &undefined); return undefined;
}

static napi_value node_app_load_menu_bar(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    const char* json_ptr = NULL;
    STRING_ARG(json);
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            if (!read_string_arg(env, argv[0], &json, "json")) return NULL;
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
    STRING_ARG(cfg);
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            if (!read_string_arg(env, argv[0], &cfg, "config")) return NULL;
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
    STRING_ARG(cfg);
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            if (!read_string_arg(env, argv[0], &cfg, "config")) return NULL;
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
    STRING_ARG(cfg);
    if (argc >= 1) {
        napi_valuetype vtype; napi_typeof(env, argv[0], &vtype);
        if (vtype == napi_string) {
            if (!read_string_arg(env, argv[0], &cfg, "config")) return NULL;
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

#if defined(_WIN32)
/* Not in this binding on Windows yet (ActionUI.dll has the element; Python's binding has it there). Registering
 * does nothing (ActionUI.dll registers the element itself); the rest throw. The header's constants are exported as
 * elsewhere, for index.js's names. */
static napi_value host_surface_not_yet(napi_env env) {
    napi_throw_error(env, NULL, "HostSurface is not available on Windows yet");
    return NULL;
}

static napi_value node_host_surface_register(napi_env env, napi_callback_info info) {
    (void)info;
    if (!require_main_env(env, "hostSurfaceRegister")) return NULL;
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value node_host_surface_set_delegate(napi_env env, napi_callback_info info) {
    (void)info;
    if (!require_main_env(env, "hostSurfaceSetDelegate")) return NULL;
    return host_surface_not_yet(env);
}

static napi_value node_host_surface_request_frame(napi_env env, napi_callback_info info) {
    (void)info;
    return host_surface_not_yet(env);
}

static napi_value node_host_surface_set_continuous(napi_env env, napi_callback_info info) {
    (void)info;
    return host_surface_not_yet(env);
}

static napi_value node_host_surface_set_cursor(napi_env env, napi_callback_info info) {
    (void)info;
    if (!require_main_env(env, "hostSurfaceSetCursor")) return NULL;
    return host_surface_not_yet(env);
}

static napi_value node_host_surface_present_pixels(napi_env env, napi_callback_info info) {
    (void)info;
    return host_surface_not_yet(env);
}
#else

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

static void host_surface_free_retired_later(void* unused) {
    (void)unused;
    host_surface_free_retired();
}

static void host_surface_schedule_free(void) {
    if (s_host_surface_free_scheduled || s_host_surface_retired == NULL) {
        return;
    }
    s_host_surface_free_scheduled = true;
    actionUIRunOnMainThread(host_surface_free_retired_later, NULL);
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
        finish_callback(env, "a HostSurface delegate");
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
    if (argc < 2) {
        napi_throw_type_error(env, NULL, "hostSurfaceSetDelegate(name, bridge|null) takes two arguments");
        return NULL;
    }
    STRING_ARG(name);
    if (!read_string_arg(env, argv[0], &name, "name")) return NULL;
    if (name[0] == '\0') {
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
    if (!read_bool_arg(env, argv[1], &on, "continuous", false)) return NULL;
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
    if (!read_int32_arg(env, argv[1], &cursor, "cursor", false)) return NULL;
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
    if (!read_uint32_arg(env, argv[2], &width, "width", false)) return NULL;
    if (!read_uint32_arg(env, argv[3], &height, "height", false)) return NULL;
    if (!read_uint32_arg(env, argv[4], &stride, "stride", false)) return NULL;
    if (!read_int32_arg(env, argv[5], &format, "format", false)) return NULL;
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

#endif  /* !_WIN32 */

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

/* Object.create(null), or NULL when it cannot be made. */
static napi_value create_null_prototype_object(napi_env env) {
    napi_value global, object_ctor, create_fn, null_value, result;
    if (napi_get_global(env, &global) != napi_ok) return NULL;
    if (napi_get_named_property(env, global, "Object", &object_ctor) != napi_ok) return NULL;
    if (napi_get_named_property(env, object_ctor, "create", &create_fn) != napi_ok) return NULL;
    if (napi_get_null(env, &null_value) != napi_ok) return NULL;
    if (napi_call_function(env, object_ctor, create_fn, 1, &null_value, &result) != napi_ok) return NULL;
    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
#if defined(_WIN32)
    /* The main environment runs on libuv's default loop, a worker on a loop of its own. As on Linux, the module
     * must come to the main environment first: ActionUI's main queue belongs to the thread that set it up. */
    uv_loop_t* init_loop = NULL;
    napi_get_uv_event_loop(env, &init_loop);
    if (!s_first_init_seen) {
        s_first_init_seen = true;
        /* Never unloaded, as Linux links it with -z nodelete: a refused worker's exit would otherwise unload it,
         * and ActionUI.dll with it, under their running threads (and forget the refusal). */
        HMODULE self = NULL;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                           (LPCWSTR)(const void*)&s_first_init_seen, &self);
        s_loaded_on_main_thread = init_loop == uv_default_loop();
    }
    if (!s_loaded_on_main_thread) {
        napi_throw_error(env, NULL,
            "actionui was first loaded by a worker thread; on Windows it must be loaded on the main "
            "thread before any worker loads it (require it at the start of the main script)");
        return NULL;
    }
#elif !defined(__APPLE__)
    if (!s_loaded_on_main_thread) {
        napi_throw_error(env, NULL,
            "actionui was first loaded by a worker thread; on Linux it must be loaded on the main "
            "thread before any worker loads it (require it at the start of the main script)");
        return NULL;
    }
#endif
    ActionUIAddonState* state = (ActionUIAddonState*)calloc(1, sizeof(ActionUIAddonState));
    state->env = env;

    /* action_handlers is a JS object used as a string-keyed map. It has no prototype
     * (Object.create(null)), so an action id such as "__proto__" or "constructor" is an ordinary
     * key, never an inherited property or the prototype setter. */
    napi_value handlers_obj = create_null_prototype_object(env);
    if (handlers_obj == NULL) {
        free(state);
        napi_throw_error(env, NULL, "actionui: could not create the action handler table");
        return NULL;
    }
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
    EXPORT_FN(exports, "appendElementText",        node_append_element_text);

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
    EXPORT_FN(exports, "getElementOriginJSON",     node_get_element_origin_json);
    EXPORT_FN(exports, "setTrustPolicy",           node_set_trust_policy);
    EXPORT_FN(exports, "setConfigurationJSON",     node_set_configuration_json);
    EXPORT_FN(exports, "getConfigurationJSON",     node_get_configuration_json);

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
    EXPORT_FN(exports, "appRemoteUnexportToken",   node_app_remote_unexport_token);
    EXPORT_FN(exports, "appRemoteMintToken",       node_app_remote_mint_token);
    EXPORT_FN(exports, "appRemoteRevokeTokens",    node_app_remote_revoke_tokens);
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

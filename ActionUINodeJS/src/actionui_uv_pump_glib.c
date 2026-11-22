/*
 * actionui_uv_pump_glib.c
 * The libuv pump on Linux, where actionUIAppRun blocks in the GTK main loop, which runs GLib's
 * default main context (see actionui_uv_pump.h). binding.gyp compiles this file on Linux only.
 */

#include <uv.h>
#include <glib.h>
#include "actionui_uv_pump.h"

/* The main loop asks libuv before it sleeps (the source's prepare), so nothing needs waking. */
void actionui_uv_pump_kick(void) {}

/* A GLib source over libuv's loop, the usual way to run libuv inside GLib. GLib polls libuv's
 * backend file descriptor (an epoll descriptor, readable when libuv has I/O to handle) with its
 * own, sleeps no longer than libuv's next timer (prepare), and dispatches the source when
 * either is due: one libuv iteration and the nextTick/microtask drain (actionui_uv_pump). Prepare runs
 * before every sleep, so work a JS callback queued meanwhile is seen at once. The source is
 * dispatched by the main loop between GTK's own sources, never inside one, so it cannot run in
 * the middle of an event's delivery (what made the kqueue source misbehave on macOS, see
 * actionui_uv_pump_apple.c).
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
    uv_loop_t* loop = actionui_uv_loop();
    if (loop == NULL) {
        *timeout = -1;
        return FALSE;
    }
    /* 0: work ready now; N > 0: the next timer in N ms; -1: only I/O, which the descriptor wakes. */
    int next = actionui_uv_next_timeout(loop);
    *timeout = next;
    return next == 0;
}

static gboolean uv_source_check(GSource* source) {
    uv_loop_t* loop = actionui_uv_loop();
    if (loop == NULL) return FALSE;
    UvSource* uv_source = (UvSource*)source;
    if ((g_source_query_unix_fd(source, uv_source->backend_tag) & G_IO_IN) != 0) return TRUE;
    return actionui_uv_next_timeout(loop) == 0;   /* a timer came due */
}

static gboolean uv_source_dispatch(GSource* source, GSourceFunc callback, gpointer user_data) {
    (void)source;
    (void)callback;
    (void)user_data;
    actionui_uv_pump();
    return G_SOURCE_CONTINUE;
}

static GSourceFuncs s_uv_source_funcs = {
    .prepare  = uv_source_prepare,
    .check    = uv_source_check,
    .dispatch = uv_source_dispatch,
};

void actionui_uv_pump_setup(uv_loop_t* loop) {
    if (loop == NULL) return;
    actionui_uv_keepalive_start(loop);
    GSource* source = g_source_new(&s_uv_source_funcs, sizeof(UvSource));
    ((UvSource*)source)->backend_tag = g_source_add_unix_fd(source, uv_backend_fd(loop), G_IO_IN);
    g_source_attach(source, NULL);   /* the default main context, which GTK's main loop runs */
    s_uv_source = source;
}

void actionui_uv_pump_teardown(void) {
    if (s_uv_source != NULL) {
        g_source_destroy(s_uv_source);
        g_source_unref(s_uv_source);
        s_uv_source = NULL;
    }
    actionui_uv_keepalive_stop();
}


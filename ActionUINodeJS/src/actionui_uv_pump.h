/*
 * actionui_uv_pump.h
 * How the addon runs Node's libuv loop while appRun blocks in the platform's UI loop.
 *
 * actionui_node.c holds what every platform shares (one libuv iteration with the nextTick and microtask drain,
 * the keepalive handle, the next timer). Each platform starts, stops and wakes the pump its own way:
 * actionui_uv_pump_apple.c, _glib.c and _windows.c, chosen by binding.gyp.
 */

#ifndef ACTIONUI_UV_PUMP_H
#define ACTIONUI_UV_PUMP_H

#include <uv.h>

/* In actionui_node.c, for the platforms' pumps. */

/* The loop appRun runs, NULL when appRun is not running. */
uv_loop_t* actionui_uv_loop(void);

/* One libuv iteration, then the nextTick and microtask drain. On the main thread. */
void actionui_uv_pump(void);

/* libuv's next timer in ms (0: work ready now; -1: none), from a fresh clock. */
int actionui_uv_next_timeout(uv_loop_t* loop);

/* A referenced handle that keeps libuv's loop alive while appRun runs; stopped by the pump's teardown. */
void actionui_uv_keepalive_start(uv_loop_t* loop);
void actionui_uv_keepalive_stop(void);

/* In each platform's pump. */

/* Before actionUIAppRun, with the loop appRun runs; after it returns. */
void actionui_uv_pump_setup(uv_loop_t* loop);
void actionui_uv_pump_teardown(void);

/* After JavaScript ran outside libuv's own iteration (an ActionUI callback): on Windows, wakes the thread that
 * waits for libuv, so work that code started (a timer, setImmediate) is waited for anew. Elsewhere the run loop
 * asks libuv before it sleeps, and this does nothing. */
void actionui_uv_pump_kick(void);

#endif /* ACTIONUI_UV_PUMP_H */

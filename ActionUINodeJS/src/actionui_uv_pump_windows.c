/*
 * actionui_uv_pump_windows.c
 * The libuv pump on Windows, where actionUIAppRun blocks in WinUI's message loop (see actionui_uv_pump.h).
 * binding.gyp compiles this file on Windows only.
 */

#include <uv.h>
#include <windows.h>   /* after uv.h, which brings winsock2.h first */
#include <stdio.h>
#include <ActionUICAdapter/ActionUIC.h>
#include "actionui_uv_pump.h"

/* libuv on Windows waits on an I/O completion port, not a descriptor, so nothing can poll it from the UI loop.
 * As Electron runs Node inside a GUI loop: a thread waits on the port (GetQueuedCompletionStatus) up to libuv's
 * next timer, gives any packet it took back to the port (PostQueuedCompletionStatus: libuv reads its result from
 * the OVERLAPPED, status included), and asks the main thread for one libuv iteration and the nextTick/microtask
 * drain (actionui_uv_pump, through actionUIRunOnMainThread). It waits until that has run before waiting on the port again,
 * so it never takes a packet while libuv runs, and the next wait (libuv's timeout) is read on the main thread
 * after each pump, never from the loop by this thread. JavaScript an ActionUI callback ran (a timer started in a
 * button's action) wakes the thread with a packet that has no OVERLAPPED (actionui_uv_pump_kick), which libuv's own poll
 * skips, so the thread asks for a pump and waits anew with libuv's new timeout. The referenced keepalive handle
 * keeps an empty loop from reporting "work ready now" over and over, as on the other platforms. */
static HANDLE s_uv_iocp = NULL;
static HANDLE s_uv_poll_thread = NULL;
static HANDLE s_uv_pumped = NULL;              /* auto-reset: set by the main thread after each pump */
static volatile LONG s_uv_poll_stop = 0;
static volatile LONG s_uv_poll_timeout = 0;    /* ms (-1: none), from the last pump; 0 at first: pump at once */

void actionui_uv_pump_kick(void) {
    if (s_uv_iocp != NULL && InterlockedCompareExchange(&s_uv_poll_stop, 0, 0) == 0) {
        PostQueuedCompletionStatus(s_uv_iocp, 0, 0, NULL);
    }
}

/* On the main thread, asked for by the poll thread. */
static void uv_win_pump(void* unused) {
    (void)unused;
    if (InterlockedCompareExchange(&s_uv_poll_stop, 0, 0) != 0) return;   /* torn down meanwhile */
    actionui_uv_pump();
    uv_loop_t* loop = actionui_uv_loop();
    LONG next = loop != NULL ? (LONG)actionui_uv_next_timeout(loop) : -1;
    InterlockedExchange(&s_uv_poll_timeout, next);
    SetEvent(s_uv_pumped);
}

static DWORD WINAPI uv_poll_watch(LPVOID unused) {
    (void)unused;
    for (;;) {
        LONG timeout = InterlockedCompareExchange(&s_uv_poll_timeout, 0, 0);
        DWORD bytes = 0;
        ULONG_PTR key = 0;
        OVERLAPPED* overlapped = NULL;
        GetQueuedCompletionStatus(s_uv_iocp, &bytes, &key, &overlapped, timeout < 0 ? INFINITE : (DWORD)timeout);
        if (overlapped != NULL) {
            PostQueuedCompletionStatus(s_uv_iocp, bytes, key, overlapped);   /* libuv's, given back */
        }
        if (InterlockedCompareExchange(&s_uv_poll_stop, 0, 0) != 0) break;
        /* I/O, a timer come due, or a kick: one iteration on the main thread, then wait again. */
        actionUIRunOnMainThread(uv_win_pump, NULL);
        WaitForSingleObject(s_uv_pumped, INFINITE);
        if (InterlockedCompareExchange(&s_uv_poll_stop, 0, 0) != 0) break;
    }
    return 0;
}

void actionui_uv_pump_setup(uv_loop_t* loop) {
    if (loop == NULL) return;
    actionui_uv_keepalive_start(loop);
    InterlockedExchange(&s_uv_poll_stop, 0);
    InterlockedExchange(&s_uv_poll_timeout, 0);
    s_uv_iocp = loop->iocp;
    s_uv_pumped = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (s_uv_iocp == NULL || s_uv_pumped == NULL) {
        fprintf(stderr, "actionui: libuv's loop cannot be watched; Node's timers and I/O wait until appRun returns\n");
        return;
    }
    s_uv_poll_thread = CreateThread(NULL, 0, uv_poll_watch, NULL, 0, NULL);
    if (s_uv_poll_thread == NULL) {
        fprintf(stderr, "actionui: the libuv watcher thread did not start; Node's timers and I/O wait until appRun returns\n");
    }
}

void actionui_uv_pump_teardown(void) {
    InterlockedExchange(&s_uv_poll_stop, 1);
    if (s_uv_poll_thread != NULL) {
        /* Wakes it wherever it waits: on the port, or for a pump that will not come. */
        PostQueuedCompletionStatus(s_uv_iocp, 0, 0, NULL);
        SetEvent(s_uv_pumped);
        WaitForSingleObject(s_uv_poll_thread, INFINITE);
        CloseHandle(s_uv_poll_thread);
        s_uv_poll_thread = NULL;
    }
    /* A pump still queued on the main queue returns at the stop flag without touching the event. */
    if (s_uv_pumped != NULL) {
        CloseHandle(s_uv_pumped);
        s_uv_pumped = NULL;
    }
    s_uv_iocp = NULL;
    actionui_uv_keepalive_stop();
}

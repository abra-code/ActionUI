/*
 * actionui_uv_pump_apple.c
 * The libuv pump on macOS, where actionUIAppRun blocks in [NSApp run], inside the main CFRunLoop
 * (see actionui_uv_pump.h). binding.gyp compiles this file on macOS only.
 *
 * We install:
 *   1. A CFRunLoopObserver - pumps libuv before every source pass and before every sleep; arms the
 *      timer when libuv has a future timer deadline.
 *   2. A CFRunLoopTimer, armed at libuv's next timer deadline.
 *   3. A CFRunLoopSource, signaled by a thread watching libuv's backend descriptor (uv_io_watch)
 *      when libuv has I/O, that pumps libuv.
 *
 * actionui_uv_next_timeout() returns:
 *   0   - work ready now: prevent CFRunLoop from sleeping
 *   N>0 - next timer in N ms: arm the CFRunLoopTimer to that deadline
 *   -1  - active I/O handles, no timer: the I/O watcher (uv_io_watch) wakes us
 */

#include <uv.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include "actionui_uv_pump.h"

/* The run loop asks libuv before it sleeps (the observer), so nothing needs waking. */
void actionui_uv_pump_kick(void) {}

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

static void uv_cf_timer_cb(CFRunLoopTimerRef timer, void* info) {
    actionui_uv_pump();
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
   actionui_uv_pump();
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
 * done without its callbacks, which ran on any kqueue activity (see actionui_uv_pump_setup). An I/O callback
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
    actionui_uv_pump();
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
    actionui_uv_pump();
    uv_loop_t* loop = actionui_uv_loop();
    if (loop == NULL) return;
    if (activity != kCFRunLoopBeforeWaiting) return;

    int timeout_ms = actionui_uv_next_timeout(loop);
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

void actionui_uv_pump_setup(uv_loop_t* loop) {
    if (loop != NULL) {
        actionui_uv_keepalive_start(loop);
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
     * HOWEVER, this causes spurious re-entrant actionui_uv_pump() calls that
     * interfere with AppKit's normal event delivery, specifically:
     *   - TextField: pressing Return clears the text field
     *   - Other text controls may exhibit similar glitches
     *
     * The problem is the kqueue callback fires on ANY kqueue activity,
     * including internal libuv state changes, not just real I/O readiness.
     * This causes actionui_uv_pump() to run mid-delivery of AppKit events,
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

void actionui_uv_pump_teardown(void) {

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
    actionui_uv_keepalive_stop();
}


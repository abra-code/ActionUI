// ActionUIWinUIShim.h - the plain C interface of ActionUI's WinUI 3 shim.
//
// The shim is a small DLL written in C++ with Microsoft's C++/WinRT projection. It puts the parts
// of WinUI 3 (Windows App SDK) that ActionUI uses behind C functions, so Swift (and any other
// language with a C interface) calls WinUI the way the Linux renderer calls GTK.
//
// Conventions:
// - Functions that can fail return bool: true on success. After a failure,
//   actionUIWinUICopyLastError gives a message (per thread).
// - ActionUIWinUIObject is one reference to a WinUI object. A function that returns one gives the
//   caller a reference of its own; actionUIWinUIRelease gives it back. Release every object before
//   actionUIWinUIRun returns: XAML objects must go away on the UI thread while XAML still runs.
// - Strings are UTF-8, NUL-terminated. Sizes and positions are in effective pixels (WinUI's
//   device-independent unit), as doubles.
// - Except where a function says otherwise, call it on the UI thread while actionUIWinUIRun runs.

#ifndef ACTIONUI_WINUI_SHIM_H
#define ACTIONUI_WINUI_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(_WIN32)
#define ACTIONUI_WINUI_API
#elif defined(ACTIONUI_WINUI_SHIM_BUILDING)
#define ACTIONUI_WINUI_API __declspec(dllexport)
#else
#define ACTIONUI_WINUI_API __declspec(dllimport)
#endif

// One reference to a WinUI object (a window, a control, a panel). Opaque.
typedef struct ActionUIWinUIObject ActionUIWinUIObject;

typedef void (*ActionUIWinUICallback)(void *context);
typedef void (*ActionUIWinUICompletion)(void *context, bool succeeded);

// MARK: - Errors

// Copies the calling thread's last error message (UTF-8, NUL-terminated, cut to fit) into
// outMessage. Returns false when outMessage is NULL or outMessageSize is not positive. Any thread.
ACTIONUI_WINUI_API bool actionUIWinUICopyLastError(char *outMessage, ptrdiff_t outMessageSize);

// MARK: - Application

// Attaches the Windows App SDK runtime this shim was built for to the process (the Windows App
// SDK bootstrapper). Call once, before actionUIWinUIRun, on the thread that will run it. Fails when
// that runtime is not installed.
ACTIONUI_WINUI_API bool actionUIWinUIInitialize(void);

// Detaches the runtime again, after actionUIWinUIRun has returned.
ACTIONUI_WINUI_API void actionUIWinUIShutdown(void);

// Starts WinUI on the calling thread, which becomes the UI thread, and blocks until the
// application quits. onLaunched(context) is called on the UI thread once WinUI is ready; create
// the first window there. Returns false when WinUI could not start or onLaunched could not run.
// From Swift, call it on the process's main thread: Swift's main actor is that thread, and the
// shim's callbacks run on the thread that calls this.
ACTIONUI_WINUI_API bool actionUIWinUIRun(ActionUIWinUICallback onLaunched, void *context);

// Ends the application: actionUIWinUIRun returns once the current work is done.
ACTIONUI_WINUI_API void actionUIWinUIQuit(void);

// Calls callback(context) on the UI thread after `milliseconds` (0: as soon as the UI thread is
// free). Once.
ACTIONUI_WINUI_API bool actionUIWinUIPostDelayed(int32_t milliseconds, ActionUIWinUICallback callback,
                                                 void *context);

// Calls onSignaled(context) on the UI thread each time the Win32 event `handle` is signaled, until
// actionUIWinUIRun returns. `handle` must be an auto-reset event: the wait repeats, so a
// manual-reset event that stays signaled would call onSignaled without end. For Swift's main queue: `handle` is dispatch's main-queue event
// (_dispatch_get_main_queue_handle_4CF) and onSignaled drains the queue
// (_dispatch_main_queue_callback_4CF).
ACTIONUI_WINUI_API bool actionUIWinUIWatchHandle(void *handle, ActionUIWinUICallback onSignaled, void *context);

// MARK: - Objects

// Adds a reference (returns `object`) or gives one back. NULL is ignored. Any thread, but the
// last release of a XAML object belongs on the UI thread.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIRetain(ActionUIWinUIObject *object);
ACTIONUI_WINUI_API void actionUIWinUIRelease(ActionUIWinUIObject *object);

// MARK: - Window

// A new window, not shown. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIWindowCreate(void);
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetTitle(ActionUIWinUIObject *window, const char *title);
// The size of the window's content area (inside its frame and title bar).
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetContentSize(ActionUIWinUIObject *window, double width,
                                                          double height);
// Makes `element` the window's content (NULL removes it). The window keeps its own reference.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetContent(ActionUIWinUIObject *window, ActionUIWinUIObject *element);
// Shows the window and brings it to the front.
ACTIONUI_WINUI_API bool actionUIWinUIWindowActivate(ActionUIWinUIObject *window);
ACTIONUI_WINUI_API bool actionUIWinUIWindowClose(ActionUIWinUIObject *window);

// MARK: - Text

// A new TextBlock (read-only text). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUITextBlockCreate(void);
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetText(ActionUIWinUIObject *textBlock, const char *text);
// Whether the text wraps onto more lines when it is offered less width than one line needs (at
// word boundaries, and inside a word that does not fit). A new TextBlock does not wrap.
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetWraps(ActionUIWinUIObject *textBlock, bool wraps);

// MARK: - Events

// A control's event handlers (actionUIWinUIButtonOnClick, ...) take a handler, a context and a
// destroyContext: handler(context) runs on the UI thread each time the event happens, and
// destroyContext(context), when not NULL, runs once the control is gone (on the UI thread, also
// when the last reference goes away on another thread), so the caller can free `context`. When
// registering fails, destroyContext runs at once (after the error is recorded: a destroyContext that
// calls the shim may replace it). At shutdown, when the UI thread's queue no longer takes work, a
// destroyContext due from another thread is dropped (a leak, never a call on the wrong thread).
// Each event says which changes report it: the user's (pointer, keyboard, an accessibility tool)
// and, for some, the shim's own setters too. A handler stays alive while it runs, also when it lets
// go of its own control.

// MARK: - Button

// A new Button showing no content. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIButtonCreate(void);
// Shows `title` as the button's content.
ACTIONUI_WINUI_API bool actionUIWinUIButtonSetTitle(ActionUIWinUIObject *button, const char *title);
// Click: the user clicked the button, pressed it with the keyboard, or an accessibility tool invoked
// it. Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUIButtonOnClick(ActionUIWinUIObject *button, ActionUIWinUICallback handler, void *context,
                                                   ActionUIWinUICallback destroyContext);

// MARK: - Automation

// Operates `element` as an accessibility tool does, through its UI Automation peer: what a screen
// reader or a test drives. Invoke presses a button: its Click handler runs during the call. Fails
// when the element has no peer or the peer cannot be invoked.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationInvoke(ActionUIWinUIObject *element);

// MARK: - Layout

typedef struct ActionUIWinUISize {
    double width;
    double height;
} ActionUIWinUISize;

typedef struct ActionUIWinUIRect {
    double x;
    double y;
    double width;
    double height;
} ActionUIWinUIRect;

// WinUI's two layout passes over a panel, handed to the caller. `panel` is the panel itself,
// borrowed for the call (no reference of its own). Measure: given the size offered (a dimension
// may be infinite), measure the children (actionUIWinUIElementMeasure) and return the size the
// panel wants. Arrange: place every child inside `finalSize` (actionUIWinUIElementArrange).
typedef ActionUIWinUISize (*ActionUIWinUIMeasureCallback)(void *context, ActionUIWinUIObject *panel,
                                                          ActionUIWinUISize available);
typedef void (*ActionUIWinUIArrangeCallback)(void *context, ActionUIWinUIObject *panel, ActionUIWinUISize finalSize);

// A new panel (a WinUI Panel) whose layout is the callbacks'. destroyContext(context), when not
// NULL, is called once the panel is gone (on the UI thread), so the caller can free `context`.
// NULL on failure (and destroyContext is then called at once). destroyContext runs on the UI thread
// also when the last reference goes away on another thread.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIPanelCreate(ActionUIWinUIMeasureCallback measure,
                                                                 ActionUIWinUIArrangeCallback arrange, void *context,
                                                                 ActionUIWinUICallback destroyContext);
// The panel's children, in order. The panel keeps its own reference to each. The count is -1 on
// failure.
ACTIONUI_WINUI_API int32_t actionUIWinUIPanelChildCount(ActionUIWinUIObject *panel);
ACTIONUI_WINUI_API bool actionUIWinUIPanelInsertChild(ActionUIWinUIObject *panel, int32_t index,
                                                      ActionUIWinUIObject *child);
ACTIONUI_WINUI_API bool actionUIWinUIPanelRemoveChild(ActionUIWinUIObject *panel, int32_t index);

// In a measure callback: measures `element` with the size offered and returns the size it wants
// (its DesiredSize). {0, 0} on failure.
ACTIONUI_WINUI_API ActionUIWinUISize actionUIWinUIElementMeasure(ActionUIWinUIObject *element,
                                                                 ActionUIWinUISize available);
// In an arrange callback: places `element` at `frame`, in its parent's coordinates. Fails when the
// position is not finite; a width or height that is not finite, or is negative, becomes 0.
ACTIONUI_WINUI_API bool actionUIWinUIElementArrange(ActionUIWinUIObject *element, ActionUIWinUIRect frame);
// Asks WinUI to measure `element` again (after a change that alters its size).
ACTIONUI_WINUI_API bool actionUIWinUIElementInvalidateMeasure(ActionUIWinUIObject *element);
// Where `element` was last placed: its offset in its parent and its size. {0, 0, 0, 0} on failure.
ACTIONUI_WINUI_API ActionUIWinUIRect actionUIWinUIElementLayoutFrame(ActionUIWinUIObject *element);

// MARK: - Rendering

// Renders `element`, which must be in a window's content (shown or not) and laid out, into a PNG
// file at `path`, at the window's scale. Asynchronous: completion(context, succeeded) is called on
// the UI thread when the file is written or the rendering failed, always after this function has
// returned. Returns false (and never calls completion) when the rendering could not start. Do not
// quit while a rendering is pending: it holds a reference to `element` until it completes.
ACTIONUI_WINUI_API bool actionUIWinUIRenderToPNG(ActionUIWinUIObject *element, const char *path,
                                                 ActionUIWinUICompletion completion, void *context);

#ifdef __cplusplus
}
#endif

#endif /* ACTIONUI_WINUI_SHIM_H */

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
// Makes `element` the window's content (NULL removes it). The window keeps its own reference. The
// content sits on the theme's page background, filling the window's content area.
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
typedef enum ActionUIWinUITextAlignment {
    ActionUIWinUITextLeading = 0,
    ActionUIWinUITextCenter = 1,
    ActionUIWinUITextTrailing = 2,
} ActionUIWinUITextAlignment;
// How the lines of a wrapping text line up in its width (left to right only: leading is the left).
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetAlignment(ActionUIWinUIObject *textBlock, ActionUIWinUITextAlignment alignment);

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
// Shows `content` (an element: a symbol, a panel of an icon and a title) as the button's content; NULL
// shows nothing. The content's text and icons take the button's text color, which changes with its
// state (pointer over, pressed, disabled).
ACTIONUI_WINUI_API bool actionUIWinUIButtonSetContent(ActionUIWinUIObject *button, ActionUIWinUIObject *content);
// Click: the user clicked the button, pressed it with the keyboard, or an accessibility tool invoked
// it. Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUIButtonOnClick(ActionUIWinUIObject *button, ActionUIWinUICallback handler, void *context,
                                                   ActionUIWinUICallback destroyContext);
// A new back button, as NavigationView shows one: WinUI's NavigationBackButtonNormalStyle (the Back
// glyph on a button with no fill until the pointer is over it, 40 by 36), or, when the theme has no such
// style, the same glyph on a borderless button of that size; named "Back" for accessibility tools and
// with a "Back" tooltip. Its click is a Button's (actionUIWinUIButtonOnClick). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIBackButtonCreate(void);

// MARK: - CheckBox

// A new CheckBox, unchecked, showing no title. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUICheckBoxCreate(void);
// Shows `title` beside the box.
ACTIONUI_WINUI_API bool actionUIWinUICheckBoxSetTitle(ActionUIWinUIObject *checkBox, const char *title);
ACTIONUI_WINUI_API bool actionUIWinUICheckBoxSetChecked(ActionUIWinUIObject *checkBox, bool checked);
// Whether it is checked now; false on failure.
ACTIONUI_WINUI_API bool actionUIWinUICheckBoxIsChecked(ActionUIWinUIObject *checkBox);
// Click: the user checked or unchecked it (pointer, keyboard, an accessibility tool), after the
// change. Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUICheckBoxOnClick(ActionUIWinUIObject *checkBox, ActionUIWinUICallback handler, void *context,
                                                     ActionUIWinUICallback destroyContext);

// MARK: - ToggleSwitch

// A new ToggleSwitch, off. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIToggleSwitchCreate(void);
// Shows `title` beside the switch, on and off (in place of WinUI's own "On" and "Off"); NULL: no text,
// and no room kept for one (a switch whose title a Form shows in its label column).
ACTIONUI_WINUI_API bool actionUIWinUIToggleSwitchSetTitle(ActionUIWinUIObject *toggleSwitch, const char *title);
ACTIONUI_WINUI_API bool actionUIWinUIToggleSwitchSetOn(ActionUIWinUIObject *toggleSwitch, bool on);
// Whether it is on now; false on failure.
ACTIONUI_WINUI_API bool actionUIWinUIToggleSwitchIsOn(ActionUIWinUIObject *toggleSwitch);
// Toggled: it turned on or off, by the user and also by actionUIWinUIToggleSwitchSetOn (WinUI
// reports both); compare with the value to tell them apart.
ACTIONUI_WINUI_API bool actionUIWinUIToggleSwitchOnToggled(ActionUIWinUIObject *toggleSwitch, ActionUIWinUICallback handler,
                                                           void *context, ActionUIWinUICallback destroyContext);

// MARK: - Choices (a Picker's controls)

typedef enum ActionUIWinUIChoiceKind {
    // A ComboBox: one item shown, the others in a dropdown list.
    ActionUIWinUIChoiceMenu = 0,
    // A RadioButtons group: a column of radio buttons (actionUIWinUIChoiceSetColumns for a row).
    ActionUIWinUIChoiceRadio = 1,
    // A SelectorBar: the items side by side, one selected (the Windows App SDK's segmented selector).
    ActionUIWinUIChoiceSegments = 2,
} ActionUIWinUIChoiceKind;

// A new choice control of `kind`, with no items. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIChoiceCreate(ActionUIWinUIChoiceKind kind);
// Replaces the items with `titles` (`count` UTF-8 strings), selecting none.
ACTIONUI_WINUI_API bool actionUIWinUIChoiceSetItems(ActionUIWinUIObject *choice, const char *const *titles, int32_t count);
// Selects the item at `index` (from 0); -1, or an index past the items, selects none.
ACTIONUI_WINUI_API bool actionUIWinUIChoiceSetSelectedIndex(ActionUIWinUIObject *choice, int32_t index);
// The selected item's index, -1 when none is (or on failure).
ACTIONUI_WINUI_API int32_t actionUIWinUIChoiceGetSelectedIndex(ActionUIWinUIObject *choice);
// A radio group's number of columns (1: a column; the item count: a row). Ignored by the other kinds.
ACTIONUI_WINUI_API bool actionUIWinUIChoiceSetColumns(ActionUIWinUIObject *choice, int32_t columns);
// A SelectorBar item's icon (an icon element, such as actionUIWinUISymbolCreate's), shown before its
// title; NULL removes it. Fails for the other kinds and for an index past the items.
ACTIONUI_WINUI_API bool actionUIWinUIChoiceSetItemIcon(ActionUIWinUIObject *choice, int32_t index, ActionUIWinUIObject *icon);
// SelectionChanged: the selected item changed, by the user or by actionUIWinUIChoiceSetSelectedIndex
// (callers compare the new selection with what they hold).
ACTIONUI_WINUI_API bool actionUIWinUIChoiceOnSelectionChanged(ActionUIWinUIObject *choice, ActionUIWinUICallback handler,
                                                             void *context, ActionUIWinUICallback destroyContext);

// MARK: - Slider

// A new horizontal Slider over 0...1, continuous, without the value shown beside its thumb. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUISliderCreate(void);
// The range, and the step a dragged thumb snaps to from the minimum (0: continuous), with a tick below
// for each step up to 200 steps; the arrow keys move by the step, else a hundredth of the range. Fails
// when minimum is past maximum.
ACTIONUI_WINUI_API bool actionUIWinUISliderSetRange(ActionUIWinUIObject *slider, double minimum, double maximum, double step);
// Sets the position, when it differs. WinUI keeps it in the range and on a step, and reports the change.
ACTIONUI_WINUI_API bool actionUIWinUISliderSetValue(ActionUIWinUIObject *slider, double value);
// The position; 0 on failure.
ACTIONUI_WINUI_API double actionUIWinUISliderGetValue(ActionUIWinUIObject *slider);
// ValueChanged: the position changed, by the user and also by the setters above, during the call.
ACTIONUI_WINUI_API bool actionUIWinUISliderOnValueChanged(ActionUIWinUIObject *slider, ActionUIWinUICallback handler,
                                                          void *context, ActionUIWinUICallback destroyContext);

// MARK: - Progress (a ProgressView's)

typedef enum ActionUIWinUIProgressKind {
    // A horizontal bar (ProgressBar), as wide as it is given.
    ActionUIWinUIProgressBar = 0,
    // A ring 32 x 32 (ProgressRing): a spinner, or filled to the progress.
    ActionUIWinUIProgressRing = 1,
} ActionUIWinUIProgressKind;

// A new progress indicator, indeterminate (the bar moves, the ring spins). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIProgressCreate(ActionUIWinUIProgressKind kind);
// Shows `value` out of `total` (determinate; fails unless 0 <= value <= total and total > 0), or an
// unknown progress (not determinate: value and total are ignored).
ACTIONUI_WINUI_API bool actionUIWinUIProgressSet(ActionUIWinUIObject *progress, bool determinate, double value, double total);

// MARK: - Gauge drawings (a Gauge's forms WinUI has no control for)

typedef enum ActionUIWinUIGaugeShape {
    // A bar across the width with a dot at the value (4 px line, 8 px dot), centered in the height.
    ActionUIWinUIGaugeBar = 0,
    // An open arc of three quarters, its gap at the bottom, with a dot at the value (6 px line).
    ActionUIWinUIGaugeArc = 1,
    // A full ring filled clockwise from the top (6 px line).
    ActionUIWinUIGaugeRing = 2,
} ActionUIWinUIGaugeShape;

// A new gauge drawing at a fraction of 0, in the accent color over a faint track; it draws itself for
// the size it is arranged at (the arc and the ring as large as fit, centered). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIGaugeDrawingCreate(ActionUIWinUIGaugeShape shape);
// Shows `fraction` (0...1; outside is clamped, not a number is 0) of the gauge filled.
ACTIONUI_WINUI_API bool actionUIWinUIGaugeDrawingSetFraction(ActionUIWinUIObject *drawing, double fraction);

// MARK: - Date and time controls (a DatePicker's)

// Days are local calendar days (Gregorian, the system's time zone); times are minutes after midnight.
typedef enum ActionUIWinUIDateKind {
    // A field showing the day, which opens a calendar (CalendarDatePicker).
    ActionUIWinUIDateField = 0,
    // A month's calendar shown inline (CalendarView), one day selectable.
    ActionUIWinUIDateCalendar = 1,
    // Hour and minute fields (TimePicker).
    ActionUIWinUIDateTime = 2,
} ActionUIWinUIDateKind;

// A new date or time control with nothing picked. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIDateControlCreate(ActionUIWinUIDateKind kind);
// Shows `day` as the picked day of a field or calendar (a calendar shows its month), when another day
// is shown.
ACTIONUI_WINUI_API bool actionUIWinUIDateControlSetDay(ActionUIWinUIObject *control, int32_t year, int32_t month, int32_t day);
// The picked day of a field or calendar; false when none is picked (a calendar's day can be clicked off).
ACTIONUI_WINUI_API bool actionUIWinUIDateControlGetDay(ActionUIWinUIObject *control, int32_t *year, int32_t *month, int32_t *day);
// The first and last days a field or calendar offers; not limited: WinUI's hundred years either side of
// today.
ACTIONUI_WINUI_API bool actionUIWinUIDateControlSetRange(ActionUIWinUIObject *control, bool limited, int32_t startYear,
                                                         int32_t startMonth, int32_t startDay, int32_t endYear,
                                                         int32_t endMonth, int32_t endDay);
// Shows `minutes` after midnight as a time picker's time, when it shows another.
ACTIONUI_WINUI_API bool actionUIWinUIDateControlSetTime(ActionUIWinUIObject *control, int32_t minutes);
// A time picker's time in minutes after midnight; -1 on failure.
ACTIONUI_WINUI_API int32_t actionUIWinUIDateControlGetTime(ActionUIWinUIObject *control);
// Changed: the picked day or time changed, by the user and also by the setters above (callers compare
// with what they set).
ACTIONUI_WINUI_API bool actionUIWinUIDateControlOnChanged(ActionUIWinUIObject *control, ActionUIWinUICallback handler,
                                                          void *context, ActionUIWinUICallback destroyContext);

// MARK: - ListView (a List's rows)

// A new ListView with no items and single selection. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIListCreate(void);
// Removes every item.
ACTIONUI_WINUI_API bool actionUIWinUIListClear(ActionUIWinUIObject *list);
// Adds an item showing `text` (one line in the theme's body font).
ACTIONUI_WINUI_API bool actionUIWinUIListAppendText(ActionUIWinUIObject *list, const char *text);
// Adds an item showing `element` (a child element's box).
ACTIONUI_WINUI_API bool actionUIWinUIListAppendElement(ActionUIWinUIObject *list, ActionUIWinUIObject *element);
// Shows `element` in the item at `index` (from 0) instead of what it showed; an index past the items
// fails. A selected item loses its selection.
ACTIONUI_WINUI_API bool actionUIWinUIListReplaceElement(ActionUIWinUIObject *list, int32_t index, ActionUIWinUIObject *element);
// The element the item at `index` (from 0) shows, a new reference; NULL when there is no such item
// or it shows text. With an element source, the element of row `index` when it is made (in or near
// view) and in the window (NULL when its container does not show it).
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIListCopyItemElement(ActionUIWinUIObject *list, int32_t index);
// Removes the items from `count` on, keeping the first `count`.
ACTIONUI_WINUI_API bool actionUIWinUIListTruncate(ActionUIWinUIObject *list, int32_t count);
// Whether the user can select a row (false: rows show their content and take no selection).
ACTIONUI_WINUI_API bool actionUIWinUIListSetSelectable(ActionUIWinUIObject *list, bool selectable);
// Selects the item at `index` (from 0); -1, or an index past the items, selects none.
ACTIONUI_WINUI_API bool actionUIWinUIListSetSelectedIndex(ActionUIWinUIObject *list, int32_t index);
// The selected item's index, -1 when none is (or on failure).
ACTIONUI_WINUI_API int32_t actionUIWinUIListGetSelectedIndex(ActionUIWinUIObject *list);
// SelectionChanged: the selected row changed, by the user or by actionUIWinUIListSetSelectedIndex (callers
// compare the new selection with what they hold).
ACTIONUI_WINUI_API bool actionUIWinUIListOnSelectionChanged(ActionUIWinUIObject *list, ActionUIWinUICallback handler,
                                                           void *context, ActionUIWinUICallback destroyContext);
// Activated: the user double-clicked a row or pressed Return on it (the selected row is the one).
ACTIONUI_WINUI_API bool actionUIWinUIListOnActivated(ActionUIWinUIObject *list, ActionUIWinUICallback handler,
                                                    void *context, ActionUIWinUICallback destroyContext);

// MARK: - TextBox and PasswordBox

// A new TextBox (one line of editable text), empty. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUITextBoxCreate(void);
// A new PasswordBox (one line of text shown as dots, without a button that shows it), empty. The
// TextBox calls below take it too (its password for the text), except SetMultiline and SetReadOnly.
// NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIPasswordBoxCreate(void);
// Replaces the text, only when it differs (setting it moves the caret).
ACTIONUI_WINUI_API bool actionUIWinUITextBoxSetText(ActionUIWinUIObject *textBox, const char *text);
// The text now, as a new UTF-8 string the caller frees with actionUIWinUIFreeString; NULL on
// failure.
ACTIONUI_WINUI_API char *actionUIWinUITextBoxCopyText(ActionUIWinUIObject *textBox);
ACTIONUI_WINUI_API void actionUIWinUIFreeString(char *string);
// The grayed text shown while the box is empty.
ACTIONUI_WINUI_API bool actionUIWinUITextBoxSetPlaceholder(ActionUIWinUIObject *textBox, const char *placeholder);
// Makes the box an editor of several lines: Return starts a new line, lines wrap at words, and a
// vertical scroll bar shows when the text is taller than the box.
ACTIONUI_WINUI_API bool actionUIWinUITextBoxSetMultiline(ActionUIWinUIObject *textBox);
// Whether the text can only be read, selected and copied (the caret stays, for selecting).
ACTIONUI_WINUI_API bool actionUIWinUITextBoxSetReadOnly(ActionUIWinUIObject *textBox, bool readOnly);
// TextChanged: the text changed, by the user and also by actionUIWinUITextBoxSetText (WinUI reports
// both, a moment after the change); compare with the value to tell them apart.
ACTIONUI_WINUI_API bool actionUIWinUITextBoxOnTextChanged(ActionUIWinUIObject *textBox, ActionUIWinUICallback handler,
                                                          void *context, ActionUIWinUICallback destroyContext);
// Submit: the user pressed Return in the box, or the focus left it (as ending editing commits on
// macOS). Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUITextBoxOnSubmit(ActionUIWinUIObject *textBox, ActionUIWinUICallback handler, void *context,
                                                     ActionUIWinUICallback destroyContext);

// MARK: - Automation

// Operates `element` as an accessibility tool does, through its UI Automation peer: what a screen
// reader or a test drives. Invoke presses a button: its Click handler runs during the call. Fails
// when the element has no peer or the peer cannot be invoked.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationInvoke(ActionUIWinUIObject *element);
// Invokes the `index`th element (from 0) inside `element` that can be invoked, in the visual tree's order
// (a Stepper's minus, then plus); fails when there is none at that index.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationInvokePart(ActionUIWinUIObject *element, int32_t index);
// Selects the `index`th element (from 0) inside `element` that can be selected (UI Automation's
// SelectionItem pattern: a selector bar's items, a list's rows, in the visual tree's order), as a user's
// click does: the control's selection event follows. Fails when there is none at that index.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationSelectPart(ActionUIWinUIObject *element, int32_t index);
// Toggle turns a check box or a toggle switch over (its Click, or Toggled, follows). Fails when
// the element cannot be toggled.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationToggle(ActionUIWinUIObject *element);
// SetValue replaces an element's value through UI Automation's Value pattern (its change event
// follows); one with a RangeValue pattern instead (a Slider) gets `value` read as a number. A TextBox,
// whose peer has no Value pattern in WinUI 2.7, gets its text set directly, which raises TextChanged as
// typing does, and a PasswordBox without one its password. Fails when the element takes no value.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationSetValue(ActionUIWinUIObject *element, const char *value);

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
// Clips `element` and everything in it to the rectangle from its top leading corner of `width` by
// `height` (its own coordinates), as a page is clipped to its area; a negative or not finite width or
// height removes the clip.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetClipSize(ActionUIWinUIObject *element, double width, double height);

// MARK: - Styling

// A color: red, green, blue and alpha, each from 0 to 1 (sRGB).
typedef struct ActionUIWinUIColor {
    double red;
    double green;
    double blue;
    double alpha;
} ActionUIWinUIColor;

typedef enum ActionUIWinUIBrushProperty {
    // What fills a panel's or a control's area behind its content.
    ActionUIWinUIBrushBackground = 0,
    // The color of a text block's or a control's text.
    ActionUIWinUIBrushForeground = 1,
    // What fills a shape's inside, and what draws its outline.
    ActionUIWinUIBrushFill = 2,
    ActionUIWinUIBrushStroke = 3,
} ActionUIWinUIBrushProperty;

// Paints `property` of `element` with `color`; when `color` is NULL, with the theme's brush named
// `themeBrush` (a WinUI theme resource: "TextFillColorSecondaryBrush", "AccentFillColorDefaultBrush",
// ...), as the theme has it when this is called; when both are NULL, the element's own default.
// Fails when the element has no such property or the theme no such brush.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetBrush(ActionUIWinUIObject *element, ActionUIWinUIBrushProperty property,
                                                     const ActionUIWinUIColor *color, const char *themeBrush);

// The font of a text block's or a control's text: `family` (NULL: the theme's, Segoe UI), `size` in
// effective pixels (0 or less: the theme's) and `weight` from 1 to 999 (400 regular, 600 semibold,
// 700 bold; 0: the theme's). Fails when the element shows no text of its own.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetFont(ActionUIWinUIObject *element, const char *family, double size,
                                                    int32_t weight);

// MARK: - State

// How opaque `element` and everything in it is drawn, from 0 (invisible, still laid out) to 1.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetOpacity(ActionUIWinUIObject *element, double opacity);
// Whether the pointer reaches `element` and everything in it (false: clicks and hovering pass through).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetHitTestVisible(ActionUIWinUIObject *element, bool visible);
// Whether a control can be used (false: drawn disabled, no pointer or keyboard focus). Does nothing for an
// element that is not a control (a text block, a panel); WinUI passes a control's state to the controls
// in its content.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetEnabled(ActionUIWinUIObject *element, bool enabled);
// A control's padding, the room between its border and its content, in pixels (a Button's is 11, 5,
// 11, 6 by default); fails for an element that is no Control or a padding that is not a number.
ACTIONUI_WINUI_API bool actionUIWinUIControlSetPadding(ActionUIWinUIObject *control, double leading, double top, double trailing,
                                                       double bottom);
// Whether accessibility tools (UI Automation clients: screen readers) skip `element` (its children are
// not skipped with it: hide each).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAccessibilityHidden(ActionUIWinUIObject *element, bool hidden);

// MARK: - Placement

typedef enum ActionUIWinUIAlignment {
    // Given the whole slot in that axis (WinUI's default).
    ActionUIWinUIAlignStretch = 0,
    // At its own size, at the start of the slot (left, top), its center, or its end.
    ActionUIWinUIAlignStart = 1,
    ActionUIWinUIAlignCenter = 2,
    ActionUIWinUIAlignEnd = 3,
} ActionUIWinUIAlignment;

// How `element` sits in the slot its parent arranges it in, in each axis (a FrameworkElement's
// HorizontalAlignment and VerticalAlignment). The shim's own panels lay their children out
// themselves; this is for WinUI's containers (a ScrollViewer's content).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAlignment(ActionUIWinUIObject *element, ActionUIWinUIAlignment horizontal,
                                                         ActionUIWinUIAlignment vertical);

// MARK: - ScrollViewer

// A new ScrollViewer, with no content, scrolling vertically. No zooming. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIScrollViewerCreate(void);
// Which axes scroll. An axis that does not scroll gives the content the viewer's size in it.
// showsIndicators false scrolls without scroll bars; with them, WinUI shows them while the pointer
// is over the viewer.
ACTIONUI_WINUI_API bool actionUIWinUIScrollViewerSetAxes(ActionUIWinUIObject *scroll, bool horizontal, bool vertical,
                                                         bool showsIndicators);
// Makes `element` the content (NULL removes it). The viewer keeps its own reference.
ACTIONUI_WINUI_API bool actionUIWinUIScrollViewerSetContent(ActionUIWinUIObject *scroll, ActionUIWinUIObject *element);
// Scrolls to the offset (from the content's top left), without animation.
ACTIONUI_WINUI_API bool actionUIWinUIScrollViewerScrollTo(ActionUIWinUIObject *scroll, double x, double y);

typedef struct ActionUIWinUIScrollState {
    double offsetX;
    double offsetY;
    double viewportWidth;
    double viewportHeight;
    double extentWidth;
    double extentHeight;
} ActionUIWinUIScrollState;

// Where the viewer is scrolled to, how much it shows and how large its content is; zeros on
// failure.
ACTIONUI_WINUI_API ActionUIWinUIScrollState actionUIWinUIScrollViewerState(ActionUIWinUIObject *scroll);

// MARK: - Repeater

// An ItemsRepeater: WinUI's virtualizing control, which makes elements only for the items in or near
// the part of it its scroll viewers show (all of them when none bounds it), estimates the others'
// sizes and keeps the scroll position anchored as they change. Its items are numbered rows (0, 1,
// ...); the caller makes each row's element and lets it go when the repeater no longer shows it.

// Makes the element for row `index` and lends it for the call (the repeater takes its own
// reference); NULL when it cannot (an empty element stands for the row). Called during a layout pass,
// on the UI thread.
typedef ActionUIWinUIObject *(*ActionUIWinUIRepeaterMake)(void *context, int32_t index);
// The repeater no longer shows `element` (lent for the call), one make returned: the caller can let
// it go. The element is already out of the repeater.
typedef void (*ActionUIWinUIRepeaterRecycle)(void *context, ActionUIWinUIObject *element);

// A new repeater stacking its rows along the vertical (else horizontal) axis, each given the
// repeater's whole size across, with no rows and no spacing. destroyContext(context), when not NULL,
// is called once the repeater's factory is gone (on the UI thread). NULL on failure (destroyContext
// then called at once).
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIRepeaterCreate(bool vertical, ActionUIWinUIRepeaterMake make,
                                                                    ActionUIWinUIRepeaterRecycle recycle, void *context,
                                                                    ActionUIWinUICallback destroyContext);
// The space between rows, in effective pixels.
ACTIONUI_WINUI_API bool actionUIWinUIRepeaterSetSpacing(ActionUIWinUIObject *repeater, double spacing);
// How many rows the repeater has; -1 on failure.
ACTIONUI_WINUI_API int32_t actionUIWinUIRepeaterCount(ActionUIWinUIObject *repeater);
// Adds a row at the end.
ACTIONUI_WINUI_API bool actionUIWinUIRepeaterAppend(ActionUIWinUIObject *repeater);
// Row `index` changed: its element, when it has one, is recycled and made again.
ACTIONUI_WINUI_API bool actionUIWinUIRepeaterReplace(ActionUIWinUIObject *repeater, int32_t index);
// Removes the rows from `count` on (their elements are recycled).
ACTIONUI_WINUI_API bool actionUIWinUIRepeaterTruncate(ActionUIWinUIObject *repeater, int32_t count);
// Row `index`'s element when the repeater shows it (a new reference); NULL (with an error) when it does not.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIRepeaterCopyElement(ActionUIWinUIObject *repeater, int32_t index);
// Whether `a` and `b` are the same WinUI object, seen through any of its interfaces (a recycled
// element and the one make returned). False when either is NULL.
ACTIONUI_WINUI_API bool actionUIWinUIObjectIsSame(ActionUIWinUIObject *a, ActionUIWinUIObject *b);

// MARK: - ListView element source (a List's rows made as they come into view)

// A ListView can take its rows from an element source instead of its own items: its items are then
// numbered rows (0, 1, ...), and the ListView, which makes containers only for the rows in or near
// view, asks the caller for a row's element when it shows the row (make) and gives it back when it
// recycles the row's container (recycle), as the repeater does. Selection, keyboard and activation
// work on the rows as on items.

// Registers the callbacks; once per ListView, before using the source. destroyContext(context), when
// not NULL, is called once the ListView lets go of them (on the UI thread); on failure at once.
ACTIONUI_WINUI_API bool actionUIWinUIListSetElementSource(ActionUIWinUIObject *list, ActionUIWinUIRepeaterMake make,
                                                          ActionUIWinUIRepeaterRecycle recycle, void *context,
                                                          ActionUIWinUICallback destroyContext);
// Whether the ListView shows the source's rows (true: its items are cleared and the rows start empty;
// false: the rows are gone, without recycle calls, and the items are its own again, empty).
ACTIONUI_WINUI_API bool actionUIWinUIListUseElementSource(ActionUIWinUIObject *list, bool use);
// The source's rows: how many there are (-1 on failure, or when the source is not in use), `count`
// rows added at the end, row `index` changed (its element, when it has one, is recycled and made
// again), the rows from `count` on removed.
ACTIONUI_WINUI_API int32_t actionUIWinUIListSourceCount(ActionUIWinUIObject *list);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceAppend(ActionUIWinUIObject *list, int32_t count);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceReplace(ActionUIWinUIObject *list, int32_t index);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceTruncate(ActionUIWinUIObject *list, int32_t count);
// Scrolls the ListView so that row `index` is in view (rows or items).
ACTIONUI_WINUI_API bool actionUIWinUIListScrollIntoView(ActionUIWinUIObject *list, int32_t index);

// MARK: - Shapes

typedef enum ActionUIWinUIShapeKind {
    ActionUIWinUIShapeRectangle = 0,
    // A rectangle whose corners actionUIWinUIShapeSetCornerRadius rounds.
    ActionUIWinUIShapeRoundedRectangle = 1,
    ActionUIWinUIShapeEllipse = 2,
    // An ellipse, for a circle: arrange it in a square (the shim draws what it is given).
    ActionUIWinUIShapeCircle = 3,
    // A rectangle, for a capsule: round it by half its shorter side (actionUIWinUIShapeSetCornerRadius).
    ActionUIWinUIShapeCapsule = 4,
} ActionUIWinUIShapeKind;

// A new shape that fills the size it is arranged in, with no fill or stroke: paint them with
// actionUIWinUIElementSetBrush (Fill, Stroke). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIShapeCreate(ActionUIWinUIShapeKind kind);
// A rectangle's corner radius (0: square corners). WinUI clamps it to half the width and half the
// height separately, so a radius past half the shorter side makes elliptical corners.
ACTIONUI_WINUI_API bool actionUIWinUIShapeSetCornerRadius(ActionUIWinUIObject *shape, double radius);
// The width of a shape's outline (0: none).
ACTIONUI_WINUI_API bool actionUIWinUIShapeSetStrokeThickness(ActionUIWinUIObject *shape, double thickness);

// MARK: - Images

typedef enum ActionUIWinUIImageStretch {
    // The image's own size (in effective pixels), never scaled.
    ActionUIWinUIImageStretchNone = 0,
    // Scaled to fit the size it is arranged in, keeping its aspect ratio (SwiftUI's fit).
    ActionUIWinUIImageStretchFit = 1,
    // Scaled to cover that size, keeping its aspect ratio, clipped to it (SwiftUI's fill).
    ActionUIWinUIImageStretchFill = 2,
} ActionUIWinUIImageStretch;

// A new Image control showing nothing, at its image's own size. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIImageCreate(void);
// Shows the image file at `path` (absolute, or relative to the current folder): an .svg file as a
// vector image, anything else through WinUI's bitmap decoders (PNG, JPEG, GIF, BMP, TIFF, ICO, and
// what the system's codecs add). A bitmap file is read again at every call, not taken from WinUI's
// cache, so a file rewritten under the same name shows its new image; an SVG file may come from the
// cache (SvgImageSource has no such option). Loading is asynchronous: the image has its size once it
// has loaded, and a file that cannot be decoded shows nothing.
ACTIONUI_WINUI_API bool actionUIWinUIImageSetFile(ActionUIWinUIObject *image, const char *path);
ACTIONUI_WINUI_API bool actionUIWinUIImageSetStretch(ActionUIWinUIObject *image, ActionUIWinUIImageStretch stretch);
// Whether `path` (absolute, or relative to the current folder) names a file that exists and is not a
// folder. False for NULL. Any thread; sets no error.
ACTIONUI_WINUI_API bool actionUIWinUIFileExists(const char *path);

// MARK: - Symbols

// The SF Symbol names ActionUI can draw on Windows are those of its SF Symbols -> Material Symbols
// map, compiled into the shim with their outlines (Scripts/prepare-windows-symbols.py) at each row's
// fill and weight; no font ships. A symbol is an icon element (a PathIcon): it draws in the inherited
// text color (a button's changes with its state), as SF Symbols take the text color, or in the brush
// actionUIWinUIElementSetBrush gives its Foreground.

// Whether the shim was built with the symbol outlines (false: every name is unknown).
ACTIONUI_WINUI_API bool actionUIWinUISymbolsAvailable(void);
// Whether `name` (an SF Symbol name, exact) has an outline.
ACTIONUI_WINUI_API bool actionUIWinUISymbolExists(const char *name);
// A new icon drawing the symbol `name` in a square of actionUIWinUISymbolSetSize's size (the Material
// glyph's em box: the glyph sits inside it with the font's margins). NULL (with an error) when the name
// has no outline.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUISymbolCreate(const char *name);
// The side of the symbol's square, in effective pixels; the outline scales with it.
ACTIONUI_WINUI_API bool actionUIWinUISymbolSetSize(ActionUIWinUIObject *symbol, double size);

// MARK: - Rendering

// Renders `element`, which must be in a window's content (shown or not) and laid out, into a PNG
// file at `path`, at the window's scale. Asynchronous: completion(context, succeeded) is called on
// the UI thread when the file is written or the rendering failed, always after this function has
// returned. Returns false (and never calls completion) when the rendering could not start. Do not
// quit while a rendering is pending: it holds a reference to `element` until it completes.
ACTIONUI_WINUI_API bool actionUIWinUIRenderToPNG(ActionUIWinUIObject *element, const char *path,
                                                 ActionUIWinUICompletion completion, void *context);
// The same for the window's whole content area (its content on the page background), at the
// window's content size: what the window shows below its title bar, the system's own title bar not
// included. Fails when the window has no content yet; the rendering holds a reference to the host
// (the window's content) until it completes.
ACTIONUI_WINUI_API bool actionUIWinUIWindowRenderToPNG(ActionUIWinUIObject *window, const char *path,
                                                       ActionUIWinUICompletion completion, void *context);

#ifdef __cplusplus
}
#endif

#endif /* ACTIONUI_WINUI_SHIM_H */

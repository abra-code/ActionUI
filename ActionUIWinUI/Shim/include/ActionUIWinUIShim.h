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
// that runtime is not installed. Also makes the process per-monitor DPI aware, as WinUI needs, when its
// program declared no DPI awareness of its own (a scripting language's interpreter); call it before the
// process makes any window.
ACTIONUI_WINUI_API bool actionUIWinUIInitialize(void);

// Removes the current folder from the places Windows searches for a DLL loaded by name, for the whole
// process (SetDllDirectoryW with an empty string), so a file named like a DLL in the folder the program
// was started in is never loaded. For a program's own start, before anything loads a DLL: a host's
// process-wide settings are the host's to choose, so ActionUI never calls it on its own.
ACTIONUI_WINUI_API bool actionUIWinUIRemoveCurrentFolderFromDLLSearch(void);

// Detaches the runtime again, after actionUIWinUIRun has returned.
ACTIONUI_WINUI_API void actionUIWinUIShutdown(void);

// Starts WinUI on the calling thread, which becomes the UI thread, and blocks until the
// application quits (actionUIWinUIQuit: closing the last window does not end it). onLaunched(context) is called on the UI thread once WinUI is ready; create
// the first window there. Returns false when WinUI could not start or onLaunched could not run.
// From Swift, call it on the process's main thread: Swift's main actor is that thread, and the
// shim's callbacks run on the thread that calls this.
ACTIONUI_WINUI_API bool actionUIWinUIRun(ActionUIWinUICallback onLaunched, void *context);

// Ends the application: actionUIWinUIRun returns once the current work is done.
ACTIONUI_WINUI_API void actionUIWinUIQuit(void);
// Whether a WinUI Application exists in the process (actionUIWinUIRun's, or a host's own). Sets no error.
ACTIONUI_WINUI_API bool actionUIWinUIApplicationExists(void);

// The folder of the running program (its .exe), as a new UTF-8 string the caller frees with
// actionUIWinUIFreeString; NULL on failure.
ACTIONUI_WINUI_API char *actionUIWinUICopyProgramFolder(void);

// Opens `url` (UTF-8, an absolute URL) with the system: the user's browser, or the app registered for
// its scheme, with the rules XAML applies to a HyperlinkButton's NavigateUri: http and https open at
// once, another app's scheme after Windows' warning, and file: and res: not at all (fails). Returns
// once the request is made, not when the app opens. Fails for text WinUI cannot read as an absolute URL.
ACTIONUI_WINUI_API bool actionUIWinUILaunchURL(const char *url);

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
// A window a host made in its own WinUI application: `inspectable` is its IInspectable (ABI) pointer, lent
// for the call. A new reference; NULL (with an error) when it is no Microsoft.UI.Xaml.Window.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIWindowFromInspectable(void *inspectable);
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetTitle(ActionUIWinUIObject *window, const char *title);
// The size of the window's content area (inside its frame and title bar).
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetContentSize(ActionUIWinUIObject *window, double width,
                                                          double height);
// Whether the user can resize (and maximize) the window; a window is resizable when made.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetResizable(ActionUIWinUIObject *window, bool resizable);
// Makes `element` the window's content (NULL removes it). The window keeps its own reference. The
// content sits on the theme's page background, filling the window's content area.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetContent(ActionUIWinUIObject *window, ActionUIWinUIObject *element);
// Shows the window and brings it to the front.
ACTIONUI_WINUI_API bool actionUIWinUIWindowActivate(ActionUIWinUIObject *window);
// Whether the window is the active one of the UI thread (the one the user works in, when the application
// is in front). Sets no error; false on failure.
ACTIONUI_WINUI_API bool actionUIWinUIWindowIsActive(ActionUIWinUIObject *window);
ACTIONUI_WINUI_API bool actionUIWinUIWindowClose(ActionUIWinUIObject *window);
// `handler` runs on the UI thread when the window has closed (by the user, or actionUIWinUIWindowClose).
ACTIONUI_WINUI_API bool actionUIWinUIWindowOnClosed(ActionUIWinUIObject *window, ActionUIWinUICallback handler, void *context,
                                                    ActionUIWinUICallback destroyContext);
// Asked on the UI thread whether the window may close when the user closes it (its close button, Alt+F4,
// the taskbar; not actionUIWinUIWindowClose): false keeps it open.
typedef bool (*ActionUIWinUIWindowCloseDecider)(void *context);
// `decide` is asked about each close of the window by the user (set one per window: each one set is asked,
// and any false keeps it open). destroyContext(context) runs once the window no longer needs it.
ACTIONUI_WINUI_API bool actionUIWinUIWindowOnClosing(ActionUIWinUIObject *window, ActionUIWinUIWindowCloseDecider decide,
                                                     void *context, ActionUIWinUICallback destroyContext);
// Opens Windows' share sheet for the window showing `element` (DataTransferManager, as a desktop app
// shares), with the web link `url` titled `title` (the sheet needs one) and, for targets that take text
// (a mail's body), `text` (NULL: none); a `url` that is not absolute ("example.com") is no link, so
// only `text` is shared. The sheet is the system's: this returns once it is asked for. Fails when the
// element is in no window.
ACTIONUI_WINUI_API bool actionUIWinUIShareLink(ActionUIWinUIObject *element, const char *url, const char *title, const char *text);
// Drags with the real mouse, as a user does, for tests: through Windows' input queue (SendInput),
// presses the left mouse button (the primary one unless the buttons are swapped) at (fromX, fromY)
// in `element`'s coordinates, moves the pointer to (toX, toY) in steps 15 ms apart, as a hand moves
// (the call takes about 150 ms; sent at once, a drag reads as a far faster flick), and releases it
// there. It moves the user's pointer. `window`, which shows `element`, is brought to the front (it
// fails when Windows refuses, or when the program has no interactive desktop) and must have nothing
// over the points; the element sees the drag as the UI thread runs after this returns.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSendDrag(ActionUIWinUIObject *window, ActionUIWinUIObject *element, double fromX,
                                                    double fromY, double toX, double toY);
// Turns the real mouse wheel, as a user does, for tests: moves the pointer to (x, y) in `element`'s
// coordinates through Windows' input queue, then turns the wheel `notchesY` notches toward the bottom
// (a wheel turned toward the user; negative: toward the top) and the tilt wheel `notchesX` notches toward
// the right, each a whole wheel step (WHEEL_DELTA) or a part of one, at most 100 either way. It
// moves the user's pointer; `window` is brought to the front as actionUIWinUIWindowSendDrag brings it.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSendWheel(ActionUIWinUIObject *window, ActionUIWinUIObject *element, double x,
                                                     double y, double notchesX, double notchesY);

// MARK: - Text

// A new TextBlock (read-only text). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUITextBlockCreate(void);
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetText(ActionUIWinUIObject *textBlock, const char *text);
// Whether the text wraps onto more lines when it is offered less width than one line needs (at
// word boundaries, and inside a word that does not fit). A new TextBlock does not wrap.
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetWraps(ActionUIWinUIObject *textBlock, bool wraps);
// Whether a text that does not fit its width is cut short with an ellipsis (a character boundary), as
// a macOS Table cell's; a new TextBlock is not.
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetTrimmed(ActionUIWinUIObject *textBlock, bool trimmed);
// Whether the user can select `textBlock`'s text with the pointer and copy it (its context menu, Ctrl+C).
ACTIONUI_WINUI_API bool actionUIWinUITextBlockSetSelectable(ActionUIWinUIObject *textBlock, bool selectable);
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

// How a button is drawn (SwiftUI's buttonStyle).
typedef enum ActionUIWinUIButtonStyle {
    // WinUI's standard button (bordered, automatic).
    ActionUIWinUIButtonStyleStandard = 0,
    // No background or border at rest or disabled; the standard button's fill when the pointer is over it
    // or it is pressed (borderless: Windows' subtle button).
    ActionUIWinUIButtonStyleBorderless = 1,
    // As borderless, with no padding, no minimum size and no fill at all: as large as its content
    // (plain).
    ActionUIWinUIButtonStylePlain = 2,
    // WinUI's accent button, filled with the accent color (borderedProminent).
    ActionUIWinUIButtonStyleAccent = 3,
} ActionUIWinUIButtonStyle;
// Draws `button` in `style`, from the standard button (what an earlier style set is undone). Set it
// before the button is first shown: a borderless button's disabled look and a plain button's hover and
// pressed fills are WinUI resources the template reads when it is applied.
ACTIONUI_WINUI_API bool actionUIWinUIButtonSetStyle(ActionUIWinUIObject *button, ActionUIWinUIButtonStyle style);
// Gives `control` (a Control) a minimum height and padding, a control size's box; a negative
// `minHeight` gives it its style's again (both cleared). A ComboBox's dropdown glyph, which keeps the
// box at least 32 pixels tall, takes the minimum height too.
ACTIONUI_WINUI_API bool actionUIWinUIControlSetBox(ActionUIWinUIObject *control, double minHeight, double left,
                                                   double top, double right, double bottom);
// Click: the user clicked the button, pressed it with the keyboard, or an accessibility tool invoked
// it. Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUIButtonOnClick(ActionUIWinUIObject *button, ActionUIWinUICallback handler, void *context,
                                                   ActionUIWinUICallback destroyContext);
// A new back button, as NavigationView shows one: WinUI's NavigationBackButtonNormalStyle (the Back
// glyph on a button with no fill until the pointer is over it, 40 by 36), or, when the theme has no such
// style, the same glyph on a borderless button of that size; named "Back" for accessibility tools and
// with a "Back" tooltip. Its click is a Button's (actionUIWinUIButtonOnClick). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIBackButtonCreate(void);
// A new button that shows and hides a sidebar, as NavigationView's pane toggle: WinUI's
// PaneToggleButtonStyle (the GlobalNavigationButton glyph, three lines, on a button with no fill until the
// pointer is over it), or, when the theme has no such style, the same glyph on a borderless button 40 by
// 36; named "Show or hide the sidebar" for accessibility tools and with a tooltip of the same. Its click
// is a Button's (actionUIWinUIButtonOnClick). NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIPaneToggleButtonCreate(void);
// A new "see more" button, as a command bar shows one: the More glyph (three dots) of the system's symbol
// font on a button with no fill until the pointer is over it, named "More options" for accessibility
// tools and with a tooltip of the same. A click opens its flyout, which shows `content` (an element: a
// panel of the overflowing items), lent for the call; a tap, Enter or Space in it closes it, as choosing a
// menu item does. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIOverflowButtonCreate(ActionUIWinUIObject *content);

// MARK: - Menu (a DropDownButton and its MenuFlyout)

typedef enum ActionUIWinUIMenuItemKind {
    ActionUIWinUIMenuItem = 0,          // an item that runs something when chosen (MenuFlyoutItem)
    ActionUIWinUIMenuItemToggle = 1,    // a check item (ToggleMenuFlyoutItem)
    ActionUIWinUIMenuItemRadio = 2,     // one of a group's radio items (RadioMenuFlyoutItem)
    ActionUIWinUIMenuItemSeparator = 3, // a line between items
    ActionUIWinUIMenuItemSubmenu = 4,   // a submenu (MenuFlyoutSubItem), its items appended to it
    ActionUIWinUIMenuItemHeader = 5,    // a dimmed title that cannot be chosen (Windows menus have no header)
} ActionUIWinUIMenuItemKind;

// A new DropDownButton (a button with a down arrow that opens its menu), its menu empty. Its title or
// content is set as a Button's (actionUIWinUIButtonSetTitle, actionUIWinUIButtonSetContent). NULL on
// failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuButtonCreate(void);
// The button's menu (a MenuFlyout), a new reference; NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuButtonCopyMenu(ActionUIWinUIObject *button);
// Removes every item of `menu` (a menu, a submenu or a menu bar's menu).
ACTIONUI_WINUI_API bool actionUIWinUIMenuClear(ActionUIWinUIObject *menu);
// Appends an item of `kind` to `menu` (a menu, a submenu or a menu bar's menu) and returns it (a new reference): `title`
// (UTF-8; unused for a separator), whether it can be chosen (`enabled`; a header never can), a check or
// radio item's `checked`, and a radio item's `group` (the radio items of one group exclude each other).
// NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuAppend(ActionUIWinUIObject *menu, ActionUIWinUIMenuItemKind kind,
                                                                const char *title, bool enabled, bool checked,
                                                                const char *group);
// Shows a check or radio item checked or not.
ACTIONUI_WINUI_API bool actionUIWinUIMenuItemSetChecked(ActionUIWinUIObject *item, bool checked);
// Click: the user chose the item (an item, a check item, which WinUI turns over first, or a radio item,
// which WinUI checks first), with the pointer, the keyboard or an accessibility tool. Never from a setter.
ACTIONUI_WINUI_API bool actionUIWinUIMenuItemOnClick(ActionUIWinUIObject *item, ActionUIWinUICallback handler, void *context,
                                                     ActionUIWinUICallback destroyContext);
// The item at `index` (from 0) of `menu` (a menu or a submenu), a new reference; NULL when there is none.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuCopyItem(ActionUIWinUIObject *menu, int32_t index);

// MARK: - MenuBar (the application's menus across the top of a window)

// A new MenuBar with no menus. One bar shows in one window: each window gets its own. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuBarCreate(void);
// Appends a top-level menu titled `title` (UTF-8; a MenuBarItem) and returns it, a new reference: a menu
// actionUIWinUIMenuAppend fills. A menu item's keyboard shortcut (actionUIWinUIElementSetKeyboardShortcut)
// works while its menu is closed, and the menu shows it beside the item's title. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMenuBarAppendMenu(ActionUIWinUIObject *menuBar, const char *title);
// Shows `menuBar` across the top of `window`, above its content, replacing the one shown before; NULL
// removes it. The content keeps the rest of the window.
ACTIONUI_WINUI_API bool actionUIWinUIWindowSetMenuBar(ActionUIWinUIObject *window, ActionUIWinUIObject *menuBar);
// The height `window`'s menu bar takes (effective pixels), 0 with none; -1 on failure.
ACTIONUI_WINUI_API double actionUIWinUIWindowMenuBarHeight(ActionUIWinUIObject *window);

// MARK: - HyperlinkButton (a Link)

// A new HyperlinkButton (text in the accent color that opens a URL) with no padding, so its text lines
// up with the text around it, as SwiftUI's Link shows only its text. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIHyperlinkCreate(void);
// Shows `title` (UTF-8) as the link's text.
ACTIONUI_WINUI_API bool actionUIWinUIHyperlinkSetTitle(ActionUIWinUIObject *link, const char *title);
// Calls handler(context) on each click (a press, Enter or Space, or UI Automation's Invoke). The link
// opens nothing itself: the handler opens its URL (actionUIWinUILaunchURL), so the app decides first.
ACTIONUI_WINUI_API bool actionUIWinUIHyperlinkOnClick(ActionUIWinUIObject *link, ActionUIWinUICallback handler, void *context,
                                                    ActionUIWinUICallback destroyContext);

// MARK: - Expander (a DisclosureGroup)

// A new Expander (a header with a chevron over a content area that opens and closes), collapsed,
// stretched to the width it is given, showing `content` (an element, lent for the call) when expanded.
// NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIExpanderCreate(ActionUIWinUIObject *content);
// Shows `title` (UTF-8) as the header, and names the expander after it for accessibility tools.
ACTIONUI_WINUI_API bool actionUIWinUIExpanderSetTitle(ActionUIWinUIObject *expander, const char *title);
// Expands or collapses it (its ExpandedChanged event follows, as for the user's).
ACTIONUI_WINUI_API bool actionUIWinUIExpanderSetExpanded(ActionUIWinUIObject *expander, bool expanded);
// Whether it is expanded; false on failure.
ACTIONUI_WINUI_API bool actionUIWinUIExpanderIsExpanded(ActionUIWinUIObject *expander);
// ExpandedChanged: it was expanded or collapsed, by the user (pointer, keyboard, an accessibility tool) or
// by actionUIWinUIExpanderSetExpanded (callers compare the state with what they hold).
ACTIONUI_WINUI_API bool actionUIWinUIExpanderOnExpandedChanged(ActionUIWinUIObject *expander, ActionUIWinUICallback handler,
                                                               void *context, ActionUIWinUICallback destroyContext);

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
// Toggle turns a check box or a toggle switch over (its Click, or Toggled, follows); an expander is
// expanded when collapsed and collapsed when expanded (UI Automation's ExpandCollapse pattern). Fails
// when the element can be neither.
ACTIONUI_WINUI_API bool actionUIWinUIAutomationToggle(ActionUIWinUIObject *element);
// SetValue replaces an element's value through UI Automation's Value pattern (its change event
// follows); one with a RangeValue pattern instead (a Slider) gets `value` read as a number; one holding a
// color button (a ColorPicker) gets `value` ("#RRGGBB" or "#RRGGBBAA") as its picker's color, as a pick
// in its flyout (ColorChanged follows). A TextBox,
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

// The resize cursor (west-east when `horizontal`, else north-south) while the pointer is over
// `panel`, one of actionUIWinUIPanelCreate's, or the default cursor when not `resizes` (only the
// panel's own class may set its cursor in WinUI 3). Fails for any other element.
ACTIONUI_WINUI_API bool actionUIWinUIPanelSetResizeCursor(ActionUIWinUIObject *panel, bool resizes, bool horizontal);

// The cursors of actionUIWinUIPanelSetCursor: Windows' system cursors, and a blank one.
typedef enum ActionUIWinUICursor {
    ActionUIWinUICursorDefault = 0,         // none of the panel's own: the cursor of the element it is in
    ActionUIWinUICursorIBeam = 1,
    ActionUIWinUICursorCross = 2,
    ActionUIWinUICursorHand = 3,
    ActionUIWinUICursorSizeAll = 4,         // the move cursor (four arrows)
    ActionUIWinUICursorSizeWestEast = 5,
    ActionUIWinUICursorSizeNorthSouth = 6,
    ActionUIWinUICursorNo = 7,              // a circle with a slash
    ActionUIWinUICursorHidden = 8           // a blank cursor (a resource of the shim's DLL)
} ActionUIWinUICursor;

// `cursor` while the pointer is over `panel`, one of actionUIWinUIPanelCreate's, until the next call.
// Fails for any other element and for a value that is not an ActionUIWinUICursor.
ACTIONUI_WINUI_API bool actionUIWinUIPanelSetCursor(ActionUIWinUIObject *panel, ActionUIWinUICursor cursor);

typedef enum ActionUIWinUIPointerEventKind {
    // The primary button, a pen or a finger went down on the element.
    ActionUIWinUIPointerPressed = 0,
    ActionUIWinUIPointerMoved = 1,
    ActionUIWinUIPointerReleased = 2,
    // The drag ended without a release (the capture was lost, the input canceled).
    ActionUIWinUIPointerCanceled = 3,
} ActionUIWinUIPointerEventKind;

// Called on the UI thread with the pointer's position in `relativeTo`'s coordinates (0, 0 for a
// cancel, or once `relativeTo` is gone); returns whether the element takes the event: a press it takes captures the pointer, so the
// moves and the release that follow come to it wherever the pointer goes.
typedef bool (*ActionUIWinUIPointerCallback)(void *context, ActionUIWinUIPointerEventKind kind, double x, double y);

// Reports `element`'s pointer presses, moves, releases and cancels to `handler` until the element is
// gone (destroyContext then, on the UI thread; at once when this fails). `relativeTo` (usually an
// element around it, held weakly) gives the coordinates.
ACTIONUI_WINUI_API bool actionUIWinUIElementOnPointerDrag(ActionUIWinUIObject *element, ActionUIWinUIObject *relativeTo,
                                                          ActionUIWinUIPointerCallback handler, void *context,
                                                          ActionUIWinUICallback destroyContext);

typedef enum ActionUIWinUIPointerInputKind {
    // The primary button, a pen or a finger went down on the element.
    ActionUIWinUIPointerInputPressed = 0,
    // The pointer moved over the element with or without a press, or anywhere while a press the
    // element took holds it.
    ActionUIWinUIPointerInputMoved = 1,
    ActionUIWinUIPointerInputReleased = 2,
    // A press the element took ended without a release (the capture was lost, the input canceled).
    // Windows also reports the capture's end right after a release: a cancel with no press held is that.
    ActionUIWinUIPointerInputCanceled = 3,
    // The pointer left the element. While a press it took holds the pointer, Windows may report this
    // then or only at the release; the moves keep coming either way.
    ActionUIWinUIPointerInputExited = 4,
    // The mouse wheel or a touchpad scrolled over the element: `wheelX` and `wheelY` say how far.
    ActionUIWinUIPointerInputWheel = 5,
} ActionUIWinUIPointerInputKind;

typedef struct ActionUIWinUIPointerInput {
    ActionUIWinUIPointerInputKind kind;
    // The pointer's position in `relativeTo`'s coordinates (0, 0 for a cancel, or once `relativeTo` is gone).
    double x;
    double y;
    // A finger on a touchscreen (not a mouse, a pen or a touchpad).
    bool touch;
    // Wheel only: in wheel notches (WHEEL_DELTA each, a touchpad's in parts of one), x toward the right,
    // y toward the bottom (a wheel turned toward the user).
    double wheelX;
    double wheelY;
} ActionUIWinUIPointerInput;

// Called on the UI thread; returns whether the element takes the event: a press it takes captures the
// pointer, so the moves and the release that follow come to it wherever the pointer goes; a wheel it takes
// does not reach what is around it (a scroll view), one it leaves does.
typedef bool (*ActionUIWinUIPointerInputCallback)(void *context, const ActionUIWinUIPointerInput *input);

// Reports `element`'s pointer input to `handler` until the element is gone (destroyContext then, on the UI
// thread; at once when this fails): presses, moves (hovering too), releases, cancels, leaving and the
// wheel. `relativeTo` (usually the element itself or one around it, held weakly) gives the coordinates.
// A panel with no background gets a transparent one, so its whole area takes the input.
ACTIONUI_WINUI_API bool actionUIWinUIElementOnPointerInput(ActionUIWinUIObject *element, ActionUIWinUIObject *relativeTo,
                                                           ActionUIWinUIPointerInputCallback handler, void *context,
                                                           ActionUIWinUICallback destroyContext);

typedef enum ActionUIWinUIPointerEventType {
    // The pointer came over the element, and left it.
    ActionUIWinUIPointerEventEntered = 0,
    ActionUIWinUIPointerEventExited = 1,
    // A button went down or up (`button`), a finger or a pen touched or lifted. A second button pressed while
    // one is held comes as a press too (WinUI reports it as a move).
    ActionUIWinUIPointerEventPressed = 2,
    ActionUIWinUIPointerEventMoved = 3,
    ActionUIWinUIPointerEventReleased = 4,
    // The element lost a pointer it held (another took it, the input was canceled). Not after a release.
    ActionUIWinUIPointerEventCanceled = 5,
    // The wheel or a touchpad scrolled over the element: `wheelX` and `wheelY`.
    ActionUIWinUIPointerEventWheel = 6,
} ActionUIWinUIPointerEventType;

typedef enum ActionUIWinUIPointerDevice {
    ActionUIWinUIPointerDeviceMouse = 0,     // a mouse or a touchpad
    ActionUIWinUIPointerDeviceTouch = 1,     // a finger on a touchscreen
    ActionUIWinUIPointerDevicePen = 2,
} ActionUIWinUIPointerDevice;

// Bits of ActionUIWinUIPointerEvent.buttons.
enum {
    ActionUIWinUIPointerButtonLeft = 1,
    ActionUIWinUIPointerButtonRight = 2,
    ActionUIWinUIPointerButtonMiddle = 4,
    ActionUIWinUIPointerButtonBack = 8,      // XButton1
    ActionUIWinUIPointerButtonForward = 16,  // XButton2
};

// Bits of ActionUIWinUIPointerEvent.modifiers (the keys held).
enum {
    ActionUIWinUIModifierShift = 1,
    ActionUIWinUIModifierControl = 2,
    ActionUIWinUIModifierAlt = 4,
    ActionUIWinUIModifierWindows = 8,
    ActionUIWinUIModifierCapsLock = 16,      // Caps Lock on
};

typedef struct ActionUIWinUIPointerEvent {
    ActionUIWinUIPointerEventType type;
    ActionUIWinUIPointerDevice device;
    // Windows' pointer ID: the same for one finger or pen from touch to lift.
    uint32_t pointerID;
    // Pressed and Released: the button that went down or up, 0 left (a finger, a pen's tip), 1 right, 2 middle,
    // 3 back, 4 forward; -1 for the other events.
    int32_t button;
    // The buttons held after the event (ActionUIWinUIPointerButton bits); a finger or a pen's tip down holds Left.
    uint32_t buttons;
    uint32_t modifiers;
    // The pointer's position in the element's coordinates (0, 0 for a cancel).
    double x;
    double y;
    // A pen's pressure, 0 to 1; 1 for a mouse button or a finger held, 0 when none is.
    double pressure;
    // A pen's tilt in degrees, -90 to 90, to the right and toward the user; 0 for other devices.
    double tiltX;
    double tiltY;
    // Wheel only: in wheel notches (WHEEL_DELTA each, a touchpad's in parts of one), x toward the right,
    // y toward the bottom (a wheel turned toward the user).
    double wheelX;
    double wheelY;
    // When the input happened: microseconds since Windows started (0 for a cancel).
    uint64_t timestampMicroseconds;
} ActionUIWinUIPointerEvent;

// Called on the UI thread; returns whether the element takes the event. A press it takes captures that
// pointer, so the moves and the release that follow come to it wherever the pointer goes, until no button
// of it is held; a wheel it takes does not reach what is around it (a scroll view), one it leaves does.
typedef bool (*ActionUIWinUIPointerEventCallback)(void *context, const ActionUIWinUIPointerEvent *event);

// Reports all of `element`'s pointer input to `handler`, every button and device, until the element is gone
// (destroyContext then, on the UI thread; at once when this fails). A panel with no background gets a
// transparent one, so its whole area takes the input.
ACTIONUI_WINUI_API bool actionUIWinUIElementOnPointerEvents(ActionUIWinUIObject *element, ActionUIWinUIPointerEventCallback handler,
                                                            void *context, ActionUIWinUICallback destroyContext);

// Windows' limits for a double click: the most milliseconds between the clicks, and how far apart in pixels
// they may be, across and down.
ACTIONUI_WINUI_API void actionUIWinUIDoubleClickLimits(uint32_t *milliseconds, double *widthPixels, double *heightPixels);

// MARK: - Keyboard focus and keys of any element

// Whether `element` takes keyboard focus (IsTabStop): Tab and Shift-Tab stop at it, and actionUIWinUIElementFocus
// focuses it.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetFocusable(ActionUIWinUIObject *element, bool focusable);
// Gives `element` keyboard focus as a pointer press does (no focus rectangle). False when it cannot take it.
ACTIONUI_WINUI_API bool actionUIWinUIElementFocus(ActionUIWinUIObject *element);
// Whether `element` itself has keyboard focus. False on failure.
ACTIONUI_WINUI_API bool actionUIWinUIElementHasFocus(ActionUIWinUIObject *element);
// Moves keyboard focus on from `element` when it has it (to the next element that takes it, as Tab would),
// so it takes no more keys; nothing when it does not have it.
ACTIONUI_WINUI_API bool actionUIWinUIElementGiveUpFocus(ActionUIWinUIObject *element);
// GotFocus and LostFocus of `element`: handler(context) after its keyboard focus changed, until the element is
// gone (destroyContext then, on the UI thread; at once when this fails).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnFocusChanged(ActionUIWinUIObject *element, ActionUIWinUICallback handler,
                                                           void *context, ActionUIWinUICallback destroyContext);

typedef enum ActionUIWinUIKeyEventType {
    ActionUIWinUIKeyDown = 0,
    ActionUIWinUIKeyUp = 1,
} ActionUIWinUIKeyEventType;

typedef struct ActionUIWinUIKeyEvent {
    ActionUIWinUIKeyEventType type;
    // The Windows virtual-key code (VK_*): the key's meaning in the keyboard's layout.
    int32_t virtualKey;
    // The key's position: its scan code, with 0xE000 added for an extended key (the arrows, Insert, Delete, Home,
    // End, Page Up and Down, the right Control and Alt, the numeric keypad's Enter and slash), as Windows'
    // MapVirtualKey writes them.
    uint32_t scanCode;
    // Down only: the key is held and repeats.
    bool repeat;
    // The keys held (ActionUIWinUIModifier bits).
    uint32_t modifiers;
    // Down only: the UTF-8 text the key types in the keyboard's layout, NULL for none: a key that types nothing
    // (an arrow, a function key, Escape, Return, Backspace, a dead key), and while Control, Alt or Windows is held
    // (a shortcut, not text; Control with Alt is AltGr, whose text comes). Valid during the call.
    const char *text;
    // When the key went down or up: GetMessageTime, milliseconds since Windows started (wraps after 49 days).
    uint32_t timeMilliseconds;
} ActionUIWinUIKeyEvent;

// Called on the UI thread; returns whether the element takes the key: a key it takes goes no further (no focus
// move with Tab, no keyboard accelerator), one it leaves goes on as if it were not there.
typedef bool (*ActionUIWinUIKeyEventCallback)(void *context, const ActionUIWinUIKeyEvent *event);

// Reports the keys pressed and released while `element` (or something in it) has keyboard focus, until the
// element is gone (destroyContext then, on the UI thread; at once when this fails).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnKeyEvents(ActionUIWinUIObject *element, ActionUIWinUIKeyEventCallback handler,
                                                        void *context, ActionUIWinUICallback destroyContext);

// MARK: - Styling

// A color: red, green, blue and alpha, each from 0 to 1 (sRGB).
typedef struct ActionUIWinUIColor {
    double red;
    double green;
    double blue;
    double alpha;
} ActionUIWinUIColor;

// MARK: - Rich text (RichText.cpp)

// A new RichTextBlock: read-only text in paragraphs, wrapping, its whole text selectable as one (the
// pointer, Ctrl+A, Ctrl+C), with no paragraph yet. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIRichTextBlockCreate(void);
// Removes every paragraph.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockClear(ActionUIWinUIObject *block);
// The size of the block's text, in points; 0 or less: the theme's body size.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockSetFontSize(ActionUIWinUIObject *block, double fontSize);
// Starts a paragraph after the others; the runs added next go into it. Its lines start `indent` points
// from the left and end `rightIndent` points from the right, its first line `firstLineIndent` points
// further in (negative: a hanging line, for a list marker), with `spaceBefore` and `spaceAfter` points
// above and below it.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockAddParagraph(ActionUIWinUIObject *block, double indent, double rightIndent,
                                                               double firstLineIndent, double spaceBefore,
                                                               double spaceAfter);
typedef enum ActionUIWinUIRunStyle {
    ActionUIWinUIRunBold = 1,
    ActionUIWinUIRunItalic = 2,
    ActionUIWinUIRunStrikethrough = 4,
    // The monospaced face code is shown in (Cascadia Mono, else Consolas).
    ActionUIWinUIRunMonospace = 8,
} ActionUIWinUIRunStyle;
// Adds `text` (UTF-8) to the last paragraph, in `style` (ActionUIWinUIRunStyle flags), at `fontSize`
// points (0: the block's), in `color`, else the theme brush `themeBrush` (actionUIWinUIElementSetBrush's
// names), else the block's text color. False when the block has no paragraph.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockAddRun(ActionUIWinUIObject *block, const char *text, uint32_t style,
                                                         double fontSize, const ActionUIWinUIColor *color,
                                                         const char *themeBrush);
// Adds a line break to the last paragraph: a new line within it. False when the block has no paragraph.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockAddLineBreak(ActionUIWinUIObject *block);
// Adds `text` as a link to the last paragraph, in `style` and at `fontSize`, in the theme's link color and
// underlined: handler(context) runs when the user clicks it or invokes it from the keyboard, and opens
// nothing itself (the caller judges and opens the address). destroyContext as for the events below.
// False when the block has no paragraph.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockAddLink(ActionUIWinUIObject *block, const char *text, uint32_t style,
                                                          double fontSize, ActionUIWinUICallback handler, void *context,
                                                          ActionUIWinUICallback destroyContext);
// The index of the last inline (a run, a line break or a link) in the block's last paragraph, from 0: with
// the paragraph's index, it names a run for actionUIWinUIRichTextBlockInlineLineBounds. -1 when the last
// paragraph has none, or the block has no paragraph.
ACTIONUI_WINUI_API int32_t actionUIWinUIRichTextBlockLastInlineIndex(ActionUIWinUIObject *block);
// The rectangles the `inlineIndex`th inline of the `paragraphIndex`th paragraph takes, one per line it is on,
// in points from the block's top-left corner, once the block is laid out: each from its first character's
// leading edge to its last character's trailing edge on that line, the line's height. For drawing behind
// the text (inline code's fill). Writes up to `capacity` rectangles into `rects` and returns how many it
// wrote: 0 when the inline is empty or not laid out yet, or on failure (no such inline).
ACTIONUI_WINUI_API int32_t actionUIWinUIRichTextBlockInlineLineBounds(ActionUIWinUIObject *block, int32_t paragraphIndex,
                                                                      int32_t inlineIndex, ActionUIWinUIRect *rects,
                                                                      int32_t capacity);
// The rectangle the `index`th paragraph (from 0, in the order added) takes in the block, in points from its
// top-left corner, once the block is laid out: from the paragraph's indent to the block's right edge, from the
// top of its first line to the bottom of its last. For drawing behind the text (a code card, a quote bar).
// False when there is no such paragraph.
ACTIONUI_WINUI_API bool actionUIWinUIRichTextBlockParagraphBounds(ActionUIWinUIObject *block, int32_t index,
                                                                  ActionUIWinUIRect *bounds);

// MARK: - Color button (a ColorPicker)

// A new color button: a Button showing a swatch of its color that opens a flyout with WinUI's
// ColorPicker (a spectrum, sliders and an opacity slider), as macOS's color well opens the color panel.
// Clear (transparent black) at first. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIColorButtonCreate(void);
// Shows `color` in the swatch and in the picker (the picker's ColorChanged follows when it changes, as
// for the user's pick: callers compare it with what they set).
ACTIONUI_WINUI_API bool actionUIWinUIColorButtonSetColor(ActionUIWinUIObject *button, ActionUIWinUIColor color);
// The picker's color into `color` (each part 0...1, in steps of 1/255).
ACTIONUI_WINUI_API bool actionUIWinUIColorButtonGetColor(ActionUIWinUIObject *button, ActionUIWinUIColor *color);
// ColorChanged: the picker's color changed, picked by the user or set by actionUIWinUIColorButtonSetColor.
// The swatch follows by itself.
ACTIONUI_WINUI_API bool actionUIWinUIColorButtonOnColorChanged(ActionUIWinUIObject *button, ActionUIWinUICallback handler,
                                                               void *context, ActionUIWinUICallback destroyContext);

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
// Makes `color` the accent of `element` (a FrameworkElement) and the controls in it: brushes for the
// theme resources WinUI's controls take their accent from (the accent fills and text, a switch's,
// check box's, radio button's, slider's, accent button's, hyperlink button's, progress bar's and
// selector bar's), at rest, pointed at (90 percent opaque) and pressed (80 percent), in the element's
// resources. Controls look them up when their templates are applied, so set it before they are
// shown. NULL takes them away (the system accent again).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAccent(ActionUIWinUIObject *element, const ActionUIWinUIColor *color);

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
// Whether `element` is collapsed (Visibility.Collapsed: not drawn, no keyboard focus, not seen by
// accessibility tools, and measured as no size), as an element that shows nothing.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetCollapsed(ActionUIWinUIObject *element, bool collapsed);
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
// The name accessibility tools read for `element` (UTF-8; NULL or empty: the control's own, from its
// content).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAccessibleName(ActionUIWinUIObject *element, const char *name);
// What accessibility tools read as `element`'s help, after its name (UI Automation's HelpText; UTF-8;
// NULL or empty: none).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAccessibilityHint(ActionUIWinUIObject *element, const char *hint);
// The identifier test and automation tools find `element` by (UI Automation's AutomationId; UTF-8;
// NULL or empty: none).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetAccessibilityIdentifier(ActionUIWinUIObject *element, const char *identifier);
// The tooltip `element` shows when the pointer rests on it (UTF-8; NULL or empty: none).
ACTIONUI_WINUI_API bool actionUIWinUIElementSetToolTip(ActionUIWinUIObject *element, const char *text);

// A keyboard accelerator for `element`, replacing the one this set before: `key`, a Windows virtual key
// (0: none), with `modifiers` (VirtualKeyModifiers: Control 1, Menu (Alt) 2, Shift 4), handled wherever
// the focus is in the element's window; it does what the keyboard does to the control (a Button clicks).
// `text` (UTF-8, "Ctrl+S") is the accelerator key accessibility tools read, which WinUI does not fill
// from a keyboard accelerator itself; ignored with no key.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetKeyboardShortcut(ActionUIWinUIObject *element, int32_t key, uint32_t modifiers,
                                                                const char *text);

// What accessibility tools read of an element, through its UI Automation peer.
typedef enum ActionUIWinUIAutomationText {
    ActionUIWinUIAutomationName = 0,
    ActionUIWinUIAutomationHelpText = 1,
    ActionUIWinUIAutomationIdentifier = 2,
    // Its accelerator key (AutomationProperties.AcceleratorKey: "Ctrl+S").
    ActionUIWinUIAutomationAcceleratorKey = 3,
} ActionUIWinUIAutomationText;
// `element`'s name, help text or automation identifier as an accessibility tool reads it, as a new UTF-8
// string the caller frees with actionUIWinUIFreeString; NULL (with an error) when the element has no
// automation peer. For tests.
ACTIONUI_WINUI_API char *actionUIWinUIElementCopyAutomationText(ActionUIWinUIObject *element, ActionUIWinUIAutomationText which);
// Joins a control (a button) to its neighbors in a row, as a ControlGroup's: its leading corners are
// rounded only when it is `first`, its trailing ones only when it is `last` (the theme's control corner
// radius), and its leading border is left out unless it is `first`, so neighbors share one border.
// Fails for an element that is no Control.
ACTIONUI_WINUI_API bool actionUIWinUIControlSetJoined(ActionUIWinUIObject *control, bool first, bool last);

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
// Scrolls to the offset (from the content's top left), with WinUI's own animation when `animated`;
// a new call takes over from a running one.
ACTIONUI_WINUI_API bool actionUIWinUIScrollViewerChangeView(ActionUIWinUIObject *scroll, double x, double y, bool animated);
// Where `element` lies (its laid-out size) in the coordinates of `ancestor`, an element around it.
// Fails when `ancestor` is not around `element`.
ACTIONUI_WINUI_API bool actionUIWinUIElementBoundsIn(ActionUIWinUIObject *element, ActionUIWinUIObject *ancestor,
                                                     ActionUIWinUIRect *bounds);
// Lays out what changed in `element`'s window now (WinUI's UpdateLayout), instead of before the next
// frame.
ACTIONUI_WINUI_API bool actionUIWinUIElementUpdateLayout(ActionUIWinUIObject *element);
// SizeChanged: `element` was laid out at a new size (the first layout too: once shown after being
// collapsed).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnSizeChanged(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                                          ActionUIWinUICallback destroyContext);
// Loaded: `element` was added to the window (again: a tab or a page returning).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnLoaded(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                                     ActionUIWinUICallback destroyContext);
// Unloaded: `element` was taken out of the window (a tab or a page left, its window closing). WinUI
// raises it after the removal, so an element removed and added back at once (a stack re-adding its
// children) gets it when it is in the window again, before or after its new Loaded
// (actionUIWinUIElementIsInWindow tells).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnUnloaded(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                                       ActionUIWinUICallback destroyContext);
// Whether `element` is in a window now: it, or an element it is in, is loaded. Not its own IsLoaded
// alone, which reads false until its Loaded is raised for an element just added again. False on
// failure.
ACTIONUI_WINUI_API bool actionUIWinUIElementIsInWindow(ActionUIWinUIObject *element);

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
// The source's rows: how many there are (-1 on failure, or when the source is not in use), a row added
// at the end, row `index` changed (its element, when it has one, is recycled and made again), the rows
// from `count` on removed. A row's `label` (UTF-8) is what accessibility tools name it by, made or not.
ACTIONUI_WINUI_API int32_t actionUIWinUIListSourceCount(ActionUIWinUIObject *list);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceAppend(ActionUIWinUIObject *list, const char *label);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceReplace(ActionUIWinUIObject *list, int32_t index, const char *label);
ACTIONUI_WINUI_API bool actionUIWinUIListSourceTruncate(ActionUIWinUIObject *list, int32_t count);
// The name accessibility tools read for row `index` (from 0; rows or items): its container's automation
// peer's name when the row has a container (in or near view), else its item's text (what WinUI names an
// item without a container by). A new UTF-8 string the caller frees with actionUIWinUIFreeString; NULL on
// failure.
ACTIONUI_WINUI_API char *actionUIWinUIListCopyRowName(ActionUIWinUIObject *list, int32_t index);
// Scrolls the ListView so that row `index` is in view (rows or items).
ACTIONUI_WINUI_API bool actionUIWinUIListScrollIntoView(ActionUIWinUIObject *list, int32_t index);

// MARK: - Presentations (Presentations.cpp)

// A new dialog over a window showing `content` (a ContentDialog with no title or buttons, as large as
// its content and the window allow), for a sheet. `content` must have no parent. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIDialogCreate(ActionUIWinUIObject *content);
// Shows `dialog` over the window `anchor` is in. Fails when `anchor` is in no window, or another dialog
// is open in it (WinUI shows one at a time).
ACTIONUI_WINUI_API bool actionUIWinUIDialogShow(ActionUIWinUIObject *dialog, ActionUIWinUIObject *anchor);
// Closes `dialog` (Closed follows).
ACTIONUI_WINUI_API bool actionUIWinUIDialogHide(ActionUIWinUIObject *dialog);
// Closed: `dialog` closed, by the user (Escape) or by actionUIWinUIDialogHide.
ACTIONUI_WINUI_API bool actionUIWinUIDialogOnClosed(ActionUIWinUIObject *dialog, ActionUIWinUICallback handler, void *context,
                                                    ActionUIWinUICallback destroyContext);

// MARK: - The application's alert (Panels.cpp)

// The answer to an alert: the index of the chosen button (from 0), or -1 when it closed unanswered
// (actionUIWinUIAlertDismiss).
typedef void (*ActionUIWinUIAlertCompletion)(void *context, int32_t index);
// Shows an alert over the window `anchor` is in: a ContentDialog titled `title` (NULL: none) with
// `message` (NULL or empty: none) and `buttons`, `buttonCount` UTF-8 titles (at least one). The first
// button is the primary one and the default (Enter); the button `escapeIndex` names answers Escape and,
// unless it is the first, is the close button (-1: Escape does nothing); the others take the secondary
// place, then the close place, then a column in the content. completion(context, index) runs once on the
// UI thread, when the alert closes. Returns the dialog (a new reference), or NULL when `anchor` is in no
// window or another dialog is open in it (WinUI shows one at a time).
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIAlertShow(ActionUIWinUIObject *anchor, const char *title,
                                                               const char *message, const char *const *buttons,
                                                               int32_t buttonCount, int32_t escapeIndex,
                                                               ActionUIWinUIAlertCompletion completion, void *context);
// Closes the alert unanswered: its completion runs at once with -1, unless it has answered already. For
// a window closing under it, or the application ending.
ACTIONUI_WINUI_API bool actionUIWinUIAlertDismiss(ActionUIWinUIObject *alert);
// Runs the UI thread's messages (GetMessage, TranslateMessage, DispatchMessage) until `*done` is true, for
// a call that returns once the user answers: WinUI keeps drawing and taking input, and its timers and
// queued work run. Returns true when `*done` ended it; false when the application is quitting (WM_QUIT,
// posted again for the outer loop) or the loop failed.
ACTIONUI_WINUI_API bool actionUIWinUIRunNestedLoop(const volatile bool *done);

// MARK: - The application's file panels (Panels.cpp)

typedef enum ActionUIWinUIFileDialogKind {
    // Files to open (IFileOpenDialog).
    ActionUIWinUIFileDialogKindOpen = 0,
    // Folders to open (IFileOpenDialog choosing folders).
    ActionUIWinUIFileDialogKindOpenFolder = 1,
    // A file to save (IFileSaveDialog, asking before it replaces a file).
    ActionUIWinUIFileDialogKindSave = 2,
} ActionUIWinUIFileDialogKind;
// Shows the system's file dialog, modal to `owner` (a window; NULL: none), and returns once the user
// answers; the UI thread's messages run meanwhile (the dialog's own loop). `multiple` lets an open dialog
// choose several. `title` (the dialog's title), `okLabel` (its accept button), `folder` (where it opens:
// a path, with "/" or a backslash between its parts) and `fileName` (the name it proposes) may be NULL. `filterCount`
// filters, each a name ("Images") and a pattern ("*.png;*.jpg"), the first chosen (none for folders);
// `defaultExtension` ("json", NULL: none) is added to a saved name with no extension; `strictTypes` (save)
// adds the chosen filter's extension to a name with another one too, before the dialog asks about
// replacing a file. On success
// `*chosen` is the chosen paths, one per line (a Windows path holds no line break), as a new UTF-8 string
// the caller frees with actionUIWinUIFreeString, or NULL when the user canceled. Fails (false) when the
// dialog could not be shown.
ACTIONUI_WINUI_API bool actionUIWinUIFileDialogRun(ActionUIWinUIObject *owner, ActionUIWinUIFileDialogKind kind, bool multiple,
                                                   const char *title, const char *okLabel, const char *folder,
                                                   const char *fileName, const char *const *filterNames,
                                                   const char *const *filterPatterns, int32_t filterCount,
                                                   const char *defaultExtension, bool strictTypes, char **chosen);
// Cancels the file dialogs on screen modal to `owner` (NULL: every one): each actionUIWinUIFileDialogRun
// returns with no answer. For a window closing, or the application ending.
ACTIONUI_WINUI_API void actionUIWinUIFileDialogsClose(ActionUIWinUIObject *owner);

// A file dialog shown on a thread of its own (actionUIWinUIFileDialogBegin).
typedef struct ActionUIWinUIFileDialogTask ActionUIWinUIFileDialogTask;
// A begun dialog's answer, on the UI thread: `chosen` is the chosen paths, one per line, or NULL when the
// user canceled, a cancel closed it, or it could not be shown; `failure` is why it could not be shown,
// else NULL. Both are valid during the call only.
typedef void (*ActionUIWinUIFileDialogCompletion)(void *context, const char *chosen, const char *failure);
// Shows the system's file dialog as actionUIWinUIFileDialogRun does, with no owner, and returns at once:
// the dialog runs on a thread of its own, so the UI thread goes on and several dialogs can be up at a time,
// each answering when its user does. Call it on the UI thread. completion(context, ...) runs on the UI
// thread, once, unless the application is ending by then (its queue refuses the call; the context is not
// freed). Returns the dialog's handle, which the caller frees with actionUIWinUIFileDialogRelease (the
// dialog goes on; after its completion is the usual time); NULL on failure, when completion never runs.
ACTIONUI_WINUI_API ActionUIWinUIFileDialogTask *actionUIWinUIFileDialogBegin(
    ActionUIWinUIFileDialogKind kind, bool multiple, const char *title, const char *okLabel, const char *folder,
    const char *fileName, const char *const *filterNames, const char *const *filterPatterns, int32_t filterCount,
    const char *defaultExtension, bool strictTypes, ActionUIWinUIFileDialogCompletion completion, void *context);
// Closes the begun dialog unanswered, from any thread: its completion runs with no path. Nothing happens
// once it has answered.
ACTIONUI_WINUI_API void actionUIWinUIFileDialogCancel(ActionUIWinUIFileDialogTask *task);
// Frees the handle; the dialog, if still up, goes on and answers as before.
ACTIONUI_WINUI_API void actionUIWinUIFileDialogRelease(ActionUIWinUIFileDialogTask *task);

// The side of its element a flyout shows on.
typedef enum ActionUIWinUIFlyoutPlacement {
    ActionUIWinUIFlyoutPlacementTop = 0,
    ActionUIWinUIFlyoutPlacementBottom = 1,
    ActionUIWinUIFlyoutPlacementLeft = 2,
    ActionUIWinUIFlyoutPlacementRight = 3,
} ActionUIWinUIFlyoutPlacement;
// A new flyout showing `content` (a Flyout, as large as its content and the window allow, kept inside
// the window), for a popover. `content` must have no parent. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIFlyoutCreate(ActionUIWinUIObject *content);
// Shows `flyout` on the `placement` side of `anchor` (a FrameworkElement in a window). A click outside
// it or Escape closes it.
ACTIONUI_WINUI_API bool actionUIWinUIFlyoutShow(ActionUIWinUIObject *flyout, ActionUIWinUIObject *anchor,
                                                ActionUIWinUIFlyoutPlacement placement);
// Closes `flyout` (Closed follows).
ACTIONUI_WINUI_API bool actionUIWinUIFlyoutHide(ActionUIWinUIObject *flyout);
// Closed: `flyout` closed, by the user (a click outside, Escape) or by actionUIWinUIFlyoutHide.
ACTIONUI_WINUI_API bool actionUIWinUIFlyoutOnClosed(ActionUIWinUIObject *flyout, ActionUIWinUICallback handler, void *context,
                                                    ActionUIWinUICallback destroyContext);

// MARK: - Decoration (Decoration.cpp, Effects.cpp)

// A new rounded box holding `child`, which fills it: its corners (actionUIWinUIRoundedBoxSetCornerRadius)
// clip what it holds and its background (actionUIWinUIElementSetBrush, Background). `child` must have
// no parent. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIRoundedBoxCreate(ActionUIWinUIObject *child);
// The box's corner radius (0: square corners), the same in both axes: WinUI clamps it to half the width
// and half the height separately, so the caller keeps it within half the shorter side for round corners.
ACTIONUI_WINUI_API bool actionUIWinUIRoundedBoxSetCornerRadius(ActionUIWinUIObject *box, double radius);
// Moves what `element` draws, and where it takes pointer input, by the 2D matrix (M11, M12, M21, M22,
// OffsetX, OffsetY: x' = x M11 + y M21 + OffsetX, y' = x M12 + y M22 + OffsetY) without moving its
// layout (a render transform); the identity removes it.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetRenderMatrix(ActionUIWinUIObject *element, double m11, double m12, double m21,
                                                            double m22, double offsetX, double offsetY);

typedef enum ActionUIWinUIClipShapeKind {
    ActionUIWinUIClipShapeNone = 0,
    ActionUIWinUIClipShapeRectangle = 1,
    // The largest circle in the size, centered.
    ActionUIWinUIClipShapeCircle = 2,
    ActionUIWinUIClipShapeEllipse = 3,
    // Corners of radiusX by radiusY; a corner wider than half the width or taller than half the height
    // shrinks keeping its proportions, as SwiftUI's RoundedRectangle.
    ActionUIWinUIClipShapeRoundedRectangle = 4,
} ActionUIWinUIClipShapeKind;

// Clips what `element` draws (not where it takes the pointer) to a shape of `width` by `height` from its
// top leading corner, on its composition visual, in its own coordinates (its render transform moves the
// clip with it); ActionUIWinUIClipShapeNone removes the clip. A new clip at every call: set it when the
// shape or the size changed.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetClipShape(ActionUIWinUIObject *element, ActionUIWinUIClipShapeKind kind,
                                                         double width, double height, double radiusX, double radiusY);

// Draws on `host` (an element behind `source`, laid out at the same place, with no transform of its
// own) the drop shadow of what `source` draws in the rectangle at (left, top), `width` by `height`, of
// its own coordinates after its render transform (the transformed frame's bounds), in `color`, blurred
// by `blurRadius` and moved by (x, y): a shadow in the shape of what is drawn, not of the box, from a
// live capture of `source`'s visual, which includes that transform. NULL `color` removes it. Call it
// again when the rectangle or the source changes.
ACTIONUI_WINUI_API bool actionUIWinUIElementSetShadow(ActionUIWinUIObject *host, ActionUIWinUIObject *source,
                                                      const ActionUIWinUIColor *color, double blurRadius, double x,
                                                      double y, double left, double top, double width, double height);

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
    // Scaled to exactly that size, each axis on its own (WinUI's Fill): a small grid of colors stretched
    // into a soft preview.
    ActionUIWinUIImageStretchToSize = 3,
} ActionUIWinUIImageStretch;

// A new Image control showing nothing, at its image's own size. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIImageCreate(void);
// Shows the image file at `path` (absolute, or relative to the current folder): an .svg file as a
// vector image, anything else through WinUI's bitmap decoders (PNG, JPEG, GIF, BMP, TIFF, ICO, and
// what the system's codecs add). A bitmap file is read again at every call, not taken from WinUI's
// cache, so a file rewritten under the same name shows its new image; an SVG file may come from the
// cache (SvgImageSource has no such option). Loading is asynchronous: the image has its size once it
// has loaded, and a file that cannot be decoded shows nothing. Fails for a path that names no regular
// file (actionUIWinUIIsRegularFile).
ACTIONUI_WINUI_API bool actionUIWinUIImageSetFile(ActionUIWinUIObject *image, const char *path);
ACTIONUI_WINUI_API bool actionUIWinUIImageSetStretch(ActionUIWinUIObject *image, ActionUIWinUIImageStretch stretch);
// Shows the image `url` (UTF-8, an absolute URI: http, https, file) names: one whose path ends in .svg
// as a vector image, anything else through WinUI's bitmap decoders, loaded without blocking (WinUI
// downloads it while the image is in the window). WinUI's image cache is used: a URL shown before
// may not be read again. Fails for text that is no absolute URI, and for a file URL that names no
// regular file (actionUIWinUIIsRegularFile); whether the image loads is told by
// actionUIWinUIImageOnOpened or actionUIWinUIImageOnFailed.
ACTIONUI_WINUI_API bool actionUIWinUIImageSetURL(ActionUIWinUIObject *image, const char *url);
// ImageOpened: the image's source was loaded and decoded (it has its size).
ACTIONUI_WINUI_API bool actionUIWinUIImageOnOpened(ActionUIWinUIObject *image, ActionUIWinUICallback handler, void *context,
                                                   ActionUIWinUICallback destroyContext);
// ImageFailed: the image's source could not be loaded or decoded.
ACTIONUI_WINUI_API bool actionUIWinUIImageOnFailed(ActionUIWinUIObject *image, ActionUIWinUICallback handler, void *context,
                                                   ActionUIWinUICallback destroyContext);
// Whether `path` (absolute, or relative to the current folder) names a regular file, symbolic links
// followed: false for a missing file, a folder, a device (NUL, CON, COM1, anything under \\.\) and a
// pipe, which an image decoder would read forever or wait on (ActionUI JSON names the path). False for
// NULL. Any thread; sets no error.
ACTIONUI_WINUI_API bool actionUIWinUIIsRegularFile(const char *path);
// The pixel size the image file at `path` (UTF-8) declares, read from its header by Windows' image
// decoders (WIC) without decoding the image: its largest frame's (an icon's sizes, an animation's
// frames), or a GIF's logical screen when larger. False when none of them reads it (an SVG, a file that
// is no image or that cannot be opened). Any thread with COM initialized; sets no error.
ACTIONUI_WINUI_API bool actionUIWinUIImageFileGetSize(const char *path, uint32_t *width, uint32_t *height);
// The same for an image's `length` bytes in memory (read only during the call). False for an SVG or
// bytes that are no image WIC reads.
ACTIONUI_WINUI_API bool actionUIWinUIImageDataGetSize(const uint8_t *bytes, size_t length, uint32_t *width, uint32_t *height);
// Shows the bitmap image the `length` bytes hold in `image` (a copy is kept), not cached and not shared
// with other images. Its header is read at once (false when it is no image Windows reads); the image
// loads after, and ImageOpened or ImageFailed tells the outcome.
ACTIONUI_WINUI_API bool actionUIWinUIImageSetData(ActionUIWinUIObject *image, const uint8_t *bytes, size_t length);
// Shows `imageSource` in `image`: a borrowed `IInspectable *` of a Microsoft.UI.Xaml.Media.ImageSource another
// library made on this UI thread (AsyncImageCache's PlatformImage.imageSource, a SoftwareBitmapSource), which the
// image takes its own reference to. One source may be shown by many images. Shown at its stretch, no ImageOpened.
// NULL clears the image. False for an object that is no ImageSource.
ACTIONUI_WINUI_API bool actionUIWinUIImageSetSource(ActionUIWinUIObject *image, void *imageSource);

// MARK: - Frames drawn elsewhere (Frames.cpp)

// Shows `pixels` in `image`: `width` x `height`, premultiplied BGRA, rows `width * 4` bytes apart, top row
// first. The pixels are copied before it returns. The image's bitmap is written over when it is one of this
// size (a stream of frames), else a new one is made. Shown at the image's stretch. Main thread.
ACTIONUI_WINUI_API bool actionUIWinUIImageShowPixels(ActionUIWinUIObject *image, uint32_t width, uint32_t height,
                                                     const uint8_t *pixels);
// CompositionTarget.Rendering: handler(context, seconds) runs on the UI thread before each frame WinUI draws,
// `seconds` the frame's rendering time (from an arbitrary start). WinUI draws frames while any handler is
// added, so add one only while frames are wanted. Returns a token for actionUIWinUIRenderingRemove, 0 on
// failure (destroyContext has then run). Main thread.
typedef void (*ActionUIWinUIRenderingCallback)(void *context, double seconds);
ACTIONUI_WINUI_API uint64_t actionUIWinUIRenderingAdd(ActionUIWinUIRenderingCallback handler, void *context,
                                                      ActionUIWinUICallback destroyContext);
// Removes a handler actionUIWinUIRenderingAdd added (it may be running: it may remove itself). destroyContext
// runs once no call of it is running. An unknown token does nothing. Main thread.
ACTIONUI_WINUI_API void actionUIWinUIRenderingRemove(uint64_t token);
// XamlRoot.Changed of the window `element` is in now: handler(context) runs on the UI thread when that window's
// size, scale (RasterizationScale: another display, or a new scale setting) or visibility (IsHostVisible:
// minimized or restored) changes, and when it becomes or stops being the active window (its input activation).
// It watches the window the element is in when called: an element put in another window needs a new watch.
// Returns a token for actionUIWinUIXamlRootChangedRemove, 0 when the element is in no window or on failure
// (destroyContext has then run). Main thread.
ACTIONUI_WINUI_API uint64_t actionUIWinUIXamlRootChangedAdd(ActionUIWinUIObject *element, ActionUIWinUICallback handler,
                                                            void *context, ActionUIWinUICallback destroyContext);
// Removes a watch actionUIWinUIXamlRootChangedAdd added (it may be running: it may remove itself).
// destroyContext runs once no call of it is running. An unknown token does nothing. Main thread.
ACTIONUI_WINUI_API void actionUIWinUIXamlRootChangedRemove(uint64_t token);
// Whether the window `element` is in is shown (its XamlRoot's IsHostVisible): false while it is minimized, and
// when the element is in no window.
ACTIONUI_WINUI_API bool actionUIWinUIElementIsHostVisible(ActionUIWinUIObject *element);
// Whether the window `element` is in is the active window (it takes the keyboard's input), from the Activated events
// of the windows actionUIWinUIWindowCreate made; true for a window it did not make (a host's own), false when the
// element is in no window.
ACTIONUI_WINUI_API bool actionUIWinUIElementIsWindowActive(ActionUIWinUIObject *element);

// MARK: - Drawing (a Canvas)

// One drawing: Direct2D into a bitmap of `width` x `height` points at `scale` pixels a point
// (actionUIWinUIElementRasterizationScale), transparent at first, then shown by a WinUI Image
// (actionUIWinUIImageCreate) with actionUIWinUIDrawingFinish. Coordinates are points, y down, under
// the transform last set (the identity at first). A path is built with MoveTo, LineTo, QuadTo, CubicTo
// and Close (a segment before any move fails; after Close, the next segment starts where the closed
// figure started) and used up by the Fill, Stroke or Clip after it (the nonzero winding rule).
typedef struct ActionUIWinUIDrawing ActionUIWinUIDrawing;

typedef enum ActionUIWinUILineCap {
    ActionUIWinUILineCapButt = 0,
    ActionUIWinUILineCapRound = 1,
    ActionUIWinUILineCapSquare = 2,
} ActionUIWinUILineCap;

typedef enum ActionUIWinUILineJoin {
    // Beveled past the miter limit.
    ActionUIWinUILineJoinMiter = 0,
    ActionUIWinUILineJoinRound = 1,
    ActionUIWinUILineJoinBevel = 2,
} ActionUIWinUILineJoin;

// How a context's operations are put over what it drew before (SwiftUI's blend modes the canvas
// knows; any other is normal).
typedef enum ActionUIWinUIBlendMode {
    ActionUIWinUIBlendModeNormal = 0,
    ActionUIWinUIBlendModeMultiply = 1,
    ActionUIWinUIBlendModeScreen = 2,
    ActionUIWinUIBlendModeOverlay = 3,
} ActionUIWinUIBlendMode;

typedef enum ActionUIWinUIDrawingFilterKind {
    // A drop shadow of `color` offset by (x, y) points, `radius` SwiftUI's (twice its deviation).
    ActionUIWinUIDrawingFilterShadow = 0,
    // A Gaussian blur of `radius` points (its deviation, as SwiftUI's).
    ActionUIWinUIDrawingFilterBlur = 1,
} ActionUIWinUIDrawingFilterKind;

typedef struct ActionUIWinUIDrawingFilter {
    ActionUIWinUIDrawingFilterKind kind;
    ActionUIWinUIColor color;
    double radius;
    double x;
    double y;
} ActionUIWinUIDrawingFilter;

// A new drawing; NULL on failure (a size or scale that is not a positive number, more than 16384
// pixels a side). Each drawing ends with actionUIWinUIDrawingFinish or actionUIWinUIDrawingDiscard.
ACTIONUI_WINUI_API ActionUIWinUIDrawing *actionUIWinUIDrawingBegin(double width, double height, double scale);
// The transform of what is drawn after it: x' = a x + c y + tx, y' = b x + d y + ty. Drops a path
// not used yet (each path starts by setting its transform).
ACTIONUI_WINUI_API bool actionUIWinUIDrawingSetTransform(ActionUIWinUIDrawing *drawing, double a, double b, double c, double d,
                                                         double tx, double ty);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingMoveTo(ActionUIWinUIDrawing *drawing, double x, double y);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingLineTo(ActionUIWinUIDrawing *drawing, double x, double y);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingQuadTo(ActionUIWinUIDrawing *drawing, double cx, double cy, double x, double y);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingCubicTo(ActionUIWinUIDrawing *drawing, double c1x, double c1y, double c2x, double c2y,
                                                    double x, double y);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingClose(ActionUIWinUIDrawing *drawing);
// Fills the path with `color` (its components 0...1, straight alpha).
ACTIONUI_WINUI_API bool actionUIWinUIDrawingFill(ActionUIWinUIDrawing *drawing, ActionUIWinUIColor color);
// Fills the path with a linear gradient from (x0, y0) to (x1, y1), or a radial one around (cx, cy)
// out to `radius`, in the coordinates of the path: `count` colors (at least one) at `offsets` (0 to
// 1, in order), the end colors extended past them.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingFillLinearGradient(ActionUIWinUIDrawing *drawing, double x0, double y0, double x1,
                                                               double y1, const ActionUIWinUIColor *colors, const double *offsets,
                                                               int32_t count);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingFillRadialGradient(ActionUIWinUIDrawing *drawing, double cx, double cy, double radius,
                                                               const ActionUIWinUIColor *colors, const double *offsets,
                                                               int32_t count);
// Draws `text` (UTF-8) with its top leading corner at (x, y), wrapped at `width` points (0 or less:
// not wrapped), in WinUI's text font (Segoe UI Variable) at `fontSize` points and `weight` (100 to 900; 400
// regular), under the transform set. Drops a path not used yet.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingText(ActionUIWinUIDrawing *drawing, const char *text, double x, double y, double width,
                                                 double fontSize, int32_t weight, ActionUIWinUIColor color);
// The size `text` (UTF-8) takes on one line in the font actionUIWinUIDrawingText draws in, at `fontSize`
// points and `weight`: its layout's width and height in points (0 x 0 for an empty string). False, with an
// error, for a size that is not a positive number.
ACTIONUI_WINUI_API bool actionUIWinUIMeasureText(const char *text, double fontSize, int32_t weight, double *width, double *height);
// The theme's primary text color, as text and symbols draw by default (black when the theme has none).
ACTIONUI_WINUI_API ActionUIWinUIColor actionUIWinUIThemeTextColor(void);
// Draws the image file at `path` (absolute, or relative to the current folder) stretched to the
// frame (x, y, width, height) at `opacity` (0 to 1), under the transform set. Fails, drawing nothing,
// for a path that names no regular file (actionUIWinUIIsRegularFile) and for a file the system's
// decoders cannot read (an SVG file among them). Drops a path not used yet.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingImageFile(ActionUIWinUIDrawing *drawing, const char *path, double x, double y,
                                                      double width, double height, double opacity);
// Draws SF Symbol `name` (the shim's outline for it, as actionUIWinUISymbolCreate) stretched to the
// frame, filled with `color` (NULL: the theme's primary text color) at `opacity`. Fails, drawing
// nothing, when the shim has no outline for the name. Drops a path not used yet.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingSymbol(ActionUIWinUIDrawing *drawing, const char *name, double x, double y, double width,
                                                   double height, const ActionUIWinUIColor *color, double opacity);
// Strokes the path `width` points wide (0 or less draws nothing). `dashes` (`dashCount` lengths in
// points, or NULL) dash it from `dashPhase` points in; a pattern of only zeros is solid.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingStroke(ActionUIWinUIDrawing *drawing, ActionUIWinUIColor color, double width,
                                                   ActionUIWinUILineCap cap, ActionUIWinUILineJoin join, double miterLimit,
                                                   const double *dashes, int32_t dashCount, double dashPhase);
// Clips everything drawn after it in the current context to the path, where it lies under the
// transform set now (with the context's clips before it); a drawing with no path clips everything
// away.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingClip(ActionUIWinUIDrawing *drawing);
// The canvas and each layer is a context: its clips (actionUIWinUIDrawingClip), filters, opacity and
// blend mode apply to each operation drawn in it after they are set, as in SwiftUI's GraphicsContext.
// The filters apply in the order given (the first innermost), then the opacity, then the clips; the
// result is blended over what the context drew before. Radii and offsets are in points.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingSetFilters(ActionUIWinUIDrawing *drawing, const ActionUIWinUIDrawingFilter *filters,
                                                       int32_t count);
// Opacity 0 to 1 (1 at first).
ACTIONUI_WINUI_API bool actionUIWinUIDrawingSetOpacity(ActionUIWinUIDrawing *drawing, double opacity);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingSetBlendMode(ActionUIWinUIDrawing *drawing, ActionUIWinUIBlendMode mode);
// Begins a layer: a new context drawn into its own bitmap of the canvas's size, with no clips or
// filters, opacity 1 and the normal blend mode. actionUIWinUIDrawingEndLayer ends it and puts what
// it drew over the context around it as one operation (that context's clips, filters, opacity and
// blend mode apply); the context around it is current again, as it was.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingBeginLayer(ActionUIWinUIDrawing *drawing);
ACTIONUI_WINUI_API bool actionUIWinUIDrawingEndLayer(ActionUIWinUIDrawing *drawing);
// Ends the drawing and shows it in `image` (a WinUI Image), stretched to the image's size. Frees
// the drawing, also on failure.
ACTIONUI_WINUI_API bool actionUIWinUIDrawingFinish(ActionUIWinUIDrawing *drawing, ActionUIWinUIObject *image);
// Ends the drawing without showing it, and frees it. NULL does nothing.
ACTIONUI_WINUI_API void actionUIWinUIDrawingDiscard(ActionUIWinUIDrawing *drawing);
// The pixels a point of `element`'s window has (its XamlRoot's RasterizationScale: 1.5 at 150%); 1
// when it is in no window yet.
ACTIONUI_WINUI_API double actionUIWinUIElementRasterizationScale(ActionUIWinUIObject *element);
// ActualThemeChanged: `element`'s theme turned light or dark (the system's, the app's or an ancestor's
// changed); what it drew from the theme is to be drawn again.
ACTIONUI_WINUI_API bool actionUIWinUIElementOnActualThemeChanged(ActionUIWinUIObject *element, ActionUIWinUICallback handler,
                                                                 void *context, ActionUIWinUICallback destroyContext);
// Whether `element`'s theme is dark now (ActualTheme); false when it is light, or `element` is no
// FrameworkElement. Sets no error.
ACTIONUI_WINUI_API bool actionUIWinUIElementIsDark(ActionUIWinUIObject *element);
// PointerEntered and PointerExited: the pointer came over `element` (or something in it) and left it;
// a mouse or a pen, not a finger (whose press and release WinUI reports as entering and leaving).
// A panel with no background gets a transparent one when Entered is connected, so its whole area,
// not only what is drawn in it, tracks the pointer (a click there no longer reaches what is behind).
ACTIONUI_WINUI_API bool actionUIWinUIElementOnPointerEntered(ActionUIWinUIObject *element, ActionUIWinUICallback handler,
                                                             void *context, ActionUIWinUICallback destroyContext);
ACTIONUI_WINUI_API bool actionUIWinUIElementOnPointerExited(ActionUIWinUIObject *element, ActionUIWinUICallback handler,
                                                            void *context, ActionUIWinUICallback destroyContext);
// Tapped: a press and release on `element` (pointer, pen or touch). The event is handled there, so
// an element around it does not see it.
ACTIONUI_WINUI_API bool actionUIWinUIElementOnTapped(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                                     ActionUIWinUICallback destroyContext);

// MARK: - Web view (WinUI's WebView2)

// What a web view's command does to its page.
typedef enum ActionUIWinUIWebViewCommand {
    // Back or forward in its history (nothing when there is nowhere to go).
    ActionUIWinUIWebViewGoBack = 0,
    ActionUIWinUIWebViewGoForward = 1,
    ActionUIWinUIWebViewReload = 2,
    ActionUIWinUIWebViewStop = 3,
} ActionUIWinUIWebViewCommand;

// A web view's page as it stands.
typedef struct ActionUIWinUIWebViewState {
    // Between a navigation's start and its end.
    bool loading;
    // 0.1 once a navigation starts, 1 when it ends (WebView2 reports no progress between).
    double progress;
    bool canGoBack;
    bool canGoForward;
} ActionUIWinUIWebViewState;

// A new web view (WebView2, on the WebView2 runtime Windows ships), as large as it is given. It starts
// its browser asynchronously, in the process's one WebView2 environment (made with the first web view):
// what is asked of it before then (the calls below) waits, in order, and runs once it has started; a
// script waits until added, so a page after it gets it. The environment keeps the browser's data
// (cookies, cache, storage) in the folder the host named in WEBVIEW2_USER_DATA_FOLDER, else in
// %LOCALAPPDATA%\<program name>\WebView2 (by default it would go beside the program, which an installed
// one may not write to); the process's environment variables are not changed.
// `restricted`: its pages are less-trusted content's, for good: no permission, no sign-in, no script
// dialog (leaving a page still allowed), no fullscreen, no printing, no saving from its menu, no
// developer tools or browser keys, no autofill or saved passwords.
// `privateData`: the web view gets a separate, private browser profile (InPrivate). Its cookies, cache
// and storage are shared with no other web view and never written to disk.
// NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIWebViewCreateWithOptions(bool restricted, bool privateData);
ACTIONUI_WINUI_API bool actionUIWinUIWebViewSetUserAgent(ActionUIWinUIObject *webView, const char *userAgent);
// Runs `source` (JavaScript) in every document from then on: as it is created, before its own scripts,
// or when it has been parsed (`atDocumentEnd`, its DOMContentLoaded, as the browser runs a page's own
// script: no eval, which a page's security policy may refuse); in the main frame only, or in it and its
// frames (a document-created script in every frame, a parsed one in the main frame's frames).
ACTIONUI_WINUI_API bool actionUIWinUIWebViewAddScript(ActionUIWinUIObject *webView, const char *source, bool atDocumentEnd,
                                                      bool mainFrameOnly);
ACTIONUI_WINUI_API bool actionUIWinUIWebViewNavigate(ActionUIWinUIObject *webView, const char *url);
// Shows `html` as the page. With no `baseURL` (NULL) its URL is about:blank and relative links resolve
// against nothing; with an http or https `baseURL` (UTF-8) the page is that address, as WebKit's
// loadHTMLString(_:baseURL:) makes it: its origin, cookies and storage, and relative links resolved
// against it (the web view goes to the address and is answered with `html` instead of the server's
// page, once). Fails for a base that is not an absolute http or https URL.
ACTIONUI_WINUI_API bool actionUIWinUIWebViewNavigateToString(ActionUIWinUIObject *webView, const char *html, const char *baseURL);
ACTIONUI_WINUI_API bool actionUIWinUIWebViewRun(ActionUIWinUIObject *webView, ActionUIWinUIWebViewCommand command);
// False, with the error, once the browser could not start.
ACTIONUI_WINUI_API bool actionUIWinUIWebViewGetState(ActionUIWinUIObject *webView, ActionUIWinUIWebViewState *state);
// The page's URL and title, as new UTF-8 strings the caller frees with actionUIWinUIFreeString (empty
// before the browser has started); NULL on failure.
ACTIONUI_WINUI_API char *actionUIWinUIWebViewCopyURL(ActionUIWinUIObject *webView);
ACTIONUI_WINUI_API char *actionUIWinUIWebViewCopyTitle(ActionUIWinUIObject *webView);
// Where the browser's start is: "starting", "started", or "failed: " and why, as a new UTF-8 string
// the caller frees with actionUIWinUIFreeString; NULL on failure.
ACTIONUI_WINUI_API char *actionUIWinUIWebViewCopyStatus(ActionUIWinUIObject *webView);
// `handler` runs on the UI thread whenever the page's URL, title, history or loading changes, or the
// browser could not start (one handler per web view: a new one replaces it).
ACTIONUI_WINUI_API bool actionUIWinUIWebViewOnChanged(ActionUIWinUIObject *webView, ActionUIWinUICallback handler, void *context,
                                                      ActionUIWinUICallback destroyContext);

// What a web view asks its decider about.
typedef enum ActionUIWinUIWebViewNavigationKind {
    // The page itself going to an address (a link, a script, a form, a redirect, the app's own load).
    ActionUIWinUIWebViewNavigationPage,
    // A frame in the page going to an address.
    ActionUIWinUIWebViewNavigationFrame,
    // The page handing an address of another scheme to the app registered for it (mailto:, an app's
    // own scheme); refused, it is not opened.
    ActionUIWinUIWebViewNavigationExternalScheme,
    // The page opening a new window (window.open, a link with target _blank); refused, no window opens.
    ActionUIWinUIWebViewNavigationNewWindow,
    // The page saving a file into the user's Downloads (a download link, a response WebView2 cannot
    // show); refused, nothing is saved.
    ActionUIWinUIWebViewNavigationDownload,
} ActionUIWinUIWebViewNavigationKind;

// Decides whether the web view goes to `url` (UTF-8) for `kind`, synchronously on the UI thread: true
// lets it, false refuses it (the navigation is canceled, the address not opened, the window not made).
typedef bool (*ActionUIWinUIWebViewNavigationDecider)(void *context, const char *url, ActionUIWinUIWebViewNavigationKind kind);

// `decide` is asked about each navigation, frame navigation, external scheme, new window and download of the web
// view, also those it was told to make (one decider per web view: a new one replaces it; without one,
// WebView2 decides). destroyContext(context) runs once the web view no longer needs it.
ACTIONUI_WINUI_API bool actionUIWinUIWebViewSetNavigationDecider(ActionUIWinUIObject *webView, ActionUIWinUIWebViewNavigationDecider decide,
                                                               void *context, ActionUIWinUICallback destroyContext);

// MARK: - Video player (WinUI's MediaPlayerElement)

// A new video player: the video fitted inside it, keeping its aspect ratio, with Windows' transport
// controls over it, as large as it is given. It plays through one MediaPlayer for its whole life, so
// a new source keeps the volume and mute chosen. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIVideoPlayerCreate(void);
// Pauses, and shows the video at `url` (NULL or empty: none), not playing. A text that is no absolute
// URL shows none, its status "failed: not an absolute URL".
ACTIONUI_WINUI_API bool actionUIWinUIVideoPlayerSetSource(ActionUIWinUIObject *videoPlayer, const char *url);
// Plays or pauses (a video still opening plays once it has opened).
ACTIONUI_WINUI_API bool actionUIWinUIVideoPlayerSetPlaying(ActionUIWinUIObject *videoPlayer, bool playing);
// Where the source is: "none", "opening", "opened W x H" (the video's own size in pixels) or "failed: "
// and why, as a new UTF-8 string the caller frees with actionUIWinUIFreeString; NULL on failure.
ACTIONUI_WINUI_API char *actionUIWinUIVideoPlayerCopyStatus(ActionUIWinUIObject *videoPlayer);
// `handler` runs on the UI thread when the source shown has opened or could not be played (one handler
// per player: a new one replaces it).
ACTIONUI_WINUI_API bool actionUIWinUIVideoPlayerOnChanged(ActionUIWinUIObject *videoPlayer, ActionUIWinUICallback handler,
                                                          void *context, ActionUIWinUICallback destroyContext);

// MARK: - Map (OpenStreetMap's tiles)

// Where a map looks: its center and zoom level (0 shows the world in one 256-pixel tile, each level
// doubles it), and whether a finger, pen or button is on it or a flick is still moving it.
typedef struct ActionUIWinUIMapCamera {
    double latitude;
    double longitude;
    double zoom;
    bool interacting;
} ActionUIWinUIMapCamera;

// A new map of OpenStreetMap's standard tiles, as large as it is given, opening at 0, 0 and zoom 1.
// The tiles in view are fetched with Windows' HTTP client (whose cache honors the server's cache
// headers), with `userAgent` naming the program, as OpenStreetMap's tile usage policy asks. A drag
// (and a flick) pans; the wheel, a pinch, a double tap and its zoom buttons (top right) zoom;
// OpenStreetMap's attribution, a link to its copyright page, sits bottom right. NULL on failure.
ACTIONUI_WINUI_API ActionUIWinUIObject *actionUIWinUIMapCreate(const char *userAgent);
// An annotation: a pin (an icon the caller made, a symbol in its color, or NULL for none) with its
// tip on the coordinate, and the title (semibold) and subtitle (NULL or empty: none) centered under
// it, wrapped, on a light plate, dark whatever the theme (the tiles stay light). `pinSide` is the
// side of the pin's square and `pinTip` how far its tip is above the square's bottom.
typedef struct ActionUIWinUIMapAnnotation {
    double latitude;
    double longitude;
    const char *title;
    const char *subtitle;
    ActionUIWinUIObject *pin;
    double pinSide;
    double pinTip;
} ActionUIWinUIMapAnnotation;

// Replaces the map's annotations (`count` of them; one whose coordinate is not a number is skipped).
// They take no input: a drag or a click on one goes to the map; a screen reader reads their text. The
// pins are the map's from then on (the caller may release its references).
ACTIONUI_WINUI_API bool actionUIWinUIMapSetAnnotations(ActionUIWinUIObject *map, const ActionUIWinUIMapAnnotation *annotations,
                                                       size_t count);
// Shows the user's location from Windows' location service as a dot in the accent color, over the
// annotations, while the map is in a window (Windows asks the user the first time a program wants the
// location). It never moves the map. No position (the location turned off in Windows' Settings, or
// refused): no dot; actionUIWinUIMapCopyStatus says why.
ACTIONUI_WINUI_API bool actionUIWinUIMapSetShowsUserLocation(ActionUIWinUIObject *map, bool shows);
// Moves the map to look at latitude, longitude at `zoom` (negative or not a number: the zoom stays),
// at once; the moved handler runs before this returns.
ACTIONUI_WINUI_API bool actionUIWinUIMapSetCamera(ActionUIWinUIObject *map, double latitude, double longitude, double zoom);
ACTIONUI_WINUI_API bool actionUIWinUIMapGetCamera(ActionUIWinUIObject *map, ActionUIWinUIMapCamera *camera);
// What the user may do: pan (drag, flick) and zoom (wheel, pinch, double tap, the zoom buttons, shown
// only then).
ACTIONUI_WINUI_API bool actionUIWinUIMapSetInteraction(ActionUIWinUIObject *map, bool pan, bool zoom);
// How the tiles went: "N tiles loaded, M failed", and the first failure's reason in parentheses, then
// when the map shows the user's location "; user location: " and "shown" or where the location
// service is (why there is no position), as a new UTF-8 string the caller frees with
// actionUIWinUIFreeString; NULL on failure.
ACTIONUI_WINUI_API char *actionUIWinUIMapCopyStatus(ActionUIWinUIObject *map);
// `handler` runs on the UI thread at every change of the camera (each step of a drag or a zoom, and
// actionUIWinUIMapSetCamera), and when a press or a flick on the map ends (one handler per map: a new
// one replaces it).
ACTIONUI_WINUI_API bool actionUIWinUIMapOnMoved(ActionUIWinUIObject *map, ActionUIWinUICallback handler, void *context,
                                                ActionUIWinUICallback destroyContext);

// MARK: - Network

// Called on the UI thread when a fetch ends: the body's `length` bytes and `finalURL`, the address they
// came from when a redirect was followed (UTF-8; NULL without one), or NULL bytes and `error`, why not (an
// HTTP status that is not success, a network failure, a limit). Every pointer is valid only during the call.
typedef void (*ActionUIWinUIDataCompletion)(void *context, const uint8_t *bytes, size_t length, const char *finalURL,
                                            const char *error);
// Fetches the http or https `url` with Windows' HTTP client (its cache and proxy settings), without
// blocking: completion(context, ...) is called on the UI thread, always after this returns. Limits: the
// body is read as it arrives and refused once it grows past `maximumBytes` (at once when the server
// says it is longer); the whole fetch is given up after `timeoutSeconds` (0: no limit; at most 24 days), and
// any step (sending the request and reading the response's headers, opening the body, one read) once it
// has waited 30 seconds for the server; redirects are followed here, their bodies unread, only to http
// and https, never from https to http, at most 20. False (and no completion) when it could not start: not
// an http or https URL, not on the UI thread, a limit out of range.
ACTIONUI_WINUI_API bool actionUIWinUIFetchURL(const char *url, int64_t maximumBytes, double timeoutSeconds,
                                              ActionUIWinUIDataCompletion completion, void *context);
// The same, for an address named by less-trusted content, with WinHTTP. The request sends no cookies,
// client certificate or Windows sign-in (Negotiate, NTLM, Kerberos) to the server or a proxy, keeps no
// cookies, shows no password dialog and uses no cache. A server or proxy that asks for a sign-in (401,
// 407) gets a failure. The limits and redirect rules are the same; the completion is called on the UI
// thread that started the download.
ACTIONUI_WINUI_API bool actionUIWinUIFetchURLPrivately(const char *url, int64_t maximumBytes, double timeoutSeconds,
                                                       ActionUIWinUIDataCompletion completion, void *context);

// MARK: - Symbols

// The SF Symbol names ActionUI can draw on Windows are those of its SF Symbols -> Material Symbols
// map, at each row's fill and weight (at most 300, Windows' thinner look), and, for names that map
// lacks, those of its SF Symbols -> Fluent System Icons map, compiled into the shim with their
// outlines (Scripts/prepare-windows-symbols.py); no font ships. A symbol is an icon element (a
// PathIcon): it draws in the inherited text color (a button's changes with its state), as SF Symbols
// take the text color, or in the brush actionUIWinUIElementSetBrush gives its Foreground.

// Whether the shim was built with the symbol outlines (false: every name is unknown).
ACTIONUI_WINUI_API bool actionUIWinUISymbolsAvailable(void);
// Whether `name` (an SF Symbol name, exact) has an outline.
ACTIONUI_WINUI_API bool actionUIWinUISymbolExists(const char *name);
// A new icon drawing the symbol `name` in a square of actionUIWinUISymbolSetSize's size (the Material
// or Fluent glyph's em box: the glyph sits inside it with the font's margins). NULL (with an error)
// when the name has no outline.
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
// included, with the popups open over it (a dialog, a flyout, a menu) drawn at their places. Fails when the window has no content yet; the rendering holds a reference to the host
// (the window's content) until it completes.
ACTIONUI_WINUI_API bool actionUIWinUIWindowRenderToPNG(ActionUIWinUIObject *window, const char *path,
                                                       ActionUIWinUICompletion completion, void *context);
// The same, scaled down so that neither side is larger than `maxPixels` (0: no cap), keeping its shape.
ACTIONUI_WINUI_API bool actionUIWinUIWindowRenderToPNGWithin(ActionUIWinUIObject *window, const char *path,
                                                             uint32_t maxPixels, ActionUIWinUICompletion completion,
                                                             void *context);

#ifdef __cplusplus
}
#endif

#endif /* ACTIONUI_WINUI_SHIM_H */

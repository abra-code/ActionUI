// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIApp.h
//  ActionUIAppKitApplication
//
//  C types for the AppKit application lifecycle adapter.
//
//  The types and a prototype for every function, so plain C clients can call it. The Swift
//  compiler also declares the @c functions, in ActionUIAppKitApplication-Swift.h (on Linux,
//  ActionUIAdwaitaApplication-Swift.h). The two declarations must agree:
//  HeaderCheck/ActionUIAppHeaderCheck.c includes both, so a differing type fails the build, and
//  Scripts/check-c-prototypes.sh checks the two lists of names agree.
//
//  Bool: all the functions use Swift's CBool (= stdbool.h bool).
//

#ifndef ActionUIApp_h
#define ActionUIApp_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - App lifecycle callbacks

/// No-argument void callback used for all simple lifecycle events.
typedef void (*ActionUIAppLifecycleHandler)(void);

/// Return true to allow termination, false to cancel.
typedef bool (*ActionUIAppShouldTerminateHandler)(void);

// MARK: - Window callbacks

/// Fired when a tracked window is about to close.
/// windowUUID - the UUID that was passed to actionUIAppLoadAndPresentWindow.
typedef void (*ActionUIAppWindowHandler)(const char* windowUUID);

// The Swift-generated declarations are noexcept in C++, so these are too: a C++ or
// Objective-C++ client that includes both would otherwise see conflicting declarations.
#ifndef ACTIONUI_NOEXCEPT
#  if defined(__cplusplus) && __cplusplus >= 201103L
#    define ACTIONUI_NOEXCEPT noexcept
#  else
#    define ACTIONUI_NOEXCEPT
#  endif
#endif

// MARK: - Functions
//
// Strings are null-terminated UTF-8. A returned `char *` is the caller's: free it with
// actionUIFreeString (ActionUIC.h). A returned `const char *` belongs to the library. Handlers
// may be NULL, which removes the handler.

// Lifecycle handlers
void actionUIAppSetWillFinishLaunchingHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetDidFinishLaunchingHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetWillBecomeActiveHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetDidBecomeActiveHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetWillResignActiveHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetDidResignActiveHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetWillTerminateHandler(ActionUIAppLifecycleHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetShouldTerminateHandler(ActionUIAppShouldTerminateHandler handler) ACTIONUI_NOEXCEPT;
void actionUIAppSetWindowWillCloseHandler(ActionUIAppWindowHandler handler) ACTIONUI_NOEXCEPT;  // read the window's values here: its model is removed after the handler returns
void actionUIAppSetWindowWillPresentHandler(ActionUIAppWindowHandler handler) ACTIONUI_NOEXCEPT;

// The application
void actionUIAppSetName(const char *name) ACTIONUI_NOEXCEPT;
void actionUIAppSetApplicationID(const char *applicationID) ACTIONUI_NOEXCEPT;  // reverse DNS; needed on Linux, nothing on Apple (the bundle identifier)
void actionUIAppSetIcon(const char *path) ACTIONUI_NOEXCEPT;
void actionUIAppSetResourceFolder(const char *path) ACTIONUI_NOEXCEPT;  // the folder of the app's resources, looked up first (Apple: then the main bundle; Linux: else the program's folder); an interpreted host passes its script's; NULL: the platform's own place only
void actionUIAppRun(void) ACTIONUI_NOEXCEPT;
void actionUIAppTerminate(void) ACTIONUI_NOEXCEPT;
void actionUIAppLoadMenuBar(const char *jsonString) ACTIONUI_NOEXCEPT;  // jsonString may be NULL; Linux: the commands go in each window's primary menu (GNOME has no menu bar)

// Windows
void actionUIAppLoadAndPresentWindow(const char *urlString, const char *windowUUID, const char *title) ACTIONUI_NOEXCEPT;  // title may be NULL
void actionUIAppLoadAndPresentWindowFromJSON(const char *jsonString, const char *windowUUID, const char *title) ACTIONUI_NOEXCEPT;  // title may be NULL
void actionUIAppCloseWindow(const char *windowUUID) ACTIONUI_NOEXCEPT;

// Alerts and file panels (configJSON may be NULL)
char *actionUIAppRunAlert(const char *configJSON) ACTIONUI_NOEXCEPT;
char *actionUIAppRunOpenPanel(const char *configJSON) ACTIONUI_NOEXCEPT;
char *actionUIAppRunSavePanel(const char *configJSON) ACTIONUI_NOEXCEPT;

// The remote server (socketPath may be NULL for the default)
bool actionUIAppStartRemoteServer(const char *socketPath) ACTIONUI_NOEXCEPT;
void actionUIAppStopRemoteServer(void) ACTIONUI_NOEXCEPT;
const char *actionUIAppRemoteServerToken(void) ACTIONUI_NOEXCEPT;
bool actionUIAppRemoteCopyServerToken(char *outToken, long outTokenSize) ACTIONUI_NOEXCEPT;  // false if outToken is NULL or too small; long is ptrdiff_t (Swift Int) on 64-bit platforms
const char *actionUIAppRemoteServerEndpoint(void) ACTIONUI_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#endif /* ActionUIApp_h */

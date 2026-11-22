// ActionUIWinUI/Apps/CAppCheck/main.c
//
// Runs ActionUI's application on Windows as a C host does (ActionUIApp.h and ActionUIC.h, both in
// ActionUI.dll): presents one window from JSON and one from a file once the application has started,
// sets and reads a value in the first through the C adapter and closes both (the host's closing does
// not end the application); then presents a window from a server, reads its value once it is shown,
// and closes it as the user does (the system close command): shouldTerminate's first answer keeps it open, its second
// lets the application end. Checks the handlers after the run. Usage: ActionUIAppCheck WINDOW.json URL.
// Prints "c-app:" lines; exit status 0 when every check passed. Built and run by Scripts/ci-windows.py.

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <windows.h>

#include "ActionUIApp.h"
#include "ActionUIC.h"

static int failures = 0;
static const char *windowFile = NULL;
static const char *remoteURL = NULL;
static int shouldTerminateAsked = 0;
static bool remoteChecked = false;
static int willFinish = 0;
static int didFinish = 0;
static int presented = 0;
static int closedCount = 0;
static int terminated = 0;
static char valueAtClose[64] = "";

static void check(bool passed, const char *what) {
    printf("c-app: %s: %s\n", passed ? "ok" : "FAILED", what);
    fflush(stdout);
    if (!passed) {
        failures += 1;
    }
}

static void CALLBACK onRemoteShown(HWND window, UINT message, UINT_PTR timer, DWORD time);

static void onWillFinishLaunching(void) {
    willFinish += 1;
}

static void onWillPresent(const char *windowUUID) {
    presented += 1;
    printf("c-app: presenting %s\n", windowUUID);
    // Once it is on screen (after this handler and the window's setup).
    if (strcmp(windowUUID, "remote-window") == 0) {
        SetTimer(NULL, 0, 500, onRemoteShown);
    }
}

// The window's values are still readable here: its model is removed after the handler returns.
static void onWillClose(const char *windowUUID) {
    closedCount += 1;
    printf("c-app: closing %s\n", windowUUID);
    if (strcmp(windowUUID, "json-window") == 0) {
        char *value = actionUIGetStringValue(windowUUID, 2, 0);
        if (value != NULL) {
            snprintf(valueAtClose, sizeof valueAtClose, "%s", value);
            actionUIFreeString(value);
        }
    }
    fflush(stdout);
}

static void onWillTerminate(void) {
    terminated += 1;
}

// The first answer keeps the last window open; the second lets the application end.
static bool onShouldTerminate(void) {
    shouldTerminateAsked += 1;
    printf("c-app: shouldTerminate asked (%d)\n", shouldTerminateAsked);
    fflush(stdout);
    return shouldTerminateAsked >= 2;
}

// Closes the window titled "From a server" as the user does: the close button's system command
// (SC_CLOSE, which then sends WM_CLOSE).
static bool closeAsTheUser(void) {
    HWND window = FindWindowW(NULL, L"From a server");
    if (window == NULL) {
        return false;
    }
    return PostMessageW(window, WM_SYSCOMMAND, SC_CLOSE, 0) != 0;
}

static void CALLBACK onSecondClose(HWND window, UINT message, UINT_PTR timer, DWORD time) {
    (void)window; (void)message; (void)time;
    KillTimer(NULL, timer);
    check(FindWindowW(NULL, L"From a server") != NULL, "the window stayed open when shouldTerminate said no");
    check(closeAsTheUser(), "the user closes it again");
}

static void CALLBACK onRemoteShown(HWND window, UINT message, UINT_PTR timer, DWORD time) {
    (void)window; (void)message; (void)time;
    KillTimer(NULL, timer);
    remoteChecked = true;
    // Remote.json's Text (id 130), loaded from the server.
    char *value = actionUIGetStringValue("remote-window", 130, 0);
    check(value != NULL && strcmp(value, "Loaded over HTTPS") == 0, "the window from a server shows its document");
    if (value != NULL) {
        actionUIFreeString(value);
    }
    check(closeAsTheUser(), "the user closes the last window");
    SetTimer(NULL, 0, 700, onSecondClose);
}

static void onDidFinishLaunching(void) {
    didFinish += 1;
    actionUIAppLoadAndPresentWindowFromJSON(
        "{\"type\": \"VStack\", \"id\": 1, \"properties\": {\"padding\": 16}, \"children\": ["
        "{\"type\": \"Text\", \"id\": 2, \"properties\": {\"text\": \"A window from JSON\"}}]}",
        "json-window", "From JSON");
    // The adapter reaches the window the application functions made: one ActionUI in the DLL.
    check(actionUISetStringValue("json-window", 2, 0, "set from C"), "a value is set in the window");
    char *value = actionUIGetStringValue("json-window", 2, 0);
    check(value != NULL && strcmp(value, "set from C") == 0, "the value reads back");
    if (value != NULL) {
        actionUIFreeString(value);
    }
    actionUIAppLoadAndPresentWindow(windowFile, "file-window", NULL);
    // The host closing its windows does not end the application (as on Apple and Linux): the window
    // from the server comes after.
    actionUIAppCloseWindow("json-window");
    actionUIAppCloseWindow("file-window");
    actionUIAppLoadAndPresentWindow(remoteURL, "remote-window", "From a server");
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("c-app: usage: ActionUIAppCheck WINDOW.json URL\n");
        return 64;
    }
    windowFile = argv[1];
    remoteURL = argv[2];
    actionUIAppSetName("C app check");
    actionUIAppSetWillFinishLaunchingHandler(onWillFinishLaunching);
    actionUIAppSetDidFinishLaunchingHandler(onDidFinishLaunching);
    actionUIAppSetWindowWillPresentHandler(onWillPresent);
    actionUIAppSetWindowWillCloseHandler(onWillClose);
    actionUIAppSetWillTerminateHandler(onWillTerminate);
    actionUIAppSetShouldTerminateHandler(onShouldTerminate);
    printf("c-app: running\n");
    fflush(stdout);
    actionUIAppRun();
    printf("c-app: the run returned\n");
    check(willFinish == 1 && didFinish == 1, "the launch handlers fired once");
    check(presented == 3, "the three windows were presented");
    check(closedCount == 3, "the three windows closed");
    check(strcmp(valueAtClose, "set from C") == 0, "the value was readable as its window closed");
    check(remoteChecked, "the window from a server was shown");
    check(shouldTerminateAsked == 2, "shouldTerminate was asked at each of the user's closings of the last window");
    check(terminated == 1, "the willTerminate handler fired");
    printf("c-app: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}

// ActionUIWinUI/Apps/CAppCheck/main.c
//
// Runs ActionUI's application on Windows as a C host does (ActionUIApp.h and ActionUIC.h, both in
// ActionUI.dll): presents one window from JSON and one from a file once the application has
// started, sets and reads a value in the first through the C adapter, closes both and terminates, and
// checks that the handlers fired. Usage: ActionUIAppCheck WINDOW.json.
// Prints "c-app:" lines; exit status 0 when every check passed. Built and run by Scripts/ci-windows.py.

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "ActionUIApp.h"
#include "ActionUIC.h"

static int failures = 0;
static const char *windowFile = NULL;
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

static void onWillFinishLaunching(void) {
    willFinish += 1;
}

static void onWillPresent(const char *windowUUID) {
    presented += 1;
    printf("c-app: presenting %s\n", windowUUID);
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
    // The host closing its windows does not end the application (as on Apple and Linux): terminate does.
    actionUIAppCloseWindow("json-window");
    actionUIAppCloseWindow("file-window");
    actionUIAppTerminate();
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("c-app: usage: ActionUIAppCheck WINDOW.json\n");
        return 64;
    }
    windowFile = argv[1];
    actionUIAppSetName("C app check");
    actionUIAppSetWillFinishLaunchingHandler(onWillFinishLaunching);
    actionUIAppSetDidFinishLaunchingHandler(onDidFinishLaunching);
    actionUIAppSetWindowWillPresentHandler(onWillPresent);
    actionUIAppSetWindowWillCloseHandler(onWillClose);
    actionUIAppSetWillTerminateHandler(onWillTerminate);
    printf("c-app: running\n");
    fflush(stdout);
    actionUIAppRun();
    printf("c-app: the run returned\n");
    check(willFinish == 1 && didFinish == 1, "the launch handlers fired once");
    check(presented == 2, "both windows were presented");
    check(closedCount == 2, "both windows closed");
    check(strcmp(valueAtClose, "set from C") == 0, "the value was readable as its window closed");
    check(terminated == 1, "the willTerminate handler fired");
    printf("c-app: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}

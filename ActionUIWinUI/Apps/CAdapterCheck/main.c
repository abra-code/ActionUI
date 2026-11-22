// ActionUIWinUI/Apps/CAdapterCheck/main.c
//
// Calls the C adapter (ActionUIC.h) on Windows as a C host does, through ActionUI.dll and its
// import library: the version, the configuration (set, read back, refused), the calling thread's last
// error kept apart from another thread's, and a call that goes to the main actor from the main thread.
// Prints "c-adapter:" lines; exit status 0 when every check passed. Built and run by
// Scripts/ci-windows.py beside the DLL.

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <windows.h>

#include "ActionUIC.h"

static int failures = 0;

static void check(bool passed, const char *what) {
    printf("c-adapter: %s: %s\n", passed ? "ok" : "FAILED", what);
    fflush(stdout);
    if (!passed) {
        failures += 1;
    }
}

// The last error a refused configuration leaves on the thread that asked: set there, and nowhere else.
static DWORD WINAPI refuseOnAnotherThread(LPVOID context) {
    bool *passed = (bool *)context;
    bool refused = !actionUISetConfigurationJSON("{\"noSuchKey\": 1}");
    char *error = actionUIGetLastError();
    *passed = refused && error != NULL;
    if (error != NULL) {
        actionUIFreeString(error);
    }
    return 0;
}

int main(void) {
    char *version = actionUIGetVersion();
    check(version != NULL && version[0] != '\0', "the version");
    if (version != NULL) {
        printf("c-adapter: version %s\n", version);
        actionUIFreeString(version);
    }

    check(actionUISetConfigurationJSON("{\"limits\": {\"maximumNestingDepth\": 8}}"), "the configuration is set");
    char *configuration = actionUIGetConfigurationJSON();
    bool readBack = configuration != NULL && (strstr(configuration, "\"maximumNestingDepth\":8") != NULL
                                              || strstr(configuration, "\"maximumNestingDepth\" : 8") != NULL);
    check(readBack, "the configuration reads back");
    if (configuration != NULL) {
        printf("c-adapter: configuration %s\n", configuration);
        actionUIFreeString(configuration);
    }

    check(!actionUISetConfigurationJSON("{\"noSuchKey\": 1}"), "an unknown key is refused");
    char *error = actionUIGetLastError();
    check(error != NULL, "the refusal leaves an error");
    if (error != NULL) {
        printf("c-adapter: error %s\n", error);
        actionUIFreeString(error);
    }
    actionUIClearError();
    error = actionUIGetLastError();
    check(error == NULL, "the error is cleared");
    if (error != NULL) {
        actionUIFreeString(error);
    }

    bool otherThreadPassed = false;
    HANDLE thread = CreateThread(NULL, 0, refuseOnAnotherThread, &otherThreadPassed, 0, NULL);
    check(thread != NULL, "another thread starts");
    if (thread != NULL) {
        check(WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0, "the other thread ends");
        CloseHandle(thread);
    }
    check(otherThreadPassed, "the other thread has its own error");
    error = actionUIGetLastError();
    check(error == NULL, "this thread's error is not the other thread's");
    if (error != NULL) {
        actionUIFreeString(error);
    }

    // Goes to the main actor: run at once on the main thread (it would wait forever for a main queue
    // nothing drains if the main thread were not recognized). An element origin, not a value: an
    // unknown window's value is NULL with no error set ("nothing found"), its origin is an error.
    printf("c-adapter: asking an element's origin on the main thread\n");
    fflush(stdout);
    char *value = actionUIGetElementOrigin("no-such-window", 1);
    error = actionUIGetLastError();
    check(value == NULL && error != NULL, "an element origin in an unknown window is an error, on the main thread");
    if (error != NULL) {
        printf("c-adapter: error %s\n", error);
        actionUIFreeString(error);
    }
    if (value != NULL) {
        actionUIFreeString(value);
    }

    printf("c-adapter: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}

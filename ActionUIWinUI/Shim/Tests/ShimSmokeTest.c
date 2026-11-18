// ShimSmokeTest.c - drives the WinUI shim from plain C: starts WinUI, opens a window with a
// TextBlock, renders it into a PNG and quits. Also checks that ActionUIWinUIShim.h is valid C, and
// that an event registration frees its context exactly once on every path.
//
// Usage: ShimSmokeTest.exe PNG_PATH
// Prints "smoke:" lines; exit status 0 when every step worked and the PNG is not empty.

#include <stdbool.h>
#include <stdio.h>

#include "ActionUIWinUIShim.h"

typedef struct SmokeState {
    const char *pngPath;
    ActionUIWinUIObject *window;
    ActionUIWinUIObject *text;
    bool rendered;
    bool eventsFreed;
} SmokeState;

static void printLastError(const char *where);

static int g_handlerCalls = 0;
static int g_contextsFreed = 0;

static void countHandler(void *context) {
    (void)context;
    g_handlerCalls += 1;
}

static void countFreed(void *context) {
    (void)context;
    g_contextsFreed += 1;
}

// An event registration frees its context exactly once: when it fails (no control, no handler),
// at once; when it succeeds, once the control is gone. True when the failure cases did and the
// successful one kept its context; the release is checked later (finish), since XAML may destroy a
// released control after the call returns.
static bool checkEventContexts(void) {
    g_contextsFreed = 0;
    bool registered = actionUIWinUIButtonOnClick(NULL, countHandler, NULL, countFreed);
    bool noControl = !registered && g_contextsFreed == 1;

    ActionUIWinUIObject *button = actionUIWinUIButtonCreate();
    if (button == NULL) {
        printLastError("button create");
        return false;
    }
    g_contextsFreed = 0;
    registered = actionUIWinUIButtonOnClick(button, NULL, NULL, countFreed);
    bool noHandler = !registered && g_contextsFreed == 1;

    g_contextsFreed = 0;
    registered = actionUIWinUIButtonOnClick(button, countHandler, NULL, countFreed);
    bool keptWhileAlive = registered && g_contextsFreed == 0;
    actionUIWinUIRelease(button);

    printf("smoke: event contexts freed: no control %s, no handler %s, kept while alive %s\n",
           noControl ? "yes" : "NO", noHandler ? "yes" : "NO", keptWhileAlive ? "yes" : "NO");
    fflush(stdout);
    return noControl && noHandler && keptWhileAlive;
}

static void printLastError(const char *where) {
    char message[512];
    bool copied = actionUIWinUICopyLastError(message, (ptrdiff_t)sizeof(message));
    printf("smoke: %s failed: %s\n", where, copied ? message : "(no message)");
    fflush(stdout);
}

// Releases the window and the text, then quits. On the UI thread.
static void finish(SmokeState *state) {
    // The released button of checkEventContexts is gone by now: its context was freed once.
    bool freedWithControl = g_contextsFreed == 1 && g_handlerCalls == 0;
    printf("smoke: event context freed with its control: %s (%d frees, %d handler calls)\n",
           freedWithControl ? "yes" : "NO", g_contextsFreed, g_handlerCalls);
    fflush(stdout);
    state->eventsFreed = state->eventsFreed && freedWithControl;
    if (state->window != NULL) {
        bool closed = actionUIWinUIWindowClose(state->window);
        if (!closed) {
            printLastError("window close");
        }
    }
    actionUIWinUIRelease(state->text);
    actionUIWinUIRelease(state->window);
    state->text = NULL;
    state->window = NULL;
    actionUIWinUIQuit();
}

static void onRendered(void *context, bool succeeded) {
    SmokeState *state = (SmokeState *)context;
    state->rendered = succeeded;
    if (succeeded) {
        printf("smoke: rendered %s\n", state->pngPath);
        fflush(stdout);
    } else {
        printLastError("render to PNG");
    }
    finish(state);
}

static void onLaidOut(void *context) {
    SmokeState *state = (SmokeState *)context;
    bool started = actionUIWinUIRenderToPNG(state->text, state->pngPath, onRendered, state);
    if (!started) {
        printLastError("render to PNG (start)");
        finish(state);
    }
}

static void onLaunched(void *context) {
    SmokeState *state = (SmokeState *)context;
    printf("smoke: launched\n");
    fflush(stdout);
    state->eventsFreed = checkEventContexts();
    state->window = actionUIWinUIWindowCreate();
    state->text = actionUIWinUITextBlockCreate();
    if (state->window == NULL || state->text == NULL) {
        printLastError(state->window == NULL ? "window create" : "text block create");
        finish(state);
        return;
    }
    bool ok = actionUIWinUIWindowSetTitle(state->window, "ActionUI WinUI shim");
    ok = ok && actionUIWinUIWindowSetContentSize(state->window, 480, 160);
    ok = ok && actionUIWinUITextBlockSetText(state->text, "ActionUI on WinUI 3, from C");
    ok = ok && actionUIWinUIWindowSetContent(state->window, state->text);
    ok = ok && actionUIWinUIWindowActivate(state->window);
    // Wait for the first layout pass before rendering.
    ok = ok && actionUIWinUIPostDelayed(500, onLaidOut, state);
    if (!ok) {
        printLastError("window setup");
        finish(state);
    }
}

static long fileSize(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return -1;
    }
    long size = -1;
    if (fseek(file, 0, SEEK_END) == 0) {
        size = ftell(file);
    }
    fclose(file);
    return size;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s PNG_PATH\n", argv[0]);
        return 64;
    }
    SmokeState state = {argv[1], NULL, NULL, false, false};
    remove(state.pngPath);

    bool initialized = actionUIWinUIInitialize();
    if (!initialized) {
        printLastError("initialize");
        return 1;
    }
    bool ran = actionUIWinUIRun(onLaunched, &state);
    if (!ran) {
        printLastError("run");
    }
    actionUIWinUIShutdown();

    long size = fileSize(state.pngPath);
    printf("smoke: run %s, rendered %s, PNG %ld bytes, event contexts %s\n", ran ? "ok" : "failed",
           state.rendered ? "yes" : "no", size, state.eventsFreed ? "ok" : "WRONG");
    bool passed = ran && state.rendered && size > 0 && state.eventsFreed;
    return passed ? 0 : 1;
}

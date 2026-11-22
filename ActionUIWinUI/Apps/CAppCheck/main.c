// ActionUIWinUI/Apps/CAppCheck/main.c
//
// Runs ActionUI's application on Windows as a C host does (ActionUIApp.h and ActionUIC.h, both in
// ActionUI.dll): presents one window from JSON and one from a file once the application has started,
// sets and reads a value in the first through the C adapter and closes both (the host's closing does
// not end the application); then presents a window from a server, reads its value once it is shown,
// and closes it as the user does (the system close command): shouldTerminate's first answer keeps it open, its second
// lets the application end. Checks the handlers after the run. Runs alerts too (actionUIAppRunAlert): before the
// run, with no window, over a window and with four buttons, each answered as an accessibility tool does (UI
// Automation's Invoke on the button, from a thread of its own while the call waits). Usage: ActionUIAppCheck
// WINDOW.json URL.
// Prints "c-app:" lines; exit status 0 when every check passed. Built and run by Scripts/ci-windows.py.

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define COBJMACROS
#include <windows.h>
#include <UIAutomation.h>

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

// MARK: - Answering an alert as an accessibility tool does

// UI Automation's class and interfaces (UIAutomationClient.h), defined here so nothing more is linked.
static const CLSID automationClass = {0xff48dba4, 0x60ef, 0x4201, {0xaa, 0x87, 0x54, 0x10, 0x3e, 0xef, 0x59, 0x4e}};
static const IID automationInterface = {0x30cbe57d, 0xd9d0, 0x452a, {0xab, 0x13, 0x7a, 0xc5, 0xac, 0x48, 0x25, 0xee}};
static const IID invokeInterface = {0xfb377fbe, 0x8ea6, 0x46d5, {0x9c, 0x73, 0x64, 0x99, 0x64, 0x2d, 0x30, 0x59}};

// What the answering thread did, and the name of the element that had the keyboard focus before it
// answered (the default button, which Enter presses), read once the alert has returned.
static char answerReport[160] = "";
static char focusedName[64] = "";
// The focus was in another program's window (one in front of this program's, as a test runner may keep).
static bool focusElsewhere = false;

// Notes the focused element's name in focusedName.
static void noteFocus(IUIAutomation *automation) {
    IUIAutomationElement *focused = NULL;
    HRESULT got = IUIAutomation_GetFocusedElement(automation, &focused);
    if (FAILED(got) || focused == NULL) {
        snprintf(focusedName, sizeof focusedName, "(none)");
        return;
    }
    int process = 0;
    got = IUIAutomationElement_get_CurrentProcessId(focused, &process);
    focusElsewhere = SUCCEEDED(got) && process != (int)GetCurrentProcessId();
    BSTR name = NULL;
    got = IUIAutomationElement_get_CurrentName(focused, &name);
    if (SUCCEEDED(got) && name != NULL) {
        snprintf(focusedName, sizeof focusedName, "%ls", name);
        SysFreeString(name);
    } else {
        snprintf(focusedName, sizeof focusedName, "(no name)");
    }
    IUIAutomationElement_Release(focused);
}

static IUIAutomationCondition *propertyCondition(IUIAutomation *automation, PROPERTYID property, VARIANT value) {
    IUIAutomationCondition *condition = NULL;
    HRESULT made = IUIAutomation_CreatePropertyCondition(automation, property, value, &condition);
    return SUCCEEDED(made) ? condition : NULL;
}

// The button of this process named `name`, once it is on screen (up to 10 seconds); NULL if it never is.
static IUIAutomationElement *findButton(IUIAutomation *automation, const wchar_t *name) {
    IUIAutomationElement *root = NULL;
    HRESULT got = IUIAutomation_GetRootElement(automation, &root);
    if (FAILED(got) || root == NULL) {
        return NULL;
    }
    VARIANT title;
    VariantInit(&title);
    title.vt = VT_BSTR;
    title.bstrVal = SysAllocString(name);
    VARIANT type;
    VariantInit(&type);
    type.vt = VT_I4;
    type.lVal = UIA_ButtonControlTypeId;
    VARIANT process;
    VariantInit(&process);
    process.vt = VT_I4;
    process.lVal = (LONG)GetCurrentProcessId();
    IUIAutomationCondition *named = propertyCondition(automation, UIA_NamePropertyId, title);
    IUIAutomationCondition *button = propertyCondition(automation, UIA_ControlTypePropertyId, type);
    IUIAutomationCondition *ours = propertyCondition(automation, UIA_ProcessIdPropertyId, process);
    VariantClear(&title);
    IUIAutomationCondition *namedButton = NULL;
    IUIAutomationCondition *condition = NULL;
    if (named != NULL && button != NULL && ours != NULL) {
        HRESULT joined = IUIAutomation_CreateAndCondition(automation, named, button, &namedButton);
        if (SUCCEEDED(joined) && namedButton != NULL) {
            joined = IUIAutomation_CreateAndCondition(automation, namedButton, ours, &condition);
            if (FAILED(joined)) {
                condition = NULL;
            }
        }
    }
    IUIAutomationElement *found = NULL;
    for (int attempt = 0; condition != NULL && found == NULL && attempt < 100; attempt++) {
        HRESULT searched = IUIAutomationElement_FindFirst(root, TreeScope_Descendants, condition, &found);
        if (FAILED(searched)) {
            found = NULL;
        }
        if (found == NULL) {
            Sleep(100);
        }
    }
    IUIAutomationCondition *conditions[] = {named, button, ours, namedButton, condition};
    for (size_t index = 0; index < sizeof conditions / sizeof conditions[0]; index++) {
        if (conditions[index] != NULL) {
            IUIAutomationCondition_Release(conditions[index]);
        }
    }
    IUIAutomationElement_Release(root);
    return found;
}

// Prints what the answering thread could not do, at once: the alert it leaves unanswered keeps the call
// waiting until the CI step's timeout ends the program.
static DWORD answerFailed(void) {
    printf("c-app: answering the alert: %s\n", answerReport);
    fflush(stdout);
    return 1;
}

// The answering thread: invokes the button named `parameter` once it appears.
static DWORD WINAPI answerAlert(void *parameter) {
    const wchar_t *name = parameter;
    HRESULT initialized = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(initialized)) {
        snprintf(answerReport, sizeof answerReport, "COM did not start (0x%08lx)", (unsigned long)initialized);
        return answerFailed();
    }
    IUIAutomation *automation = NULL;
    HRESULT made = CoCreateInstance(&automationClass, NULL, CLSCTX_INPROC_SERVER, &automationInterface, (void **)&automation);
    if (FAILED(made) || automation == NULL) {
        snprintf(answerReport, sizeof answerReport, "UI Automation did not start (0x%08lx)", (unsigned long)made);
        CoUninitialize();
        return answerFailed();
    }
    bool answered = false;
    IUIAutomationElement *found = findButton(automation, name);
    if (found == NULL) {
        snprintf(answerReport, sizeof answerReport, "the button %ls did not appear", name);
    } else {
        // The dialog's first focus settles once it has opened.
        Sleep(500);
        noteFocus(automation);
        IUnknown *pattern = NULL;
        IUIAutomationInvokePattern *invoke = NULL;
        HRESULT got = IUIAutomationElement_GetCurrentPattern(found, UIA_InvokePatternId, &pattern);
        if (SUCCEEDED(got) && pattern != NULL) {
            got = IUnknown_QueryInterface(pattern, &invokeInterface, (void **)&invoke);
            IUnknown_Release(pattern);
        }
        if (FAILED(got) || invoke == NULL) {
            snprintf(answerReport, sizeof answerReport, "the button %ls cannot be invoked (0x%08lx)", name, (unsigned long)got);
        } else {
            HRESULT invoked = IUIAutomationInvokePattern_Invoke(invoke);
            if (SUCCEEDED(invoked)) {
                answered = true;
                snprintf(answerReport, sizeof answerReport, "invoked %ls", name);
            } else {
                snprintf(answerReport, sizeof answerReport, "invoking %ls failed (0x%08lx)", name, (unsigned long)invoked);
            }
            IUIAutomationInvokePattern_Release(invoke);
        }
        IUIAutomationElement_Release(found);
    }
    IUIAutomation_Release(automation);
    CoUninitialize();
    return answered ? 0 : answerFailed();
}

// Runs the alert `json` while a thread of its own invokes its button `answer`; checks that the call
// returned that button's title, and that the button `focus` (the default) had the keyboard focus.
static void checkAlert(const char *json, const wchar_t *answer, const char *expected, const char *focus, const char *what) {
    answerReport[0] = '\0';
    focusedName[0] = '\0';
    focusElsewhere = false;
    HANDLE thread = CreateThread(NULL, 0, answerAlert, (void *)answer, 0, NULL);
    if (thread == NULL) {
        check(false, "the answering thread started");
        return;
    }
    char *chosen = actionUIAppRunAlert(json);
    WaitForSingleObject(thread, 15000);
    CloseHandle(thread);
    printf("c-app: %s: answered \"%s\" (%s; the focus on \"%s\")\n", what, chosen != NULL ? chosen : "(null)",
           answerReport, focusedName);
    check(chosen != NULL && strcmp(chosen, expected) == 0, what);
    if (focusElsewhere) {
        printf("c-app: the focus is in another program's window: the default button's focus not checked\n");
    } else {
        check(strcmp(focusedName, focus) == 0, "the alert's default button has the focus");
    }
    if (chosen != NULL) {
        actionUIFreeString(chosen);
    }
}

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

// Prints which loaded Windows App SDK module exports ContentPreTranslateMessage (keyboard handling before
// dispatch), which the alert's nested message loop looks up the same way, for the log.
static void reportPreTranslate(void) {
    const wchar_t *const modules[] = {L"Microsoft.UI.Windowing.Core.dll", L"Microsoft.Internal.FrameworkUdk.dll",
                                      L"Microsoft.UI.Input.dll", L"Microsoft.UI.Xaml.dll"};
    for (size_t index = 0; index < sizeof modules / sizeof modules[0]; index++) {
        HMODULE module = GetModuleHandleW(modules[index]);
        if (module != NULL && GetProcAddress(module, "ContentPreTranslateMessage") != NULL) {
            printf("c-app: ContentPreTranslateMessage is in %ls\n", modules[index]);
            fflush(stdout);
            return;
        }
    }
    printf("c-app: ContentPreTranslateMessage is in none of the modules looked at\n");
    fflush(stdout);
}

static void onDidFinishLaunching(void) {
    didFinish += 1;
    reportPreTranslate();
    // No window yet: the alert opens in one of its own.
    checkAlert("{\"title\": \"No window\", \"message\": \"An alert before any window.\", "
               "\"buttons\": [\"OK\", \"Later\", \"Cancel\"]}",
               L"Later", "Later", "OK", "an alert with no window answers its second button");
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
    // Over the window just presented (shown once it has loaded); Cancel is the close button.
    checkAlert("{\"title\": \"Save changes?\", \"buttons\": [\"Save\", \"Don't Save\", \"Cancel\"]}",
               L"Cancel", "Cancel", "Save", "an alert over a window answers Cancel");
    // A fourth button goes in the content, with the third.
    checkAlert("{\"title\": \"Four buttons\", \"buttons\": [\"One\", \"Two\", \"Three\", \"Four\"]}",
               L"Four", "Four", "One", "an alert's fourth button answers");
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
    char *early = actionUIAppRunAlert("{\"title\": \"Too early\"}");
    check(early == NULL, "an alert before the run answers NULL");
    if (early != NULL) {
        actionUIFreeString(early);
    }
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

// ActionUIWinUI/Apps/CAppCheck/main.c
//
// Runs ActionUI's application on Windows as a C host does (ActionUIApp.h and ActionUIC.h, both in
// ActionUI.dll): presents one window from JSON and one from a file once the application has started,
// sets and reads a value in the first through the C adapter and closes both (the host's closing does
// not end the application); then presents a window from a server, reads its value once it is shown,
// and closes it as the user does (the system close command): shouldTerminate's first answer keeps it open, its second
// lets the application end. Checks the handlers after the run. Runs alerts too (actionUIAppRunAlert): before the
// run, with no window, over a window and with four buttons; and file panels (actionUIAppRunOpenPanel,
// actionUIAppRunSavePanel): open, save, cancel, a folder. Each is answered as an accessibility tool does (UI
// Automation's Invoke on a button, its Value on the name field, from a thread of its own while the call waits).
// Reads a TextField and a SecureField of the first window as a screen reader does: the TextField gives its
// text, the SecureField says it is a password and gives none of its text.
// Usage: ActionUIAppCheck WINDOW.json URL.
// Prints "c-app:" lines; exit status 0 when every check passed. Built and run by Scripts/ci-windows.py.

#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

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
static const IID valueInterface = {0xa94cd8b1, 0x0844, 0x4cd6, {0x9d, 0x2d, 0x64, 0x05, 0x37, 0xab, 0x39, 0xe9}};
static const IID textInterface = {0x32eba289, 0x3583, 0x42c9, {0x9c, 0x59, 0x3b, 0x6d, 0x9a, 0x1e, 0x9b, 0x6a}};

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

// The first element of this process under `root` (among its descendants) whose `property` is the text
// `value` and whose control type is `type`, once it is on screen (up to `tenths` tenths of a second); NULL
// if it never is. `root` NULL: the desktop.
static IUIAutomationElement *findElement(IUIAutomation *automation, IUIAutomationElement *root, PROPERTYID property,
                                         const wchar_t *value, CONTROLTYPEID type, int tenths) {
    IUIAutomationElement *desktop = NULL;
    if (root == NULL) {
        HRESULT got = IUIAutomation_GetRootElement(automation, &desktop);
        if (FAILED(got) || desktop == NULL) {
            return NULL;
        }
        root = desktop;
    }
    VARIANT text;
    VariantInit(&text);
    text.vt = VT_BSTR;
    text.bstrVal = SysAllocString(value);
    VARIANT kind;
    VariantInit(&kind);
    kind.vt = VT_I4;
    kind.lVal = type;
    VARIANT process;
    VariantInit(&process);
    process.vt = VT_I4;
    process.lVal = (LONG)GetCurrentProcessId();
    IUIAutomationCondition *matching = propertyCondition(automation, property, text);
    IUIAutomationCondition *typed = propertyCondition(automation, UIA_ControlTypePropertyId, kind);
    IUIAutomationCondition *ours = propertyCondition(automation, UIA_ProcessIdPropertyId, process);
    VariantClear(&text);
    IUIAutomationCondition *matchingTyped = NULL;
    IUIAutomationCondition *condition = NULL;
    if (matching != NULL && typed != NULL && ours != NULL) {
        HRESULT joined = IUIAutomation_CreateAndCondition(automation, matching, typed, &matchingTyped);
        if (SUCCEEDED(joined) && matchingTyped != NULL) {
            joined = IUIAutomation_CreateAndCondition(automation, matchingTyped, ours, &condition);
            if (FAILED(joined)) {
                condition = NULL;
            }
        }
    }
    IUIAutomationElement *found = NULL;
    for (int attempt = 0; condition != NULL && found == NULL && attempt < tenths; attempt++) {
        HRESULT searched = IUIAutomationElement_FindFirst(root, TreeScope_Descendants, condition, &found);
        if (FAILED(searched)) {
            found = NULL;
        }
        if (found == NULL) {
            Sleep(100);
        }
    }
    IUIAutomationCondition *conditions[] = {matching, typed, ours, matchingTyped, condition};
    for (size_t index = 0; index < sizeof conditions / sizeof conditions[0]; index++) {
        if (conditions[index] != NULL) {
            IUIAutomationCondition_Release(conditions[index]);
        }
    }
    if (desktop != NULL) {
        IUIAutomationElement_Release(desktop);
    }
    return found;
}

// The button of this process named `name`, once it is on screen (up to 10 seconds); NULL if it never is.
static IUIAutomationElement *findButton(IUIAutomation *automation, const wchar_t *name) {
    return findElement(automation, NULL, UIA_NamePropertyId, name, UIA_ButtonControlTypeId, 100);
}

// Invokes `element` (UI Automation's Invoke pattern), as an accessibility tool presses a button.
static HRESULT invokeElement(IUIAutomationElement *element) {
    IUnknown *pattern = NULL;
    IUIAutomationInvokePattern *invoke = NULL;
    HRESULT got = IUIAutomationElement_GetCurrentPattern(element, UIA_InvokePatternId, &pattern);
    if (SUCCEEDED(got) && pattern != NULL) {
        got = IUnknown_QueryInterface(pattern, &invokeInterface, (void **)&invoke);
        IUnknown_Release(pattern);
    }
    if (FAILED(got) || invoke == NULL) {
        return FAILED(got) ? got : E_NOINTERFACE;
    }
    HRESULT invoked = IUIAutomationInvokePattern_Invoke(invoke);
    IUIAutomationInvokePattern_Release(invoke);
    return invoked;
}

// Sets `element`'s text (UI Automation's Value pattern), as an accessibility tool types it.
static HRESULT setElementText(IUIAutomationElement *element, const wchar_t *text) {
    IUnknown *pattern = NULL;
    IUIAutomationValuePattern *value = NULL;
    HRESULT got = IUIAutomationElement_GetCurrentPattern(element, UIA_ValuePatternId, &pattern);
    if (SUCCEEDED(got) && pattern != NULL) {
        got = IUnknown_QueryInterface(pattern, &valueInterface, (void **)&value);
        IUnknown_Release(pattern);
    }
    if (FAILED(got) || value == NULL) {
        return FAILED(got) ? got : E_NOINTERFACE;
    }
    BSTR typed = SysAllocString(text);
    HRESULT set = IUIAutomationValuePattern_SetValue(value, typed);
    SysFreeString(typed);
    IUIAutomationValuePattern_Release(value);
    return set;
}

// Prints what the answering thread could not do, at once: the alert it leaves unanswered keeps the call
// waiting until the CI step's timeout ends the program.
static DWORD answerFailed(void) {
    printf("c-app: answering: %s\n", answerReport);
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
        HRESULT invoked = invokeElement(found);
        if (SUCCEEDED(invoked)) {
            answered = true;
            snprintf(answerReport, sizeof answerReport, "invoked %ls", name);
        } else {
            snprintf(answerReport, sizeof answerReport, "invoking %ls failed (0x%08lx)", name, (unsigned long)invoked);
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

// MARK: - Reading text fields as an accessibility tool does

// What the reading thread found: the plain field's value, and the secure field's value and password flag.
static wchar_t plainRead[64] = L"";
static wchar_t secretRead[64] = L"";
static wchar_t plainText[64] = L"";
static wchar_t secretText[64] = L"";
static bool secretIsPassword = false;
static bool secretFound = false;

// `element`'s value through UI Automation's Value pattern, into `out` (empty when it has none).
static void readElementValue(IUIAutomationElement *element, wchar_t *out, size_t count) {
    out[0] = L'\0';
    IUnknown *pattern = NULL;
    IUIAutomationValuePattern *value = NULL;
    HRESULT got = IUIAutomationElement_GetCurrentPattern(element, UIA_ValuePatternId, &pattern);
    if (SUCCEEDED(got) && pattern != NULL) {
        got = IUnknown_QueryInterface(pattern, &valueInterface, (void **)&value);
        IUnknown_Release(pattern);
    }
    if (FAILED(got) || value == NULL) {
        return;
    }
    BSTR text = NULL;
    if (SUCCEEDED(IUIAutomationValuePattern_get_CurrentValue(value, &text)) && text != NULL) {
        wcsncpy_s(out, count, text, _TRUNCATE);
        SysFreeString(text);
    }
    IUIAutomationValuePattern_Release(value);
}

// `element`'s whole text through UI Automation's Text pattern (what a screen reader reads by line or word),
// into `out` (empty when it has none).
static void readElementText(IUIAutomationElement *element, wchar_t *out, size_t count) {
    out[0] = L'\0';
    IUnknown *pattern = NULL;
    IUIAutomationTextPattern *text = NULL;
    HRESULT got = IUIAutomationElement_GetCurrentPattern(element, UIA_TextPatternId, &pattern);
    if (SUCCEEDED(got) && pattern != NULL) {
        got = IUnknown_QueryInterface(pattern, &textInterface, (void **)&text);
        IUnknown_Release(pattern);
    }
    if (FAILED(got) || text == NULL) {
        return;
    }
    IUIAutomationTextRange *range = NULL;
    if (SUCCEEDED(IUIAutomationTextPattern_get_DocumentRange(text, &range)) && range != NULL) {
        BSTR whole = NULL;
        if (SUCCEEDED(IUIAutomationTextRange_GetText(range, -1, &whole)) && whole != NULL) {
            wcsncpy_s(out, count, whole, _TRUNCATE);
            SysFreeString(whole);
        }
        IUIAutomationTextRange_Release(range);
    }
    IUIAutomationTextPattern_Release(text);
}

// The reading thread: finds the two fields by their automation IDs and reads them, as a screen reader
// does. The plain field is read until it shows the host's text (the window syncs after the host's set).
static DWORD WINAPI readTextFields(void *parameter) {
    (void)parameter;
    if (FAILED(CoInitializeEx(NULL, COINIT_MULTITHREADED))) {
        return 1;
    }
    IUIAutomation *automation = NULL;
    HRESULT made = CoCreateInstance(&automationClass, NULL, CLSCTX_INPROC_SERVER, &automationInterface, (void **)&automation);
    if (FAILED(made) || automation == NULL) {
        CoUninitialize();
        return 1;
    }
    IUIAutomationElement *plain = findElement(automation, NULL, UIA_AutomationIdPropertyId, L"plain-field", UIA_EditControlTypeId, 100);
    for (int attempt = 0; plain != NULL && attempt < 50; attempt++) {
        readElementValue(plain, plainRead, sizeof plainRead / sizeof plainRead[0]);
        if (wcscmp(plainRead, L"plain text") == 0) {
            break;
        }
        Sleep(100);
    }
    IUIAutomationElement *secret = findElement(automation, NULL, UIA_AutomationIdPropertyId, L"secret-field", UIA_EditControlTypeId, 100);
    if (secret != NULL) {
        secretFound = true;
        BOOL password = FALSE;
        if (SUCCEEDED(IUIAutomationElement_get_CurrentIsPassword(secret, &password))) {
            secretIsPassword = password != FALSE;
        }
        readElementValue(secret, secretRead, sizeof secretRead / sizeof secretRead[0]);
        readElementText(secret, secretText, sizeof secretText / sizeof secretText[0]);
        IUIAutomationElement_Release(secret);
    }
    if (plain != NULL) {
        readElementText(plain, plainText, sizeof plainText / sizeof plainText[0]);
        IUIAutomationElement_Release(plain);
    }
    IUIAutomation_Release(automation);
    CoUninitialize();
    return 0;
}

// Handles the UI thread's messages until `thread` ends (at most `milliseconds`): the reading thread's
// questions are answered on the UI thread. Returns whether the thread ended.
static bool waitPumping(HANDLE thread, DWORD milliseconds) {
    ULONGLONG end = GetTickCount64() + milliseconds;
    for (;;) {
        ULONGLONG now = GetTickCount64();
        if (now >= end) {
            return WaitForSingleObject(thread, 0) == WAIT_OBJECT_0;
        }
        DWORD waited = MsgWaitForMultipleObjects(1, &thread, FALSE, (DWORD)(end - now), QS_ALLINPUT);
        if (waited == WAIT_OBJECT_0) {
            return true;
        }
        if (waited == WAIT_FAILED) {
            return WaitForSingleObject(thread, 0) == WAIT_OBJECT_0;
        }
        MSG message;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE) != FALSE) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

// Accessibility tools read a TextField's text (the control), and a SecureField says it is a password and
// gives none of its text.
static void checkSecureField(void) {
    check(actionUISetStringValue("json-window", 3, 0, "hunter2"), "the SecureField's value is set");
    check(actionUISetStringValue("json-window", 4, 0, "plain text"), "the TextField's value is set");
    char *held = actionUIGetStringValue("json-window", 3, 0);
    check(held != NULL && strcmp(held, "hunter2") == 0, "the SecureField holds the password");
    if (held != NULL) {
        actionUIFreeString(held);
    }
    HANDLE thread = CreateThread(NULL, 0, readTextFields, NULL, 0, NULL);
    if (thread == NULL) {
        check(false, "the reading thread started");
        return;
    }
    // Longer than the thread can take: two searches of up to 10 seconds each, and 5 seconds of reads.
    bool ended = waitPumping(thread, 40000);
    CloseHandle(thread);
    if (!ended) {
        // It may still be writing what it found.
        check(false, "the reading thread finished");
        return;
    }
    printf("c-app: accessibility tools read the TextField's value as \"%ls\" and its text as \"%ls\"; the SecureField's value "
           "as \"%ls\" and its text as \"%ls\" (%s)\n", plainRead, plainText, secretRead, secretText,
           secretIsPassword ? "a password" : "not a password");
    fflush(stdout);
    check(wcscmp(plainRead, L"plain text") == 0, "accessibility tools read the TextField's value");
    check(wcsstr(plainText, L"plain text") != NULL, "accessibility tools read the TextField's text");
    check(secretFound, "accessibility tools find the SecureField");
    check(secretIsPassword, "the SecureField says it is a password");
    check(wcsstr(secretRead, L"hunter2") == NULL, "accessibility tools do not read the SecureField's value");
    check(wcsstr(secretText, L"hunter2") == NULL, "accessibility tools do not read the SecureField's text");
}

// MARK: - Answering a file panel as an accessibility tool does

// What the answering thread does in the system's file dialog: types `fileName` in its name field (NULL:
// nothing), then presses the button whose automation ID is `button` ("1" opens, saves or selects the
// folder; "2" cancels); or, with `closeWindow`, closes that ActionUI window (the dialog's owner) instead.
typedef struct FileAnswer {
    const wchar_t *fileName;
    const wchar_t *button;
    const char *closeWindow;
} FileAnswer;

// The dialog's name field: its automation ID in an open dialog, in a save dialog, else its label.
static IUIAutomationElement *findNameField(IUIAutomation *automation, IUIAutomationElement *dialog) {
    IUIAutomationElement *field = findElement(automation, dialog, UIA_AutomationIdPropertyId, L"1148", UIA_EditControlTypeId, 20);
    if (field == NULL) {
        field = findElement(automation, dialog, UIA_AutomationIdPropertyId, L"1001", UIA_EditControlTypeId, 5);
    }
    if (field == NULL) {
        field = findElement(automation, dialog, UIA_NamePropertyId, L"File name:", UIA_EditControlTypeId, 5);
    }
    return field;
}

static DWORD WINAPI answerFileDialog(void *parameter) {
    const FileAnswer *answer = parameter;
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
    // The system's dialog window class.
    IUIAutomationElement *dialog = findElement(automation, NULL, UIA_ClassNamePropertyId, L"#32770", UIA_WindowControlTypeId, 100);
    if (dialog == NULL) {
        snprintf(answerReport, sizeof answerReport, "the file dialog did not appear");
    } else if (answer->closeWindow != NULL) {
        // The host closes the window under the dialog (from a worker thread, as a binding may).
        Sleep(500);
        actionUIAppCloseWindow(answer->closeWindow);
        answered = true;
        snprintf(answerReport, sizeof answerReport, "closed %s", answer->closeWindow);
        IUIAutomationElement_Release(dialog);
    } else {
        // Its controls settle once it has opened.
        Sleep(500);
        bool typed = true;
        if (answer->fileName != NULL) {
            IUIAutomationElement *field = findNameField(automation, dialog);
            HRESULT set = field != NULL ? setElementText(field, answer->fileName) : E_FAIL;
            typed = SUCCEEDED(set);
            if (!typed) {
                snprintf(answerReport, sizeof answerReport, "typing %ls failed (%s, 0x%08lx)", answer->fileName,
                         field != NULL ? "the name field takes no text" : "no name field", (unsigned long)set);
            }
            if (field != NULL) {
                IUIAutomationElement_Release(field);
            }
        }
        if (typed) {
            IUIAutomationElement *button = findElement(automation, dialog, UIA_AutomationIdPropertyId, answer->button,
                                                       UIA_ButtonControlTypeId, 20);
            HRESULT invoked = button != NULL ? invokeElement(button) : E_FAIL;
            if (SUCCEEDED(invoked)) {
                answered = true;
                snprintf(answerReport, sizeof answerReport, "pressed button %ls", answer->button);
            } else {
                snprintf(answerReport, sizeof answerReport, "pressing button %ls failed (%s, 0x%08lx)", answer->button,
                         button != NULL ? "it cannot be invoked" : "not found", (unsigned long)invoked);
            }
            if (button != NULL) {
                IUIAutomationElement_Release(button);
            }
        }
        IUIAutomationElement_Release(dialog);
    }
    IUIAutomation_Release(automation);
    CoUninitialize();
    return answered ? 0 : answerFailed();
}

// Runs the open (or save) panel `json` while a thread of its own answers it as `answer` says; checks that
// the call returned text holding `expected` (and ending with it when `atEnd`), or NULL when `expected` is NULL.
static void checkFilePanel(bool saving, const char *json, const FileAnswer *answer, const char *expected, bool atEnd,
                           const char *what) {
    answerReport[0] = '\0';
    HANDLE thread = CreateThread(NULL, 0, answerFileDialog, (void *)answer, 0, NULL);
    if (thread == NULL) {
        check(false, "the answering thread started");
        return;
    }
    char *chosen = saving ? actionUIAppRunSavePanel(json) : actionUIAppRunOpenPanel(json);
    WaitForSingleObject(thread, 15000);
    CloseHandle(thread);
    printf("c-app: %s: answered %s (%s)\n", what, chosen != NULL ? chosen : "(null)", answerReport);
    bool passed = false;
    if (expected == NULL) {
        passed = chosen == NULL;
    } else if (chosen != NULL) {
        const char *found = strstr(chosen, expected);
        passed = found != NULL && (!atEnd || strcmp(found, expected) == 0);
    }
    check(passed, what);
    if (chosen != NULL) {
        actionUIFreeString(chosen);
    }
}

// `path` with "/" between its parts, as JSON takes it without escapes (Windows reads either).
static void forwardSlashes(char *path) {
    for (char *character = path; *character != '\0'; character++) {
        if (*character == '\\') {
            *character = '/';
        }
    }
}

// The panels over the window from JSON: open a file by typing its name, save with the name and folder the
// JSON gives (the extension added), cancel, choose a folder; then one whose window the host closes.
static void checkFilePanels(void) {
    char folder[MAX_PATH] = "";
    snprintf(folder, sizeof folder, "%s", windowFile);
    forwardSlashes(folder);
    char *slash = strrchr(folder, '/');
    if (slash == NULL) {
        check(false, "the window file's folder is known");
        return;
    }
    *slash = '\0';
    char json[1024];
    static const FileAnswer openAnswer = {L"Window.json", L"1", NULL};
    snprintf(json, sizeof json, "{\"title\": \"Open a window\", \"directoryURL\": \"%s\", \"allowedContentTypes\": [\"json\"]}", folder);
    checkFilePanel(false, json, &openAnswer, "Window.json\"]", true, "an open panel answers the file typed in it");

    char temporary[MAX_PATH] = "";
    DWORD length = GetTempPathA(MAX_PATH, temporary);
    if (length == 0 || length >= MAX_PATH) {
        check(false, "the temporary folder is known");
        return;
    }
    // A file left from an earlier run would bring up the dialog's question about replacing it.
    char saved[MAX_PATH + 32];
    snprintf(saved, sizeof saved, "%sactionui-save-check.json", temporary);
    DeleteFileA(saved);
    forwardSlashes(temporary);
    size_t end = strlen(temporary);
    if (end > 3 && temporary[end - 1] == '/') {
        temporary[end - 1] = '\0';
    }
    static const FileAnswer saveAnswer = {NULL, L"1", NULL};
    snprintf(json, sizeof json, "{\"title\": \"Save a check\", \"directoryURL\": \"%s\", "
             "\"nameFieldStringValue\": \"actionui-save-check\", \"allowedContentTypes\": [\"public.json\"]}", temporary);
    checkFilePanel(true, json, &saveAnswer, "\\actionui-save-check.json", true, "a save panel answers its folder and name, with the extension");

    static const FileAnswer cancelAnswer = {NULL, L"2", NULL};
    checkFilePanel(false, "{\"title\": \"Cancel me\"}", &cancelAnswer, NULL, false, "a canceled open panel answers NULL");

    static const FileAnswer folderAnswer = {NULL, L"1", NULL};
    snprintf(json, sizeof json, "{\"directoryURL\": \"file:///%s\", \"canChooseFiles\": false, \"canChooseDirectories\": true}", temporary);
    checkFilePanel(false, json, &folderAnswer, "[\"", false, "an open panel for folders answers a folder");

    // Last: the window goes (its windowWillClose fires now, not with the others).
    static const FileAnswer closeAnswer = {NULL, NULL, "json-window"};
    checkFilePanel(false, "{\"title\": \"Closed under me\"}", &closeAnswer, NULL, false,
                   "an open panel whose window closes answers NULL");
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
    check(value != NULL && strcmp(value, "Loaded over HTTPS") == 0, "the window from a server shows its ActionUI JSON");
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
        "{\"type\": \"Text\", \"id\": 2, \"properties\": {\"text\": \"A window from JSON\"}},"
        "{\"type\": \"SecureField\", \"id\": 3, \"properties\": {\"title\": \"Password\", \"accessibilityIdentifier\": \"secret-field\"}},"
        "{\"type\": \"TextField\", \"id\": 4, \"properties\": {\"title\": \"Name\", \"accessibilityIdentifier\": \"plain-field\"}}]}",
        "json-window", "From JSON");
    // The adapter reaches the window the application functions made: one ActionUI in the DLL.
    check(actionUISetStringValue("json-window", 2, 0, "set from C"), "a value is set in the window");
    char *value = actionUIGetStringValue("json-window", 2, 0);
    check(value != NULL && strcmp(value, "set from C") == 0, "the value reads back");
    if (value != NULL) {
        actionUIFreeString(value);
    }
    checkSecureField();
    // Over the window just presented (shown once it has loaded); Cancel is the close button.
    checkAlert("{\"title\": \"Save changes?\", \"buttons\": [\"Save\", \"Don't Save\", \"Cancel\"]}",
               L"Cancel", "Cancel", "Save", "an alert over a window answers Cancel");
    // A fourth button goes in the content, with the third.
    checkAlert("{\"title\": \"Four buttons\", \"buttons\": [\"One\", \"Two\", \"Three\", \"Four\"]}",
               L"Four", "Four", "One", "an alert's fourth button answers");
    checkFilePanels();
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
    early = actionUIAppRunOpenPanel("{}");
    check(early == NULL, "an open panel before the run answers NULL");
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

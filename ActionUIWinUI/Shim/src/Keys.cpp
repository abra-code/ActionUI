// Keys.cpp - keyboard focus and the keys of any element: whether it takes focus, giving and giving up focus, focus
// changes, and its key presses and releases with the text they type (a HostSurface client's keyboard input).

#include "ShimInternal.h"

#include <memory>
#include <string>
#include <string_view>

#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Core.h>  // CorePhysicalKeyStatus
#include <winrt/Microsoft.UI.Xaml.Input.h>

namespace actionui_winui {

namespace {

// What a key registration holds (actionUIWinUIElementOnKeyEvents), as EventHandler.
struct KeyEventHandler {
    KeyEventHandler(ActionUIWinUIKeyEventCallback handler, void *context, ActionUIWinUICallback destroyContext,
                    dispatching::DispatcherQueue queue)
        : handler(handler), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    KeyEventHandler(KeyEventHandler const &) = delete;
    KeyEventHandler &operator=(KeyEventHandler const &) = delete;
    ~KeyEventHandler() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }

    ActionUIWinUIKeyEventCallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// The keys held now, as ActionUIWinUIModifier bits (the thread's keyboard state, as of the key being handled).
uint32_t heldModifiers() {
    uint32_t bits = 0;
    if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
        bits |= ActionUIWinUIModifierShift;
    }
    if ((GetKeyState(VK_CONTROL) & 0x8000) != 0) {
        bits |= ActionUIWinUIModifierControl;
    }
    if ((GetKeyState(VK_MENU) & 0x8000) != 0) {
        bits |= ActionUIWinUIModifierAlt;
    }
    if ((GetKeyState(VK_LWIN) & 0x8000) != 0 || (GetKeyState(VK_RWIN) & 0x8000) != 0) {
        bits |= ActionUIWinUIModifierWindows;
    }
    if ((GetKeyState(VK_CAPITAL) & 1) != 0) {
        bits |= ActionUIWinUIModifierCapsLock;
    }
    return bits;
}

// The text a key down types in the keyboard's layout, empty for none. ToUnicodeEx with flag 4 leaves the
// keyboard's state alone, so a dead key still combines with the next key in the controls that read WM_CHAR.
std::string typedText(int32_t virtualKey, uint32_t scanCode, uint32_t modifiers) {
    bool control = (modifiers & ActionUIWinUIModifierControl) != 0;
    bool alt = (modifiers & ActionUIWinUIModifierAlt) != 0;
    // A shortcut, not text: Control or Alt alone, or Windows. Control with Alt is AltGr, which types.
    if ((modifiers & ActionUIWinUIModifierWindows) != 0 || control != alt) {
        return std::string();
    }
    BYTE state[256];
    if (!GetKeyboardState(state)) {
        return std::string();
    }
    wchar_t buffer[8];
    int count = ToUnicodeEx(static_cast<UINT>(virtualKey), scanCode, state, buffer, 8, 0x4, GetKeyboardLayout(0));
    // 0: no text; below 0: a dead key, which types nothing by itself.
    if (count <= 0) {
        return std::string();
    }
    for (int index = 0; index < count; index++) {
        if (buffer[index] < 0x20 || buffer[index] == 0x7F) {
            return std::string();
        }
    }
    return winrt::to_string(std::wstring_view(buffer, static_cast<size_t>(count)));
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

bool actionUIWinUIElementSetFocusable(ActionUIWinUIObject *element, bool focusable) {
    return guarded("element set focusable", [&]() {
        objectAs<mux::UIElement>(element, L"UIElement").IsTabStop(focusable);
        return true;
    });
}

bool actionUIWinUIElementSetSystemFocusVisuals(ActionUIWinUIObject *element, bool visible) {
    return guarded("element set system focus visuals", [&]() {
        objectAs<mux::UIElement>(element, L"UIElement").UseSystemFocusVisuals(visible);
        return true;
    });
}

bool actionUIWinUIElementFocus(ActionUIWinUIObject *element) {
    return guarded("element focus", [&]() {
        if (!objectAs<mux::UIElement>(element, L"UIElement").Focus(mux::FocusState::Pointer)) {
            return fail("element focus", "the element did not take the focus");
        }
        return true;
    });
}

bool actionUIWinUIElementHasFocus(ActionUIWinUIObject *element) {
    bool focused = false;
    bool read = guarded("element has focus", [&]() {
        focused = objectAs<mux::UIElement>(element, L"UIElement").FocusState() != mux::FocusState::Unfocused;
        return true;
    });
    return read && focused;
}

bool actionUIWinUIElementGiveUpFocus(ActionUIWinUIObject *element) {
    return guarded("element give up focus", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (typed.FocusState() == mux::FocusState::Unfocused) {
            return true;
        }
        mux::XamlRoot root = typed.XamlRoot();
        if (root == nullptr || root.Content() == nullptr) {
            return fail("element give up focus", "the element is in no window");
        }
        mux::Input::FindNextElementOptions options;
        options.SearchRoot(root.Content());
        if (!mux::Input::FocusManager::TryMoveFocus(mux::Input::FocusNavigationDirection::Next, options)) {
            return fail("element give up focus", "no other element takes the focus");
        }
        return true;
    });
}

bool actionUIWinUIElementOnFocusChanged(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                        ActionUIWinUICallback destroyContext) {
    return registerHandler("element on focus changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
                               typed.GotFocus([holder](auto &&, auto &&) { holder->fire(); });
                               typed.LostFocus([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUIElementOnKeyEvents(ActionUIWinUIObject *element, ActionUIWinUIKeyEventCallback handler, void *context,
                                     ActionUIWinUICallback destroyContext) {
    std::shared_ptr<KeyEventHandler> holder;
    bool registered = guarded("element on key events", [&]() {
        if (handler == nullptr) {
            return fail("element on key events", "the handler is NULL");
        }
        holder = std::make_shared<KeyEventHandler>(handler, context, destroyContext, currentQueue());
        mux::UIElement target = objectAs<mux::UIElement>(element, L"UIElement");
        auto report = [holder](ActionUIWinUIKeyEventType type, mux::Input::KeyRoutedEventArgs const &arguments) {
            ActionUIWinUIKeyEvent event{};
            event.type = type;
            event.virtualKey = static_cast<int32_t>(arguments.Key());
            winrt::Windows::UI::Core::CorePhysicalKeyStatus status = arguments.KeyStatus();
            event.scanCode = status.ScanCode + (status.IsExtendedKey ? 0xE000u : 0u);
            event.repeat = type == ActionUIWinUIKeyDown && status.WasKeyDown;
            event.modifiers = heldModifiers();
            event.timeMilliseconds = static_cast<uint32_t>(GetMessageTime());
            std::string text;
            if (type == ActionUIWinUIKeyDown) {
                text = typedText(event.virtualKey, status.ScanCode, event.modifiers);
            }
            event.text = text.empty() ? nullptr : text.c_str();
            std::shared_ptr<KeyEventHandler> keep = holder;
            if (keep->handler(keep->context, &event)) {
                arguments.Handled(true);
            }
        };
        target.KeyDown([report](auto &&, mux::Input::KeyRoutedEventArgs const &arguments) {
            report(ActionUIWinUIKeyDown, arguments);
        });
        target.KeyUp([report](auto &&, mux::Input::KeyRoutedEventArgs const &arguments) {
            report(ActionUIWinUIKeyUp, arguments);
        });
        return true;
    });
    if (!registered && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

} // extern "C"

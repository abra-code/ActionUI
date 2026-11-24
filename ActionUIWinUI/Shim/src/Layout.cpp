// Layout.cpp - a Panel whose measure and arrange passes are the caller's (C callbacks), and the
// element calls those passes use: measure, arrange, invalidate, the last placed frame, a clip. Also a
// panel's cursor and pointer drags (a split view's dividers).

#include "ShimInternal.h"

#include <cfloat>
#include <cmath>
#include <limits>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.System.h>
#include <winrt/Microsoft.UI.Input.h>  // InputSystemCursor
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>  // RectangleGeometry, SolidColorBrush
#include <winrt/Windows.UI.h>  // Color

namespace actionui_winui {

namespace {

// A size WinUI accepts from MeasureOverride: finite and not negative (it throws otherwise). A
// double past the float range is capped: converted as is, it would be undefined (infinity on MSVC).
float layoutLength(double value) {
    if (!(std::isfinite(value) && value > 0)) {
        return 0.0f;
    }
    return value <= FLT_MAX ? static_cast<float>(value) : FLT_MAX;
}

// A size offered to Measure: infinity, or a double past the float range, is "as much as wanted";
// NaN or a negative size, which WinUI would throw on, is 0.
float offeredLength(double value) {
    if (std::isnan(value) || value < 0) {
        return 0.0f;
    }
    return value <= FLT_MAX ? static_cast<float>(value) : std::numeric_limits<float>::infinity();
}

struct CallbackPanel;

// The live panels by the pointer the callbacks see (m_self), for what only the panel's own class may
// do (its cursor: UIElement.ProtectedCursor). A panel may go on another thread: the table is locked.
std::mutex &panelsLock() {
    static std::mutex lock;
    return lock;
}

std::unordered_map<ActionUIWinUIObject *, winrt::weak_ref<CallbackPanel>> &livePanels();

struct CallbackPanel : muxc::PanelT<CallbackPanel> {
    CallbackPanel(ActionUIWinUIMeasureCallback measure, ActionUIWinUIArrangeCallback arrange, void *context,
                  ActionUIWinUICallback destroyContext)
        : m_measure(measure), m_arrange(arrange), m_context(context), m_destroyContext(destroyContext),
          m_queue(dispatching::DispatcherQueue::GetForCurrentThread()) {}

    // On the thread that let go of the last reference. The context belongs to the UI thread (its
    // Swift side is main-actor isolated): from any other thread, destroyContext is sent there
    // (callOnUIThread).
    ~CallbackPanel() {
        {
            std::lock_guard<std::mutex> guard(panelsLock());
            livePanels().erase(m_self);
        }
        callOnUIThread(m_queue, m_destroyContext, m_context);
    }

    // The cursor over the panel; nullptr: the default (the cursor of the element the panel is in).
    void SetCursor(winrt::Microsoft::UI::Input::InputCursor const &cursor) {
        ProtectedCursor(cursor);
    }

    wf::Size MeasureOverride(wf::Size available) {
        ActionUIWinUISize size{0, 0};
        if (m_measure != nullptr && m_self != nullptr) {
            size = m_measure(m_context, m_self, ActionUIWinUISize{available.Width, available.Height});
        }
        return wf::Size{layoutLength(size.width), layoutLength(size.height)};
    }

    wf::Size ArrangeOverride(wf::Size finalSize) {
        if (m_arrange != nullptr && m_self != nullptr) {
            m_arrange(m_context, m_self, ActionUIWinUISize{finalSize.Width, finalSize.Height});
        }
        return finalSize;
    }

    // The panel as the callbacks see it: one of its own interface pointers, not a reference (the
    // panel cannot hold a reference to itself). Valid while the panel lives.
    ActionUIWinUIObject *m_self = nullptr;

private:
    ActionUIWinUIMeasureCallback m_measure;
    ActionUIWinUIArrangeCallback m_arrange;
    void *m_context;
    ActionUIWinUICallback m_destroyContext;
    dispatching::DispatcherQueue m_queue;
};

// Defined once CallbackPanel is complete. Never freed: a panel let go of during the process's exit,
// after static destructors ran, still finds it.
std::unordered_map<ActionUIWinUIObject *, winrt::weak_ref<CallbackPanel>> &livePanels() {
    static auto *panels = new std::unordered_map<ActionUIWinUIObject *, winrt::weak_ref<CallbackPanel>>();
    return *panels;
}

muxc::Panel panelFrom(ActionUIWinUIObject *panel) {
    return objectAs<muxc::Panel>(panel, L"Panel");
}

// What a pointer registration holds: the caller's handler and context, freed (destroyContext, on the
// UI thread) when the element lets go of its handlers.
struct PointerHandler {
    PointerHandler(ActionUIWinUIPointerCallback handler, void *context, ActionUIWinUICallback destroyContext,
                   dispatching::DispatcherQueue queue)
        : handler(handler), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    PointerHandler(PointerHandler const &) = delete;
    PointerHandler &operator=(PointerHandler const &) = delete;
    ~PointerHandler() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }

    ActionUIWinUIPointerCallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// What a pointer input registration holds (actionUIWinUIElementOnPointerInput), as PointerHandler.
struct PointerInputHandler {
    PointerInputHandler(ActionUIWinUIPointerInputCallback handler, void *context, ActionUIWinUICallback destroyContext,
                        dispatching::DispatcherQueue queue)
        : handler(handler), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    PointerInputHandler(PointerInputHandler const &) = delete;
    PointerInputHandler &operator=(PointerInputHandler const &) = delete;
    ~PointerInputHandler() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }

    ActionUIWinUIPointerInputCallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// What a pointer event registration holds (actionUIWinUIElementOnPointerEvents), as PointerHandler, and the
// pointers the element holds captured: the capture's end that Windows reports after the element released one
// is no cancel.
struct PointerEventHandler {
    PointerEventHandler(ActionUIWinUIPointerEventCallback handler, void *context, ActionUIWinUICallback destroyContext,
                        dispatching::DispatcherQueue queue)
        : handler(handler), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    PointerEventHandler(PointerEventHandler const &) = delete;
    PointerEventHandler &operator=(PointerEventHandler const &) = delete;
    ~PointerEventHandler() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }

    ActionUIWinUIPointerEventCallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
    std::unordered_set<uint32_t> captured;
};

// The buttons a pointer holds, as ActionUIWinUIPointerButton bits.
uint32_t heldButtons(winrt::Microsoft::UI::Input::PointerPointProperties const &properties) {
    uint32_t buttons = 0;
    if (properties.IsLeftButtonPressed()) {
        buttons |= ActionUIWinUIPointerButtonLeft;
    }
    if (properties.IsRightButtonPressed()) {
        buttons |= ActionUIWinUIPointerButtonRight;
    }
    if (properties.IsMiddleButtonPressed()) {
        buttons |= ActionUIWinUIPointerButtonMiddle;
    }
    if (properties.IsXButton1Pressed()) {
        buttons |= ActionUIWinUIPointerButtonBack;
    }
    if (properties.IsXButton2Pressed()) {
        buttons |= ActionUIWinUIPointerButtonForward;
    }
    return buttons;
}

// The keys held, as ActionUIWinUIModifier bits; Caps Lock from the keyboard's state.
uint32_t modifierBits(winrt::Windows::System::VirtualKeyModifiers keys) {
    using winrt::Windows::System::VirtualKeyModifiers;
    uint32_t held = static_cast<uint32_t>(keys);
    uint32_t bits = 0;
    if ((held & static_cast<uint32_t>(VirtualKeyModifiers::Shift)) != 0) {
        bits |= ActionUIWinUIModifierShift;
    }
    if ((held & static_cast<uint32_t>(VirtualKeyModifiers::Control)) != 0) {
        bits |= ActionUIWinUIModifierControl;
    }
    if ((held & static_cast<uint32_t>(VirtualKeyModifiers::Menu)) != 0) {
        bits |= ActionUIWinUIModifierAlt;
    }
    if ((held & static_cast<uint32_t>(VirtualKeyModifiers::Windows)) != 0) {
        bits |= ActionUIWinUIModifierWindows;
    }
    if ((GetKeyState(VK_CAPITAL) & 1) != 0) {
        bits |= ActionUIWinUIModifierCapsLock;
    }
    return bits;
}

// A pointer event as actionUIWinUIElementOnPointerEvents reports it, at `element`. For a press, a move or a
// release, the type and button come from what changed (PointerUpdateKind): WinUI reports a second button's
// press and release as moves, and the first one's in PointerPressed and PointerReleased.
ActionUIWinUIPointerEvent pointerEventOf(ActionUIWinUIPointerEventType type, mux::UIElement const &element,
                                         mux::Input::PointerRoutedEventArgs const &arguments) {
    namespace input = winrt::Microsoft::UI::Input;
    ActionUIWinUIPointerEvent event{};
    event.type = type;
    event.button = -1;
    input::PointerPoint point = arguments.GetCurrentPoint(element);
    input::PointerPointProperties properties = point.Properties();
    switch (arguments.Pointer().PointerDeviceType()) {
    case input::PointerDeviceType::Touch:
        event.device = ActionUIWinUIPointerDeviceTouch;
        break;
    case input::PointerDeviceType::Pen:
        event.device = ActionUIWinUIPointerDevicePen;
        break;
    default:
        event.device = ActionUIWinUIPointerDeviceMouse;
        break;
    }
    event.pointerID = arguments.Pointer().PointerId();
    event.buttons = heldButtons(properties);
    event.modifiers = modifierBits(arguments.KeyModifiers());
    event.x = point.Position().X;
    event.y = point.Position().Y;
    if (event.device == ActionUIWinUIPointerDevicePen) {
        event.pressure = properties.Pressure();
        event.tiltX = properties.XTilt();
        event.tiltY = properties.YTilt();
    } else {
        event.pressure = event.buttons != 0 ? 1 : 0;
    }
    event.timestampMicroseconds = point.Timestamp();
    if (type == ActionUIWinUIPointerEventWheel) {
        // A notch is 120 (WHEEL_DELTA); a turn away from the user is positive, toward the top.
        double notches = properties.MouseWheelDelta() / 120.0;
        if (properties.IsHorizontalMouseWheel()) {
            event.wheelX = notches;
        } else {
            event.wheelY = -notches;
        }
        return event;
    }
    if (type != ActionUIWinUIPointerEventPressed && type != ActionUIWinUIPointerEventMoved &&
        type != ActionUIWinUIPointerEventReleased) {
        return event;
    }
    switch (properties.PointerUpdateKind()) {
    case input::PointerUpdateKind::LeftButtonPressed:
        event.type = ActionUIWinUIPointerEventPressed;
        event.button = 0;
        break;
    case input::PointerUpdateKind::RightButtonPressed:
        event.type = ActionUIWinUIPointerEventPressed;
        event.button = 1;
        break;
    case input::PointerUpdateKind::MiddleButtonPressed:
        event.type = ActionUIWinUIPointerEventPressed;
        event.button = 2;
        break;
    case input::PointerUpdateKind::XButton1Pressed:
        event.type = ActionUIWinUIPointerEventPressed;
        event.button = 3;
        break;
    case input::PointerUpdateKind::XButton2Pressed:
        event.type = ActionUIWinUIPointerEventPressed;
        event.button = 4;
        break;
    case input::PointerUpdateKind::LeftButtonReleased:
        event.type = ActionUIWinUIPointerEventReleased;
        event.button = 0;
        break;
    case input::PointerUpdateKind::RightButtonReleased:
        event.type = ActionUIWinUIPointerEventReleased;
        event.button = 1;
        break;
    case input::PointerUpdateKind::MiddleButtonReleased:
        event.type = ActionUIWinUIPointerEventReleased;
        event.button = 2;
        break;
    case input::PointerUpdateKind::XButton1Released:
        event.type = ActionUIWinUIPointerEventReleased;
        event.button = 3;
        break;
    case input::PointerUpdateKind::XButton2Released:
        event.type = ActionUIWinUIPointerEventReleased;
        event.button = 4;
        break;
    default:
        // No button changed: a move, whatever the event WinUI raised.
        event.type = ActionUIWinUIPointerEventMoved;
        break;
    }
    return event;
}

mux::UIElement elementFrom(ActionUIWinUIObject *element) {
    return objectAs<mux::UIElement>(element, L"UIElement");
}

// The class behind `panel` when it is one of actionUIWinUIPanelCreate's, else nullptr.
winrt::com_ptr<CallbackPanel> callbackPanelFrom(ActionUIWinUIObject *panel) {
    ActionUIWinUIObject *key = static_cast<ActionUIWinUIObject *>(winrt::get_abi(panelFrom(panel)));
    std::lock_guard<std::mutex> guard(panelsLock());
    auto found = livePanels().find(key);
    if (found == livePanels().end()) {
        return nullptr;
    }
    return found->second.get();
}

// The path of the shim's own DLL; empty when unknown.
std::wstring shimModulePath() {
    HMODULE shim = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&shimModulePath), &shim)) {
        return std::wstring();
    }
    std::wstring path(MAX_PATH, L'\0');
    for (;;) {
        DWORD length = GetModuleFileNameW(shim, path.data(), static_cast<DWORD>(path.size()));
        if (length == 0) {
            return std::wstring();
        }
        if (length < path.size()) {
            path.resize(length);
            return path;
        }
        path.resize(path.size() * 2);
    }
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIPanelCreate(ActionUIWinUIMeasureCallback measure, ActionUIWinUIArrangeCallback arrange,
                                              void *context, ActionUIWinUICallback destroyContext) {
    bool constructed = false;
    ActionUIWinUIObject *result = guardedObject("panel create", [&]() {
        // make_self keeps the implementation pointer: get_self cannot get back to it from the
        // composed Panel base.
        winrt::com_ptr<CallbackPanel> implementation =
            winrt::make_self<CallbackPanel>(measure, arrange, context, destroyContext);
        constructed = true;
        muxc::Panel panel = implementation.as<muxc::Panel>();
        implementation->m_self = static_cast<ActionUIWinUIObject *>(winrt::get_abi(panel));
        {
            std::lock_guard<std::mutex> guard(panelsLock());
            livePanels()[implementation->m_self] = winrt::make_weak(implementation);
        }
        return toObject(panel);
    });
    // Once constructed, the panel's destructor calls destroyContext, also on a failure after it.
    if (result == nullptr && !constructed && destroyContext != nullptr) {
        destroyContext(context);
    }
    return result;
}

int32_t actionUIWinUIPanelChildCount(ActionUIWinUIObject *panel) {
    int32_t count = -1;
    guarded("panel child count", [&]() {
        count = static_cast<int32_t>(panelFrom(panel).Children().Size());
        return true;
    });
    return count;
}

bool actionUIWinUIPanelInsertChild(ActionUIWinUIObject *panel, int32_t index, ActionUIWinUIObject *child) {
    return guarded("panel insert child", [&]() {
        auto children = panelFrom(panel).Children();
        if (index < 0 || static_cast<uint32_t>(index) > children.Size()) {
            return fail("panel insert child", "the index is out of range");
        }
        children.InsertAt(static_cast<uint32_t>(index), elementFrom(child));
        return true;
    });
}

bool actionUIWinUIPanelRemoveChild(ActionUIWinUIObject *panel, int32_t index) {
    return guarded("panel remove child", [&]() {
        auto children = panelFrom(panel).Children();
        if (index < 0 || static_cast<uint32_t>(index) >= children.Size()) {
            return fail("panel remove child", "the index is out of range");
        }
        children.RemoveAt(static_cast<uint32_t>(index));
        return true;
    });
}

ActionUIWinUISize actionUIWinUIElementMeasure(ActionUIWinUIObject *element, ActionUIWinUISize available) {
    ActionUIWinUISize desired{0, 0};
    guarded("element measure", [&]() {
        mux::UIElement typed = elementFrom(element);
        typed.Measure(wf::Size{offeredLength(available.width), offeredLength(available.height)});
        wf::Size size = typed.DesiredSize();
        desired = ActionUIWinUISize{size.Width, size.Height};
        return true;
    });
    return desired;
}

bool actionUIWinUIElementArrange(ActionUIWinUIObject *element, ActionUIWinUIRect frame) {
    return guarded("element arrange", [&]() {
        // Also false for NaN and infinity.
        if (!(std::fabs(frame.x) <= FLT_MAX && std::fabs(frame.y) <= FLT_MAX)) {
            return fail("element arrange", "the position is not finite (or past the float range)");
        }
        elementFrom(element).Arrange(wf::Rect{static_cast<float>(frame.x), static_cast<float>(frame.y),
                                              layoutLength(frame.width), layoutLength(frame.height)});
        return true;
    });
}

bool actionUIWinUIElementInvalidateMeasure(ActionUIWinUIObject *element) {
    return guarded("element invalidate measure", [&]() {
        elementFrom(element).InvalidateMeasure();
        return true;
    });
}

ActionUIWinUIRect actionUIWinUIElementLayoutFrame(ActionUIWinUIObject *element) {
    ActionUIWinUIRect frame{0, 0, 0, 0};
    guarded("element layout frame", [&]() {
        mux::UIElement typed = elementFrom(element);
        winrt::Windows::Foundation::Numerics::float3 offset = typed.ActualOffset();
        winrt::Windows::Foundation::Numerics::float2 size = typed.ActualSize();
        frame = ActionUIWinUIRect{offset.x, offset.y, size.x, size.y};
        return true;
    });
    return frame;
}

bool actionUIWinUIElementSetClipSize(ActionUIWinUIObject *element, double width, double height) {
    return guarded("element set clip size", [&]() {
        mux::UIElement typed = elementFrom(element);
        if (!(std::isfinite(width) && width >= 0 && std::isfinite(height) && height >= 0)) {
            typed.Clip(nullptr);
            return true;
        }
        mux::Media::RectangleGeometry clip;
        clip.Rect(wf::Rect{0, 0, layoutLength(width), layoutLength(height)});
        typed.Clip(clip);
        return true;
    });
}

bool actionUIWinUIPanelSetResizeCursor(ActionUIWinUIObject *panel, bool resizes, bool horizontal) {
    return guarded("panel set resize cursor", [&]() {
        winrt::com_ptr<CallbackPanel> implementation = callbackPanelFrom(panel);
        if (!implementation) {
            return fail("panel set resize cursor", "the panel is not one of actionUIWinUIPanelCreate's");
        }
        if (!resizes) {
            implementation->SetCursor(nullptr);
            return true;
        }
        implementation->SetCursor(winrt::Microsoft::UI::Input::InputSystemCursor::Create(
            horizontal ? winrt::Microsoft::UI::Input::InputSystemCursorShape::SizeWestEast
                       : winrt::Microsoft::UI::Input::InputSystemCursorShape::SizeNorthSouth));
        return true;
    });
}

bool actionUIWinUIPanelSetCursor(ActionUIWinUIObject *panel, ActionUIWinUICursor cursor) {
    return guarded("panel set cursor", [&]() {
        using winrt::Microsoft::UI::Input::InputSystemCursorShape;
        winrt::com_ptr<CallbackPanel> implementation = callbackPanelFrom(panel);
        if (!implementation) {
            return fail("panel set cursor", "the panel is not one of actionUIWinUIPanelCreate's");
        }
        InputSystemCursorShape shape;
        switch (cursor) {
        case ActionUIWinUICursorDefault:
            implementation->SetCursor(nullptr);
            return true;
        case ActionUIWinUICursorHidden: {
            // The blank cursor in the shim's resources (resources/Shim.rc), by the DLL's full path.
            std::wstring module = shimModulePath();
            if (module.empty()) {
                return fail("panel set cursor", "the shim's DLL path is unknown");
            }
            implementation->SetCursor(winrt::Microsoft::UI::Input::InputDesktopNamedResourceCursor::CreateFromModule(
                module, L"ACTIONUI_HIDDEN_CURSOR"));
            return true;
        }
        case ActionUIWinUICursorIBeam: shape = InputSystemCursorShape::IBeam; break;
        case ActionUIWinUICursorCross: shape = InputSystemCursorShape::Cross; break;
        case ActionUIWinUICursorHand: shape = InputSystemCursorShape::Hand; break;
        case ActionUIWinUICursorSizeAll: shape = InputSystemCursorShape::SizeAll; break;
        case ActionUIWinUICursorSizeWestEast: shape = InputSystemCursorShape::SizeWestEast; break;
        case ActionUIWinUICursorSizeNorthSouth: shape = InputSystemCursorShape::SizeNorthSouth; break;
        case ActionUIWinUICursorNo: shape = InputSystemCursorShape::UniversalNo; break;
        default:
            return fail("panel set cursor", "not an ActionUIWinUICursor value");
        }
        implementation->SetCursor(winrt::Microsoft::UI::Input::InputSystemCursor::Create(shape));
        return true;
    });
}

bool actionUIWinUIElementOnPointerDrag(ActionUIWinUIObject *element, ActionUIWinUIObject *relativeTo,
                                       ActionUIWinUIPointerCallback handler, void *context, ActionUIWinUICallback destroyContext) {
    std::shared_ptr<PointerHandler> holder;
    bool registered = guarded("element on pointer drag", [&]() {
        if (handler == nullptr) {
            return fail("element on pointer drag", "the handler is NULL");
        }
        holder = std::make_shared<PointerHandler>(handler, context, destroyContext, currentQueue());
        mux::UIElement target = elementFrom(element);
        // Weakly: the element is usually inside `relativeTo`, which would then keep itself alive.
        winrt::weak_ref<mux::UIElement> relative = elementFrom(relativeTo);
        auto position = [relative](mux::Input::PointerRoutedEventArgs const &arguments, wf::Point &point) {
            mux::UIElement within = relative.get();
            if (!within) {
                return false;
            }
            point = arguments.GetCurrentPoint(within).Position();
            return true;
        };
        target.PointerPressed([holder, position](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            wf::Point point{};
            // The primary button, a pen or a finger.
            if (!arguments.GetCurrentPoint(nullptr).Properties().IsLeftButtonPressed() || !position(arguments, point)) {
                return;
            }
            std::shared_ptr<PointerHandler> keep = holder;
            if (keep->handler(keep->context, ActionUIWinUIPointerPressed, point.X, point.Y)) {
                arguments.Handled(true);
                // Without the capture the moves would not follow the drag: it ends at once.
                if (!sender.as<mux::UIElement>().CapturePointer(arguments.Pointer())) {
                    keep->handler(keep->context, ActionUIWinUIPointerCanceled, 0, 0);
                }
            }
        });
        target.PointerMoved([holder, position](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            wf::Point point{};
            if (!position(arguments, point)) {
                return;
            }
            std::shared_ptr<PointerHandler> keep = holder;
            if (keep->handler(keep->context, ActionUIWinUIPointerMoved, point.X, point.Y)) {
                arguments.Handled(true);
            }
        });
        target.PointerReleased([holder, position](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            wf::Point point{};
            position(arguments, point);
            std::shared_ptr<PointerHandler> keep = holder;
            if (keep->handler(keep->context, ActionUIWinUIPointerReleased, point.X, point.Y)) {
                arguments.Handled(true);
            }
            sender.as<mux::UIElement>().ReleasePointerCapture(arguments.Pointer());
        });
        auto canceled = [holder](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &) {
            std::shared_ptr<PointerHandler> keep = holder;
            keep->handler(keep->context, ActionUIWinUIPointerCanceled, 0, 0);
        };
        target.PointerCaptureLost(canceled);
        target.PointerCanceled(canceled);
        return true;
    });
    if (!registered && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

bool actionUIWinUIElementOnPointerInput(ActionUIWinUIObject *element, ActionUIWinUIObject *relativeTo,
                                        ActionUIWinUIPointerInputCallback handler, void *context,
                                        ActionUIWinUICallback destroyContext) {
    std::shared_ptr<PointerInputHandler> holder;
    bool registered = guarded("element on pointer input", [&]() {
        if (handler == nullptr) {
            return fail("element on pointer input", "the handler is NULL");
        }
        holder = std::make_shared<PointerInputHandler>(handler, context, destroyContext, currentQueue());
        mux::UIElement target = elementFrom(element);
        // A panel hit-tests only what is drawn in it unless it has a background: its whole area takes the input.
        if (muxc::Panel panel = target.try_as<muxc::Panel>(); panel != nullptr && panel.Background() == nullptr) {
            panel.Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        }
        // Weakly: the element is usually `relativeTo` or inside it, which would then keep itself alive.
        winrt::weak_ref<mux::UIElement> relative = elementFrom(relativeTo);
        // The event as the handler takes it: where the pointer is in `relativeTo`, what it is, and how far a
        // wheel turned.
        auto inputOf = [relative](ActionUIWinUIPointerInputKind kind, mux::Input::PointerRoutedEventArgs const &arguments) {
            ActionUIWinUIPointerInput input{};
            input.kind = kind;
            input.touch = arguments.Pointer().PointerDeviceType() == winrt::Microsoft::UI::Input::PointerDeviceType::Touch;
            mux::UIElement within = relative.get();
            if (within) {
                winrt::Microsoft::UI::Input::PointerPoint point = arguments.GetCurrentPoint(within);
                input.x = point.Position().X;
                input.y = point.Position().Y;
                if (kind == ActionUIWinUIPointerInputWheel) {
                    // A notch is 120 (WHEEL_DELTA); a turn away from the user is positive, toward the top.
                    double notches = point.Properties().MouseWheelDelta() / 120.0;
                    if (point.Properties().IsHorizontalMouseWheel()) {
                        input.wheelX = notches;
                    } else {
                        input.wheelY = -notches;
                    }
                }
            }
            return input;
        };
        auto report = [holder, inputOf](ActionUIWinUIPointerInputKind kind, mux::Input::PointerRoutedEventArgs const &arguments) {
            ActionUIWinUIPointerInput input = inputOf(kind, arguments);
            std::shared_ptr<PointerInputHandler> keep = holder;
            return keep->handler(keep->context, &input);
        };
        target.PointerPressed([holder, report](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            // The primary button, a pen or a finger.
            if (!arguments.GetCurrentPoint(nullptr).Properties().IsLeftButtonPressed()) {
                return;
            }
            if (report(ActionUIWinUIPointerInputPressed, arguments)) {
                arguments.Handled(true);
                // Without the capture the moves would not follow the press out of the element.
                if (!sender.as<mux::UIElement>().CapturePointer(arguments.Pointer())) {
                    ActionUIWinUIPointerInput input{};
                    input.kind = ActionUIWinUIPointerInputCanceled;
                    std::shared_ptr<PointerInputHandler> keep = holder;
                    keep->handler(keep->context, &input);
                }
            }
        });
        target.PointerMoved([report](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (report(ActionUIWinUIPointerInputMoved, arguments)) {
                arguments.Handled(true);
            }
        });
        target.PointerReleased([report](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (report(ActionUIWinUIPointerInputReleased, arguments)) {
                arguments.Handled(true);
            }
            sender.as<mux::UIElement>().ReleasePointerCapture(arguments.Pointer());
        });
        target.PointerExited([report](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            report(ActionUIWinUIPointerInputExited, arguments);
        });
        target.PointerWheelChanged([report](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (report(ActionUIWinUIPointerInputWheel, arguments)) {
                arguments.Handled(true);
            }
        });
        auto canceled = [holder](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &) {
            ActionUIWinUIPointerInput input{};
            input.kind = ActionUIWinUIPointerInputCanceled;
            std::shared_ptr<PointerInputHandler> keep = holder;
            keep->handler(keep->context, &input);
        };
        target.PointerCaptureLost(canceled);
        target.PointerCanceled(canceled);
        return true;
    });
    if (!registered && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

bool actionUIWinUIElementOnPointerEvents(ActionUIWinUIObject *element, ActionUIWinUIPointerEventCallback handler, void *context,
                                         ActionUIWinUICallback destroyContext) {
    std::shared_ptr<PointerEventHandler> holder;
    bool registered = guarded("element on pointer events", [&]() {
        if (handler == nullptr) {
            return fail("element on pointer events", "the handler is NULL");
        }
        holder = std::make_shared<PointerEventHandler>(handler, context, destroyContext, currentQueue());
        mux::UIElement target = elementFrom(element);
        // A panel hit-tests only what is drawn in it unless it has a background: its whole area takes the input.
        if (muxc::Panel panel = target.try_as<muxc::Panel>(); panel != nullptr && panel.Background() == nullptr) {
            panel.Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        }
        auto report = [holder](ActionUIWinUIPointerEvent const &event) {
            std::shared_ptr<PointerEventHandler> keep = holder;
            return keep->handler(keep->context, &event);
        };
        // A pointer the element no longer holds, for a cancel.
        auto canceled = [report](mux::Input::PointerRoutedEventArgs const &arguments) {
            ActionUIWinUIPointerEvent event{};
            event.type = ActionUIWinUIPointerEventCanceled;
            event.button = -1;
            event.pointerID = arguments.Pointer().PointerId();
            switch (arguments.Pointer().PointerDeviceType()) {
            case winrt::Microsoft::UI::Input::PointerDeviceType::Touch:
                event.device = ActionUIWinUIPointerDeviceTouch;
                break;
            case winrt::Microsoft::UI::Input::PointerDeviceType::Pen:
                event.device = ActionUIWinUIPointerDevicePen;
                break;
            default:
                event.device = ActionUIWinUIPointerDeviceMouse;
                break;
            }
            report(event);
        };
        // Presses, moves and releases: any of them may carry a button's change.
        auto changed = [holder, report, canceled](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments,
                                                  ActionUIWinUIPointerEventType type) {
            mux::UIElement self = sender.as<mux::UIElement>();
            ActionUIWinUIPointerEvent event = pointerEventOf(type, self, arguments);
            bool taken = report(event);
            if (taken) {
                arguments.Handled(true);
            }
            if (event.type == ActionUIWinUIPointerEventPressed && taken && holder->captured.count(event.pointerID) == 0) {
                // Without the capture the moves and the release would not follow the press out of the element.
                if (self.CapturePointer(arguments.Pointer())) {
                    holder->captured.insert(event.pointerID);
                } else {
                    canceled(arguments);
                }
            } else if (event.type == ActionUIWinUIPointerEventReleased && event.buttons == 0 &&
                       holder->captured.erase(event.pointerID) > 0) {
                self.ReleasePointerCapture(arguments.Pointer());
            }
        };
        target.PointerPressed([changed](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            changed(sender, arguments, ActionUIWinUIPointerEventPressed);
        });
        target.PointerMoved([changed](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            changed(sender, arguments, ActionUIWinUIPointerEventMoved);
        });
        target.PointerReleased([changed](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            changed(sender, arguments, ActionUIWinUIPointerEventReleased);
        });
        target.PointerEntered([report](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            report(pointerEventOf(ActionUIWinUIPointerEventEntered, sender.as<mux::UIElement>(), arguments));
        });
        target.PointerExited([report](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            report(pointerEventOf(ActionUIWinUIPointerEventExited, sender.as<mux::UIElement>(), arguments));
        });
        target.PointerWheelChanged([report](wf::IInspectable const &sender, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (report(pointerEventOf(ActionUIWinUIPointerEventWheel, sender.as<mux::UIElement>(), arguments))) {
                arguments.Handled(true);
            }
        });
        // The capture's end after the element released the pointer itself is no cancel; any other is.
        target.PointerCaptureLost([holder, canceled](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (holder->captured.erase(arguments.Pointer().PointerId()) > 0) {
                canceled(arguments);
            }
        });
        target.PointerCanceled([holder, canceled](wf::IInspectable const &, mux::Input::PointerRoutedEventArgs const &arguments) {
            if (holder->captured.erase(arguments.Pointer().PointerId()) > 0) {
                canceled(arguments);
            }
        });
        return true;
    });
    if (!registered && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

void actionUIWinUIDoubleClickLimits(uint32_t *milliseconds, double *widthPixels, double *heightPixels) {
    if (milliseconds != nullptr) {
        *milliseconds = GetDoubleClickTime();
    }
    if (widthPixels != nullptr) {
        *widthPixels = GetSystemMetrics(SM_CXDOUBLECLK);
    }
    if (heightPixels != nullptr) {
        *heightPixels = GetSystemMetrics(SM_CYDOUBLECLK);
    }
}

} // extern "C"

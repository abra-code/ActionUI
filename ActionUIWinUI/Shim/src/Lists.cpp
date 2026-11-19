// Lists.cpp - WinUI's ListView for ActionUI's List: rows of text or of elements, single selection, and the
// double click or Return that activates a row.

#include "ShimInternal.h"

// ListView's SelectedIndex and SelectionChanged come from its Primitives::Selector base: without this
// header MSVC cannot use them (C3779).
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Windows.System.h>

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIListCreate(void) {
    return guardedObject("list create", []() {
        muxc::ListView list;
        list.SelectionMode(muxc::ListViewSelectionMode::Single);
        return toObject(list);
    });
}

bool actionUIWinUIListClear(ActionUIWinUIObject *list) {
    return guarded("list clear", [&]() {
        objectAs<muxc::ListView>(list, L"ListView").Items().Clear();
        return true;
    });
}

bool actionUIWinUIListAppendText(ActionUIWinUIObject *list, const char *text) {
    return guarded("list append text", [&]() {
        objectAs<muxc::ListView>(list, L"ListView").Items().Append(winrt::box_value(toHString(text)));
        return true;
    });
}

bool actionUIWinUIListAppendElement(ActionUIWinUIObject *list, ActionUIWinUIObject *element) {
    return guarded("list append element", [&]() {
        muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
        typed.Items().Append(objectAs<mux::UIElement>(element, L"UIElement"));
        return true;
    });
}

bool actionUIWinUIListReplaceElement(ActionUIWinUIObject *list, int32_t index, ActionUIWinUIObject *element) {
    return guarded("list replace element", [&]() {
        auto items = objectAs<muxc::ListView>(list, L"ListView").Items();
        if (index < 0 || static_cast<uint32_t>(index) >= items.Size()) {
            return fail("list replace element", "no item at that index");
        }
        items.SetAt(static_cast<uint32_t>(index), objectAs<mux::UIElement>(element, L"UIElement"));
        return true;
    });
}

ActionUIWinUIObject *actionUIWinUIListCopyItemElement(ActionUIWinUIObject *list, int32_t index) {
    return guardedObject("list copy item element", [&]() -> ActionUIWinUIObject * {
        auto items = objectAs<muxc::ListView>(list, L"ListView").Items();
        if (index < 0 || static_cast<uint32_t>(index) >= items.Size()) {
            fail("list copy item element", "no item at that index");
            return nullptr;
        }
        mux::UIElement element = items.GetAt(static_cast<uint32_t>(index)).try_as<mux::UIElement>();
        if (element == nullptr) {
            fail("list copy item element", "the item shows text, not an element");
            return nullptr;
        }
        return toObject(element);
    });
}

bool actionUIWinUIListTruncate(ActionUIWinUIObject *list, int32_t count) {
    return guarded("list truncate", [&]() {
        auto items = objectAs<muxc::ListView>(list, L"ListView").Items();
        uint32_t kept = count > 0 ? static_cast<uint32_t>(count) : 0;
        while (items.Size() > kept) {
            items.RemoveAtEnd();
        }
        return true;
    });
}

bool actionUIWinUIListSetSelectable(ActionUIWinUIObject *list, bool selectable) {
    return guarded("list set selectable", [&]() {
        muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
        muxc::ListViewSelectionMode wanted = selectable ? muxc::ListViewSelectionMode::Single : muxc::ListViewSelectionMode::None;
        if (typed.SelectionMode() != wanted) {
            typed.SelectionMode(wanted);
        }
        return true;
    });
}

bool actionUIWinUIListSetSelectedIndex(ActionUIWinUIObject *list, int32_t index) {
    return guarded("list set selected index", [&]() {
        muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
        int32_t selected = index >= 0 && static_cast<uint32_t>(index) < typed.Items().Size() ? index : -1;
        if (typed.SelectionMode() == muxc::ListViewSelectionMode::None) {
            selected = -1;
        }
        if (typed.SelectedIndex() != selected) {
            typed.SelectedIndex(selected);
        }
        return true;
    });
}

int32_t actionUIWinUIListGetSelectedIndex(ActionUIWinUIObject *list) {
    int32_t selected = -1;
    guarded("list get selected index", [&]() {
        selected = objectAs<muxc::ListView>(list, L"ListView").SelectedIndex();
        return true;
    });
    return selected;
}

bool actionUIWinUIListOnSelectionChanged(ActionUIWinUIObject *list, ActionUIWinUICallback handler, void *context,
                                         ActionUIWinUICallback destroyContext) {
    return registerHandler("list on selection changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::ListView>(list, L"ListView")
                                   .SelectionChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUIListOnActivated(ActionUIWinUIObject *list, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("list on activated", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
                               typed.DoubleTapped([holder](auto &&, auto &&) { holder->fire(); });
                               // Handled events too: the ListView or its item may mark Return handled
                               // before an ordinary KeyDown handler would see it.
                               typed.AddHandler(mux::UIElement::KeyDownEvent(),
                                                winrt::box_value(mux::Input::KeyEventHandler(
                                                    [holder](wf::IInspectable const &, mux::Input::KeyRoutedEventArgs const &args) {
                                                        if (args.Key() == winrt::Windows::System::VirtualKey::Enter) {
                                                            holder->fire();
                                                        }
                                                    })),
                                                true);
                           });
}

} // extern "C"

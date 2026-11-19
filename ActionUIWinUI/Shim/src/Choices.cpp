// Choices.cpp - the controls a Picker shows: a ComboBox (menu), a RadioButtons group (radio group) and a
// SelectorBar (segmented), behind one interface: items by title, a selected index, a selection event.

#include "ShimInternal.h"

// ComboBox's SelectedIndex and SelectionChanged come from its Primitives::Selector base: without this
// header MSVC cannot use them (C3779).
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>

using namespace actionui_winui;

namespace {

// The items a choice control holds, as an editable vector of boxed titles (ComboBox, RadioButtons).
wf::Collections::IVector<wf::IInspectable> titleItems(mux::UIElement const &control) {
    if (muxc::ComboBox combo = control.try_as<muxc::ComboBox>(); combo != nullptr) {
        return combo.Items();
    }
    if (muxc::RadioButtons radios = control.try_as<muxc::RadioButtons>(); radios != nullptr) {
        return radios.Items();
    }
    return nullptr;
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIChoiceCreate(ActionUIWinUIChoiceKind kind) {
    return guardedObject("choice create", [&]() -> ActionUIWinUIObject * {
        switch (kind) {
        case ActionUIWinUIChoiceMenu: {
            muxc::ComboBox combo;
            return toObject(combo);
        }
        case ActionUIWinUIChoiceRadio: {
            muxc::RadioButtons radios;
            return toObject(radios);
        }
        case ActionUIWinUIChoiceSegments: {
            muxc::SelectorBar bar;
            return toObject(bar);
        }
        }
        fail("choice create", "unknown choice kind");
        return nullptr;
    });
}

bool actionUIWinUIChoiceSetItems(ActionUIWinUIObject *choice, const char *const *titles, int32_t count) {
    return guarded("choice set items", [&]() {
        if (count < 0 || (count > 0 && titles == nullptr)) {
            return fail("choice set items", "no titles");
        }
        mux::UIElement typed = objectAs<mux::UIElement>(choice, L"UIElement");
        if (muxc::SelectorBar bar = typed.try_as<muxc::SelectorBar>(); bar != nullptr) {
            bar.SelectedItem(nullptr);
            bar.Items().Clear();
            for (int32_t index = 0; index < count; index++) {
                muxc::SelectorBarItem item;
                item.Text(toHString(titles[index]));
                bar.Items().Append(item);
            }
            return true;
        }
        wf::Collections::IVector<wf::IInspectable> items = titleItems(typed);
        if (items == nullptr) {
            return fail("choice set items", "the element is not a choice control");
        }
        items.Clear();
        for (int32_t index = 0; index < count; index++) {
            items.Append(winrt::box_value(toHString(titles[index])));
        }
        return true;
    });
}

bool actionUIWinUIChoiceSetSelectedIndex(ActionUIWinUIObject *choice, int32_t index) {
    return guarded("choice set selected index", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(choice, L"UIElement");
        if (muxc::SelectorBar bar = typed.try_as<muxc::SelectorBar>(); bar != nullptr) {
            uint32_t size = bar.Items().Size();
            muxc::SelectorBarItem wanted = index >= 0 && static_cast<uint32_t>(index) < size
                                               ? bar.Items().GetAt(static_cast<uint32_t>(index))
                                               : nullptr;
            if (bar.SelectedItem() != wanted) {
                bar.SelectedItem(wanted);
            }
            return true;
        }
        wf::Collections::IVector<wf::IInspectable> items = titleItems(typed);
        if (items == nullptr) {
            return fail("choice set selected index", "the element is not a choice control");
        }
        int32_t selected = index >= 0 && static_cast<uint32_t>(index) < items.Size() ? index : -1;
        if (muxc::ComboBox combo = typed.try_as<muxc::ComboBox>(); combo != nullptr) {
            if (combo.SelectedIndex() != selected) {
                combo.SelectedIndex(selected);
            }
        } else if (muxc::RadioButtons radios = typed.try_as<muxc::RadioButtons>(); radios != nullptr) {
            if (radios.SelectedIndex() != selected) {
                radios.SelectedIndex(selected);
            }
        }
        return true;
    });
}

int32_t actionUIWinUIChoiceGetSelectedIndex(ActionUIWinUIObject *choice) {
    int32_t selected = -1;
    guarded("choice get selected index", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(choice, L"UIElement");
        if (muxc::SelectorBar bar = typed.try_as<muxc::SelectorBar>(); bar != nullptr) {
            uint32_t found = 0;
            if (bar.SelectedItem() != nullptr && bar.Items().IndexOf(bar.SelectedItem(), found)) {
                selected = static_cast<int32_t>(found);
            }
        } else if (muxc::ComboBox combo = typed.try_as<muxc::ComboBox>(); combo != nullptr) {
            selected = combo.SelectedIndex();
        } else if (muxc::RadioButtons radios = typed.try_as<muxc::RadioButtons>(); radios != nullptr) {
            selected = radios.SelectedIndex();
        } else {
            return fail("choice get selected index", "the element is not a choice control");
        }
        return true;
    });
    return selected;
}

bool actionUIWinUIChoiceSetColumns(ActionUIWinUIObject *choice, int32_t columns) {
    return guarded("choice set columns", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(choice, L"UIElement");
        if (muxc::RadioButtons radios = typed.try_as<muxc::RadioButtons>(); radios != nullptr) {
            int32_t wanted = columns < 1 ? 1 : columns;
            if (radios.MaxColumns() != wanted) {
                radios.MaxColumns(wanted);
            }
        }
        return true;
    });
}

bool actionUIWinUIChoiceOnSelectionChanged(ActionUIWinUIObject *choice, ActionUIWinUICallback handler, void *context,
                                           ActionUIWinUICallback destroyContext) {
    return registerHandler("choice on selection changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               mux::UIElement typed = objectAs<mux::UIElement>(choice, L"UIElement");
                               if (muxc::SelectorBar bar = typed.try_as<muxc::SelectorBar>(); bar != nullptr) {
                                   bar.SelectionChanged([holder](auto &&, auto &&) { holder->fire(); });
                               } else if (muxc::ComboBox combo = typed.try_as<muxc::ComboBox>(); combo != nullptr) {
                                   combo.SelectionChanged([holder](auto &&, auto &&) { holder->fire(); });
                               } else if (muxc::RadioButtons radios = typed.try_as<muxc::RadioButtons>(); radios != nullptr) {
                                   radios.SelectionChanged([holder](auto &&, auto &&) { holder->fire(); });
                               } else {
                                   throw winrt::hresult_invalid_argument(L"the element is not a choice control");
                               }
                           });
}

} // extern "C"

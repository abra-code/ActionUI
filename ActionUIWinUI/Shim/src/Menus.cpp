// Menus.cpp - a DropDownButton and its MenuFlyout for ActionUI's Menu: items, check items, radio items,
// separators, submenus and headers, and the click that chooses an item; and the MenuBar that shows the
// application's menus across the top of a window.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // FlyoutBase

using namespace actionui_winui;

namespace {

// The items of `menu`: a MenuFlyout's, a MenuFlyoutSubItem's or a MenuBarItem's.
wf::Collections::IVector<muxc::MenuFlyoutItemBase> itemsOf(ActionUIWinUIObject *menu) {
    wf::IInspectable object = objectAs<wf::IInspectable>(menu, L"menu");
    if (muxc::MenuFlyout flyout = object.try_as<muxc::MenuFlyout>()) {
        return flyout.Items();
    }
    if (muxc::MenuFlyoutSubItem submenu = object.try_as<muxc::MenuFlyoutSubItem>()) {
        return submenu.Items();
    }
    if (muxc::MenuBarItem barMenu = object.try_as<muxc::MenuBarItem>()) {
        return barMenu.Items();
    }
    throw winrt::hresult_no_interface(L"the object is not a MenuFlyout, a MenuFlyoutSubItem or a MenuBarItem");
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIMenuButtonCreate(void) {
    return guardedObject("menu button create", []() {
        muxc::DropDownButton button;
        button.Flyout(muxc::MenuFlyout());
        return toObject(button);
    });
}

ActionUIWinUIObject *actionUIWinUIMenuButtonCopyMenu(ActionUIWinUIObject *button) {
    return guardedObject("menu button copy menu", [&]() -> ActionUIWinUIObject * {
        muxc::MenuFlyout menu = objectAs<muxc::DropDownButton>(button, L"DropDownButton").Flyout().try_as<muxc::MenuFlyout>();
        if (menu == nullptr) {
            fail("menu button copy menu", "the button has no menu");
            return nullptr;
        }
        return toObject(menu);
    });
}

bool actionUIWinUIMenuClear(ActionUIWinUIObject *menu) {
    return guarded("menu clear", [&]() {
        itemsOf(menu).Clear();
        return true;
    });
}

ActionUIWinUIObject *actionUIWinUIMenuAppend(ActionUIWinUIObject *menu, ActionUIWinUIMenuItemKind kind, const char *title,
                                             bool enabled, bool checked, const char *group) {
    return guardedObject("menu append", [&]() -> ActionUIWinUIObject * {
        wf::Collections::IVector<muxc::MenuFlyoutItemBase> items = itemsOf(menu);
        muxc::MenuFlyoutItemBase item{nullptr};
        switch (kind) {
        case ActionUIWinUIMenuItem: {
            muxc::MenuFlyoutItem plain;
            plain.Text(toHString(title));
            item = plain;
            break;
        }
        case ActionUIWinUIMenuItemToggle: {
            muxc::ToggleMenuFlyoutItem toggle;
            toggle.Text(toHString(title));
            toggle.IsChecked(checked);
            item = toggle;
            break;
        }
        case ActionUIWinUIMenuItemRadio: {
            muxc::RadioMenuFlyoutItem radio;
            radio.Text(toHString(title));
            radio.GroupName(toHString(group));
            radio.IsChecked(checked);
            item = radio;
            break;
        }
        case ActionUIWinUIMenuItemSeparator:
            item = muxc::MenuFlyoutSeparator();
            break;
        case ActionUIWinUIMenuItemSubmenu: {
            muxc::MenuFlyoutSubItem submenu;
            submenu.Text(toHString(title));
            item = submenu;
            break;
        }
        case ActionUIWinUIMenuItemHeader: {
            // Windows menus have no header: a disabled item, dimmed, that cannot be chosen.
            muxc::MenuFlyoutItem header;
            header.Text(toHString(title));
            header.IsEnabled(false);
            item = header;
            break;
        }
        default:
            fail("menu append", "unknown item kind");
            return nullptr;
        }
        if (kind != ActionUIWinUIMenuItemSeparator && kind != ActionUIWinUIMenuItemHeader) {
            item.IsEnabled(enabled);
        }
        items.Append(item);
        return toObject(item);
    });
}

bool actionUIWinUIMenuItemSetChecked(ActionUIWinUIObject *item, bool checked) {
    return guarded("menu item set checked", [&]() {
        wf::IInspectable object = objectAs<wf::IInspectable>(item, L"menu item");
        if (muxc::ToggleMenuFlyoutItem toggle = object.try_as<muxc::ToggleMenuFlyoutItem>()) {
            if (toggle.IsChecked() != checked) {
                toggle.IsChecked(checked);
            }
            return true;
        }
        if (muxc::RadioMenuFlyoutItem radio = object.try_as<muxc::RadioMenuFlyoutItem>()) {
            if (radio.IsChecked() != checked) {
                radio.IsChecked(checked);
            }
            return true;
        }
        return fail("menu item set checked", "the item is not a check or radio item");
    });
}

bool actionUIWinUIMenuItemOnClick(ActionUIWinUIObject *item, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("menu item on click", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::MenuFlyoutItem>(item, L"MenuFlyoutItem").Click([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

ActionUIWinUIObject *actionUIWinUIMenuCopyItem(ActionUIWinUIObject *menu, int32_t index) {
    return guardedObject("menu copy item", [&]() -> ActionUIWinUIObject * {
        wf::Collections::IVector<muxc::MenuFlyoutItemBase> items = itemsOf(menu);
        if (index < 0 || static_cast<uint32_t>(index) >= items.Size()) {
            fail("menu copy item", "no item at that index");
            return nullptr;
        }
        return toObject(items.GetAt(static_cast<uint32_t>(index)));
    });
}

ActionUIWinUIObject *actionUIWinUIMenuBarCreate(void) {
    return guardedObject("menu bar create", []() {
        return toObject(muxc::MenuBar());
    });
}

ActionUIWinUIObject *actionUIWinUIMenuBarAppendMenu(ActionUIWinUIObject *menuBar, const char *title) {
    return guardedObject("menu bar append menu", [&]() {
        muxc::MenuBarItem menu;
        menu.Title(title != nullptr ? toHString(title) : winrt::hstring{});
        objectAs<muxc::MenuBar>(menuBar, L"MenuBar").Items().Append(menu);
        return toObject(menu);
    });
}

} // extern "C"

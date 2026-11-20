// Lists.cpp - WinUI's ListView for ActionUI's List: rows of text or of elements, single selection, the
// double click or Return that activates a row, and rows made as they come into view (an element source).

#include "ShimInternal.h"

// ListView's SelectedIndex and SelectionChanged come from its Primitives::Selector base: without this
// header MSVC cannot use them (C3779).
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper
#include <winrt/Windows.System.h>

using namespace actionui_winui;

namespace {

// A ListView's element source: the caller's callbacks, freed (destroyContext, on the UI thread) when the
// ListView lets go of its ContainerContentChanging handler.
struct ListElementSource {
    ListElementSource(ActionUIWinUIRepeaterMake make, ActionUIWinUIRepeaterRecycle recycle, void *context,
                      ActionUIWinUICallback destroyContext, dispatching::DispatcherQueue queue)
        : make(make), recycle(recycle), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    ListElementSource(ListElementSource const &) = delete;
    ListElementSource &operator=(ListElementSource const &) = delete;
    ~ListElementSource() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }

    // Gives the element `container` shows back to the caller, and empties the container.
    void giveBack(muxc::ContentControl const &container) const {
        mux::UIElement element = container.Content() != nullptr ? container.Content().try_as<mux::UIElement>() : nullptr;
        if (element == nullptr) {
            return;
        }
        container.Content(nullptr);
        recycle(context, static_cast<ActionUIWinUIObject *>(winrt::get_abi(element)));
    }

    ActionUIWinUIRepeaterMake make;
    ActionUIWinUIRepeaterRecycle recycle;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// The ListView's rows when it shows an element source: one boxed index per row.
wf::Collections::IObservableVector<wf::IInspectable> sourceRows(muxc::ListView const &list) {
    wf::Collections::IObservableVector<wf::IInspectable> rows =
        list.ItemsSource() != nullptr ? list.ItemsSource().try_as<wf::Collections::IObservableVector<wf::IInspectable>>() : nullptr;
    if (rows == nullptr) {
        throw winrt::hresult_illegal_method_call(L"the list does not show an element source");
    }
    return rows;
}

} // namespace

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
            // An element source's row: the element its container shows, when the row is made.
            muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
            muxc::ContentControl container =
                typed.ItemsSource() != nullptr ? typed.ContainerFromIndex(index).try_as<muxc::ContentControl>() : nullptr;
            element = container != nullptr && container.Content() != nullptr ? container.Content().try_as<mux::UIElement>() : nullptr;
            // Shown only when the container presents it (a template expanded instead leaves it out of the window).
            if (element != nullptr && winrt::Microsoft::UI::Xaml::Media::VisualTreeHelper::GetParent(element) == nullptr) {
                fail("list copy item element", "the row's element is not in the window");
                return nullptr;
            }
        }
        if (element == nullptr) {
            fail("list copy item element", "the item shows text, not an element (or its row is not made)");
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

bool actionUIWinUIListSetElementSource(ActionUIWinUIObject *list, ActionUIWinUIRepeaterMake make,
                                       ActionUIWinUIRepeaterRecycle recycle, void *context,
                                       ActionUIWinUICallback destroyContext) {
    std::shared_ptr<ListElementSource> source;
    bool registered = guarded("list set element source", [&]() {
        if (make == nullptr || recycle == nullptr) {
            return fail("list set element source", "a callback is NULL");
        }
        source = std::make_shared<ListElementSource>(make, recycle, context, destroyContext, currentQueue());
        objectAs<muxc::ListView>(list, L"ListView")
            .ContainerContentChanging([source](muxc::ListViewBase const &sender, muxc::ContainerContentChangingEventArgs const &args) {
                // Only the source's rows: the ListView's own items show themselves.
                if (sender.ItemsSource() == nullptr) {
                    return;
                }
                muxc::ContentControl container = args.ItemContainer().try_as<muxc::ContentControl>();
                if (container == nullptr) {
                    return;
                }
                if (args.InRecycleQueue()) {
                    source->giveBack(container);
                } else {
                    // A container reused without a recycle still holds its last row's element.
                    source->giveBack(container);
                    int32_t index = winrt::unbox_value_or<int32_t>(args.Item(), -1);
                    ActionUIWinUIObject *made = index >= 0 ? source->make(source->context, index) : nullptr;
                    // The prepare before this event gave the container the default template for an item that
                    // is not an element (a TextBlock bound to it), which a ContentPresenter expands instead of
                    // showing an element content: without a template it shows the element.
                    container.ContentTemplate(nullptr);
                    // The caller lends the element; the container takes its own reference.
                    container.Content(made != nullptr ? objectAs<mux::UIElement>(made, L"UIElement") : nullptr);
                }
                args.Handled(true);
            });
        return true;
    });
    if (!registered && source == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

bool actionUIWinUIListUseElementSource(ActionUIWinUIObject *list, bool use) {
    return guarded("list use element source", [&]() {
        muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
        if (use) {
            if (typed.ItemsSource() == nullptr) {
                // Items and ItemsSource exclude each other.
                typed.Items().Clear();
                typed.ItemsSource(winrt::single_threaded_observable_vector<wf::IInspectable>());
            }
        } else if (typed.ItemsSource() != nullptr) {
            typed.ItemsSource(nullptr);
        }
        return true;
    });
}

int32_t actionUIWinUIListSourceCount(ActionUIWinUIObject *list) {
    int32_t count = -1;
    guarded("list source count", [&]() {
        count = static_cast<int32_t>(sourceRows(objectAs<muxc::ListView>(list, L"ListView")).Size());
        return true;
    });
    return count;
}

bool actionUIWinUIListSourceAppend(ActionUIWinUIObject *list, int32_t count) {
    return guarded("list source append", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> rows = sourceRows(objectAs<muxc::ListView>(list, L"ListView"));
        for (int32_t added = 0; added < count; ++added) {
            rows.Append(winrt::box_value(static_cast<int32_t>(rows.Size())));
        }
        return true;
    });
}

bool actionUIWinUIListSourceReplace(ActionUIWinUIObject *list, int32_t index) {
    return guarded("list source replace", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> rows = sourceRows(objectAs<muxc::ListView>(list, L"ListView"));
        if (index < 0 || static_cast<uint32_t>(index) >= rows.Size()) {
            return fail("list source replace", "no such row");
        }
        // A new box: the ListView recycles the row's container and prepares it again.
        rows.SetAt(static_cast<uint32_t>(index), winrt::box_value(index));
        return true;
    });
}

bool actionUIWinUIListSourceTruncate(ActionUIWinUIObject *list, int32_t count) {
    return guarded("list source truncate", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> rows = sourceRows(objectAs<muxc::ListView>(list, L"ListView"));
        uint32_t kept = count > 0 ? static_cast<uint32_t>(count) : 0;
        while (rows.Size() > kept) {
            rows.RemoveAtEnd();
        }
        return true;
    });
}

bool actionUIWinUIListScrollIntoView(ActionUIWinUIObject *list, int32_t index) {
    return guarded("list scroll into view", [&]() {
        muxc::ListView typed = objectAs<muxc::ListView>(list, L"ListView");
        if (index < 0 || static_cast<uint32_t>(index) >= typed.Items().Size()) {
            return fail("list scroll into view", "no such row");
        }
        typed.ScrollIntoView(typed.Items().GetAt(static_cast<uint32_t>(index)));
        return true;
    });
}

} // extern "C"

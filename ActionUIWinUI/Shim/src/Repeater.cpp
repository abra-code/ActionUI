// Repeater.cpp - an ItemsRepeater whose elements the caller makes (a lazy stack's rows): WinUI's
// virtualizing control, which realizes only the items in or near the part of it its scroll viewers
// show, estimates the others' sizes and keeps the scroll position anchored as they change.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Controls.h>

using namespace actionui_winui;

namespace {

// The repeater's element factory: each element comes from the caller's make callback and goes back
// through its recycle callback. (WinUI 3 has IElementFactory and its args in Microsoft.UI.Xaml, not
// in Controls as WinUI 2 did.)
struct CallbackElementFactory : winrt::implements<CallbackElementFactory, mux::IElementFactory> {
    CallbackElementFactory(ActionUIWinUIRepeaterMake make, ActionUIWinUIRepeaterRecycle recycle, void *context,
                           ActionUIWinUICallback destroyContext)
        : m_make(make), m_recycle(recycle), m_context(context), m_destroyContext(destroyContext),
          m_queue(dispatching::DispatcherQueue::GetForCurrentThread()) {}

    // The context belongs to the UI thread: from any other thread, destroyContext is sent there.
    ~CallbackElementFactory() {
        callOnUIThread(m_queue, m_destroyContext, m_context);
    }

    mux::UIElement GetElement(mux::ElementFactoryGetArgs const &args) {
        int32_t index = winrt::unbox_value_or<int32_t>(args.Data(), -1);
        ActionUIWinUIObject *made = index >= 0 ? m_make(m_context, index) : nullptr;
        if (made == nullptr) {
            // The repeater needs an element for every item: an empty one stands for a row that could not be made.
            return muxc::Grid();
        }
        // The caller lends the element for the call; the repeater takes its own reference.
        return objectAs<mux::UIElement>(made, L"UIElement");
    }

    void RecycleElement(mux::ElementFactoryRecycleArgs const &args) {
        mux::UIElement element = args.Element();
        if (element == nullptr) {
            return;
        }
        // With a factory of its own, the repeater leaves the element among its children (a pool would keep
        // it there for reuse): taken out here, as the repeater does when it has no factory.
        if (muxc::Panel parent = args.Parent() != nullptr ? args.Parent().try_as<muxc::Panel>() : nullptr) {
            uint32_t position = 0;
            if (parent.Children().IndexOf(element, position)) {
                parent.Children().RemoveAt(position);
            }
        }
        m_recycle(m_context, static_cast<ActionUIWinUIObject *>(winrt::get_abi(element)));
    }

private:
    ActionUIWinUIRepeaterMake m_make;
    ActionUIWinUIRepeaterRecycle m_recycle;
    void *m_context;
    ActionUIWinUICallback m_destroyContext;
    dispatching::DispatcherQueue m_queue;
};

muxc::ItemsRepeater repeaterFrom(ActionUIWinUIObject *repeater) {
    return objectAs<muxc::ItemsRepeater>(repeater, L"ItemsRepeater");
}

// The repeater's items: one boxed index per row, the data each element is made for.
wf::Collections::IObservableVector<wf::IInspectable> itemsOf(muxc::ItemsRepeater const &repeater) {
    wf::Collections::IObservableVector<wf::IInspectable> items =
        repeater.ItemsSource() != nullptr ? repeater.ItemsSource().try_as<wf::Collections::IObservableVector<wf::IInspectable>>() : nullptr;
    if (items == nullptr) {
        throw winrt::hresult_illegal_method_call(L"the repeater has no items of its own");
    }
    return items;
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIRepeaterCreate(bool vertical, ActionUIWinUIRepeaterMake make,
                                                 ActionUIWinUIRepeaterRecycle recycle, void *context,
                                                 ActionUIWinUICallback destroyContext) {
    bool constructed = false;
    ActionUIWinUIObject *result = guardedObject("repeater create", [&]() -> ActionUIWinUIObject * {
        if (make == nullptr || recycle == nullptr) {
            fail("repeater create", "a callback is NULL");
            return nullptr;
        }
        mux::IElementFactory factory = winrt::make<CallbackElementFactory>(make, recycle, context, destroyContext);
        constructed = true;
        muxc::StackLayout layout;
        layout.Orientation(vertical ? muxc::Orientation::Vertical : muxc::Orientation::Horizontal);
        layout.Spacing(0);
        muxc::ItemsRepeater repeater;
        repeater.Layout(layout);
        repeater.ItemTemplate(factory);
        repeater.ItemsSource(winrt::single_threaded_observable_vector<wf::IInspectable>());
        return toObject(repeater);
    });
    // Once made, the factory's destructor calls destroyContext, also on a failure after it.
    if (result == nullptr && !constructed && destroyContext != nullptr) {
        destroyContext(context);
    }
    return result;
}

bool actionUIWinUIRepeaterSetSpacing(ActionUIWinUIObject *repeater, double spacing) {
    return guarded("repeater set spacing", [&]() {
        muxc::StackLayout layout = repeaterFrom(repeater).Layout().try_as<muxc::StackLayout>();
        if (layout == nullptr) {
            return fail("repeater set spacing", "the repeater has no stack layout");
        }
        if (layout.Spacing() != spacing) {
            layout.Spacing(spacing);
        }
        return true;
    });
}

int32_t actionUIWinUIRepeaterCount(ActionUIWinUIObject *repeater) {
    int32_t count = -1;
    guarded("repeater count", [&]() {
        count = static_cast<int32_t>(itemsOf(repeaterFrom(repeater)).Size());
        return true;
    });
    return count;
}

bool actionUIWinUIRepeaterAppend(ActionUIWinUIObject *repeater) {
    return guarded("repeater append", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> items = itemsOf(repeaterFrom(repeater));
        items.Append(winrt::box_value(static_cast<int32_t>(items.Size())));
        return true;
    });
}

bool actionUIWinUIRepeaterReplace(ActionUIWinUIObject *repeater, int32_t index) {
    return guarded("repeater replace", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> items = itemsOf(repeaterFrom(repeater));
        if (index < 0 || static_cast<uint32_t>(index) >= items.Size()) {
            return fail("repeater replace", "no such item");
        }
        // A new box: the repeater recycles the item's element and asks for a new one.
        items.SetAt(static_cast<uint32_t>(index), winrt::box_value(index));
        return true;
    });
}

bool actionUIWinUIRepeaterTruncate(ActionUIWinUIObject *repeater, int32_t count) {
    return guarded("repeater truncate", [&]() {
        wf::Collections::IObservableVector<wf::IInspectable> items = itemsOf(repeaterFrom(repeater));
        if (count < 0) {
            return fail("repeater truncate", "the count is negative");
        }
        while (items.Size() > static_cast<uint32_t>(count)) {
            items.RemoveAtEnd();
        }
        return true;
    });
}

ActionUIWinUIObject *actionUIWinUIRepeaterCopyElement(ActionUIWinUIObject *repeater, int32_t index) {
    return guardedObject("repeater copy element", [&]() -> ActionUIWinUIObject * {
        mux::UIElement element = repeaterFrom(repeater).TryGetElement(index);
        if (element == nullptr) {
            fail("repeater copy element", "the item has no element (it is not realized)");
            return nullptr;
        }
        return toObject(element);
    });
}

bool actionUIWinUIObjectIsSame(ActionUIWinUIObject *a, ActionUIWinUIObject *b) {
    bool same = false;
    guarded("object is same", [&]() {
        if (a == nullptr || b == nullptr) {
            return true;
        }
        wf::IInspectable first{nullptr};
        wf::IInspectable second{nullptr};
        winrt::copy_from_abi(first, a);
        winrt::copy_from_abi(second, b);
        // COM identity: the IUnknown each gives is the same pointer for one object.
        same = first.as<winrt::Windows::Foundation::IUnknown>() == second.as<winrt::Windows::Foundation::IUnknown>();
        return true;
    });
    return same;
}

} // extern "C"

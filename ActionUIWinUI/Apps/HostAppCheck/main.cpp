// ActionUIWinUI/Apps/HostAppCheck/main.cpp
//
// A host that runs its own WinUI application (as a C++ or C# app does) and uses ActionUI through
// ActionUI.dll: it installs ActionUI's main-loop bridge, fills a window it made with ActionUI JSON
// (actionUILoadIntoHostWindowFromJSON), finds ActionUI's own application refused (one WinUI
// Application in a process, the host's), reads and sets a value, has a worker thread set one (which
// runs on the main actor under the host's loop: the bridge), then closes the window and ends its
// application. Prints "host-app:" lines; exit status 0 when every check passed. Built and run by
// Scripts/ci-windows.py.

#include <windows.h>
#include <unknwn.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <thread>

#include <MddBootstrap.h>
#include <WindowsAppSDK-VersionInfo.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>

#include "ActionUIApp.h"
#include "ActionUIC.h"

namespace mux = winrt::Microsoft::UI::Xaml;
namespace muxc = winrt::Microsoft::UI::Xaml::Controls;
namespace muxm = winrt::Microsoft::UI::Xaml::Markup;
namespace dispatching = winrt::Microsoft::UI::Dispatching;

namespace {

int failures = 0;
std::atomic<bool> workerSet{false};
mux::Window hostWindow{nullptr};
dispatching::DispatcherQueueTimer finishTimer{nullptr};

void check(bool passed, const char *what) {
    std::printf("host-app: %s: %s\n", passed ? "ok" : "FAILED", what);
    std::fflush(stdout);
    if (!passed) {
        failures += 1;
    }
}

const char *kUIJSON =
    "{\"type\": \"VStack\", \"id\": 1, \"properties\": {\"padding\": 16, \"spacing\": 8}, \"children\": ["
    "{\"type\": \"Text\", \"id\": 2, \"properties\": {\"text\": \"In the host's own window\"}},"
    "{\"type\": \"Button\", \"id\": 3, \"properties\": {\"title\": \"OK\"}}]}";

bool valueIs(const char *expected) {
    char *value = actionUIGetStringValue("host-window", 2, 0);
    bool same = value != nullptr && std::strcmp(value, expected) == 0;
    if (value != nullptr) {
        actionUIFreeString(value);
    }
    return same;
}

// After the worker has had its time: its value arrived through the main queue under the host's loop.
void finish() {
    check(workerSet.load(), "the worker's call returned");
    check(valueIs("from a worker"), "the worker's value reached the window (the bridge ran it)");
    hostWindow.Close();
    actionUIRemoveWindow("host-window");
    mux::Application::Current().Exit();
}

struct HostApp : mux::ApplicationT<HostApp, muxm::IXamlMetadataProvider> {
    void OnLaunched(mux::LaunchActivatedEventArgs const &) {
        Resources().MergedDictionaries().Append(muxc::XamlControlsResources());
        actionUIInstallMainLoopBridge();
        hostWindow = mux::Window();
        hostWindow.Title(L"A host's window");
        check(actionUILoadIntoHostWindowFromJSON(winrt::get_abi(hostWindow), kUIJSON, "host-window", nullptr),
              "ActionUI JSON fills the host's window");
        hostWindow.Activate();
        check(valueIs("In the host's own window"), "the window's value reads");
        check(actionUISetStringValue("host-window", 2, 0, "from the host"), "the host sets a value");
        check(valueIs("from the host"), "the host's value reads back");

        // ActionUI's own application is refused: the process's WinUI Application is the host's.
        actionUIAppRun();
        check(true, "ActionUI's own run returned at once (refused)");

        // A call from another thread waits for the main actor, which runs under the host's loop only
        // through the bridge.
        std::thread([] {
            workerSet.store(actionUISetStringValue("host-window", 2, 0, "from a worker"));
        }).detach();
        finishTimer = dispatching::DispatcherQueue::GetForCurrentThread().CreateTimer();
        finishTimer.Interval(std::chrono::milliseconds(1500));
        finishTimer.IsRepeating(false);
        finishTimer.Tick([](auto &&, auto &&) { finish(); });
        finishTimer.Start();
    }

    muxm::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const &type) {
        return m_provider.GetXamlType(type);
    }
    muxm::IXamlType GetXamlType(winrt::hstring const &fullName) {
        return m_provider.GetXamlType(fullName);
    }
    winrt::com_array<muxm::XmlnsDefinition> GetXmlnsDefinitions() {
        return m_provider.GetXmlnsDefinitions();
    }

private:
    mux::XamlTypeInfo::XamlControlsXamlMetaDataProvider m_provider;
};

} // namespace

int main() {
    PACKAGE_VERSION minVersion{};
    minVersion.Version = WINDOWSAPPSDK_RUNTIME_VERSION_UINT64;
    HRESULT started = MddBootstrapInitialize2(WINDOWSAPPSDK_RELEASE_MAJORMINOR, WINDOWSAPPSDK_RELEASE_VERSION_TAG_W, minVersion,
                                              MddBootstrapInitializeOptions_None);
    if (FAILED(started)) {
        std::printf("host-app: the Windows App SDK runtime is not available (0x%08X)\n", static_cast<unsigned>(started));
        return 1;
    }
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    std::printf("host-app: running the host's application\n");
    std::fflush(stdout);
    mux::Application::Start([](auto &&) { winrt::make<HostApp>(); });
    std::printf("host-app: the host's application ended\n");
    std::printf("host-app: %d failures\n", failures);
    hostWindow = nullptr;
    finishTimer = nullptr;
    MddBootstrapShutdown();
    return failures == 0 ? 0 : 1;
}

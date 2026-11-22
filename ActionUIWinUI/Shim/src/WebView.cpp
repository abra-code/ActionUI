// WebView.cpp - a web view (WinUI's WebView2, on the WebView2 runtime that Windows ships): its
// CoreWebView2 is made asynchronously, so what is asked of the view before then (a user agent, scripts,
// the first page) waits in order and runs once it is ready.

#include "ShimInternal.h"

#include <cstdlib>  // malloc
#include <cstring>
#include <cwctype>  // towlower
#include <deque>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

#include <winrt/Microsoft.Web.WebView2.Core.h>
#include <winrt/Windows.Storage.Streams.h>

namespace actionui_winui {

namespace {

namespace webcore = winrt::Microsoft::Web::WebView2::Core;

// What waits for the CoreWebView2, in order.
struct WebViewStep {
    enum class Kind { userAgent, script, navigate, html, command };
    Kind kind;
    std::wstring text;
    // An html step's base address (empty: none).
    std::wstring base;
    ActionUIWinUIWebViewCommand command = ActionUIWinUIWebViewGoBack;
    // A script's: run when the document is parsed (else as it is created), in the main frame only.
    bool atDocumentEnd = false;
    bool mainFrameOnly = false;
};

// A script run when a document is parsed (its DOMContentLoaded), as the browser runs a page's own:
// no eval, so a page's security policy does not refuse it.
struct EndScript {
    winrt::hstring source;
    bool mainFrameOnly;
};

// The app's navigation decider of a web view (actionUIWinUIWebViewSetNavigationDecider); its context is
// given back on the UI thread when the decider is let go.
struct NavigationDecider {
    NavigationDecider(ActionUIWinUIWebViewNavigationDecider decide, void *context, ActionUIWinUICallback destroyContext,
                      dispatching::DispatcherQueue queue)
        : decide(decide), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    NavigationDecider(NavigationDecider const &) = delete;
    NavigationDecider &operator=(NavigationDecider const &) = delete;
    ~NavigationDecider() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }
    ActionUIWinUIWebViewNavigationDecider decide;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// A web view's own state, held by the handlers on the view and found by the view's identity.
struct WebViewData {
    winrt::weak_ref<muxc::WebView2> view;
    webcore::CoreWebView2 core{nullptr};
    // True once the steps that waited for the CoreWebView2 have run: later ones run at once.
    bool ready = false;
    bool draining = false;
    std::deque<WebViewStep> pending;
    std::vector<EndScript> endScripts;
    std::string failure;
    bool loading = false;
    double progress = 0;
    std::shared_ptr<EventHandler> changed;
    std::shared_ptr<NavigationDecider> decider;
    // html shown under a base address: the address whose document request is answered with it, once,
    // and the html (UTF-8) as the answer's body.
    winrt::hstring baseDocumentURI;
    winrt::Windows::Storage::Streams::IRandomAccessStream baseDocument{nullptr};
};

// Whether the web view's decider lets it go to `uri` for `kind`; true without a decider. Fails closed:
// false when the web view's state is gone or the question cannot be asked.
bool decides(std::weak_ptr<WebViewData> const &weak, winrt::hstring const &uri, ActionUIWinUIWebViewNavigationKind kind) noexcept {
    try {
        std::shared_ptr<WebViewData> data = weak.lock();
        if (data == nullptr) {
            return false;
        }
        // Held while it runs: a decider that replaces itself must not free its context under it.
        std::shared_ptr<NavigationDecider> decider = data->decider;
        if (decider == nullptr) {
            return true;
        }
        std::string utf8 = winrt::to_string(uri);
        return decider->decide(decider->context, utf8.c_str(), kind);
    } catch (...) {
        return false;
    }
}

std::unordered_map<void *, std::weak_ptr<WebViewData>> &webViews() {
    static auto *views = new std::unordered_map<void *, std::weak_ptr<WebViewData>>();
    return *views;
}

void *identity(muxc::WebView2 const &view) {
    return winrt::get_abi(view.as<wf::IUnknown>());
}

std::shared_ptr<WebViewData> dataOf(ActionUIWinUIObject *object) {
    muxc::WebView2 view = objectAs<muxc::WebView2>(object, L"WebView2");
    auto found = webViews().find(identity(view));
    if (found == webViews().end()) {
        throw winrt::hresult_invalid_argument(L"the web view was not made by actionUIWinUIWebViewCreate");
    }
    std::shared_ptr<WebViewData> data = found->second.lock();
    if (data == nullptr) {
        webViews().erase(found);
        throw winrt::hresult_invalid_argument(L"the web view is gone");
    }
    return data;
}

// A new UTF-8 string the caller frees with actionUIWinUIFreeString.
char *copyString(std::string const &utf8) {
    char *copy = static_cast<char *>(malloc(utf8.size() + 1));
    if (copy == nullptr) {
        throw std::bad_alloc();
    }
    memcpy(copy, utf8.data(), utf8.size());
    copy[utf8.size()] = '\0';
    return copy;
}

void notify(std::shared_ptr<WebViewData> const &data) {
    if (data->changed != nullptr) {
        data->changed->fire();
    }
}

void runCommand(webcore::CoreWebView2 const &core, ActionUIWinUIWebViewCommand command) {
    switch (command) {
    case ActionUIWinUIWebViewGoBack:
        if (core.CanGoBack()) {
            core.GoBack();
        }
        break;
    case ActionUIWinUIWebViewGoForward:
        if (core.CanGoForward()) {
            core.GoForward();
        }
        break;
    case ActionUIWinUIWebViewReload:
        core.Reload();
        break;
    case ActionUIWinUIWebViewStop:
        core.Stop();
        break;
    }
}

// Drops html under a base address whose answer is not yet taken (no longer wanted: another page was
// asked for, or its navigation was refused), so a later document request for the base goes to the
// server rather than getting this html.
void dropBaseDocument(WebViewData &data) {
    if (data.baseDocument == nullptr) {
        return;
    }
    winrt::hstring uri = data.baseDocumentURI;
    data.baseDocument = nullptr;
    data.baseDocumentURI = winrt::hstring();
    data.core.RemoveWebResourceRequestedFilter(uri, webcore::CoreWebView2WebResourceContext::Document);
}

// Runs the steps that waited, in order; a script is added before anything after it runs, so the
// first page gets it.
winrt::fire_and_forget drain(std::shared_ptr<WebViewData> data) {
    if (data->draining) {
        co_return;
    }
    data->draining = true;
    while (!data->pending.empty()) {
        WebViewStep step = data->pending.front();
        data->pending.pop_front();
        try {
            switch (step.kind) {
            case WebViewStep::Kind::userAgent:
                data->core.Settings().UserAgent(step.text);
                break;
            case WebViewStep::Kind::script:
                if (step.atDocumentEnd) {
                    data->endScripts.push_back(EndScript{winrt::hstring(step.text), step.mainFrameOnly});
                } else if (step.mainFrameOnly) {
                    // WebView2 runs a document-created script in every frame.
                    co_await data->core.AddScriptToExecuteOnDocumentCreatedAsync(L"if (window === window.top) {\n" + step.text + L"\n}");
                } else {
                    co_await data->core.AddScriptToExecuteOnDocumentCreatedAsync(step.text);
                }
                break;
            case WebViewStep::Kind::navigate:
                dropBaseDocument(*data);
                data->core.Navigate(step.text);
                break;
            case WebViewStep::Kind::html:
                // An earlier base's answer not yet taken: no longer wanted.
                dropBaseDocument(*data);
                if (step.base.empty()) {
                    data->core.NavigateToString(step.text);
                } else {
                    namespace streams = winrt::Windows::Storage::Streams;
                    streams::InMemoryRandomAccessStream stream;
                    streams::DataWriter writer(stream);
                    writer.UnicodeEncoding(streams::UnicodeEncoding::Utf8);
                    writer.WriteString(step.text);
                    co_await writer.StoreAsync();
                    writer.DetachStream();
                    stream.Seek(0);
                    data->baseDocument = stream;
                    data->baseDocumentURI = winrt::hstring(step.base);
                    data->core.AddWebResourceRequestedFilter(data->baseDocumentURI, webcore::CoreWebView2WebResourceContext::Document);
                    data->core.Navigate(data->baseDocumentURI);
                }
                break;
            case WebViewStep::Kind::command:
                runCommand(data->core, step.command);
                break;
            }
        } catch (winrt::hresult_error const &error) {
            fail("web view step", error);
        } catch (std::exception const &error) {
            // Not out of the coroutine: an exception leaving a fire_and_forget one ends the process.
            fail("web view step", error);
        } catch (...) {
            fail("web view step", "an unknown C++ exception");
        }
    }
    data->draining = false;
    data->ready = true;
}

void enqueue(std::shared_ptr<WebViewData> const &data, WebViewStep step) {
    if (!data->failure.empty() && data->core == nullptr) {
        throw winrt::hresult_error(E_FAIL, winrt::to_hstring("the web view could not start: " + data->failure));
    }
    data->pending.push_back(std::move(step));
    if (data->ready && data->core != nullptr) {
        data->ready = false;
        drain(data);
    }
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIWebViewCreate(void) {
    return guardedObject("web view create", []() {
        // The browser's data (cookies, cache) under the user's local app data, unless the host chose a
        // folder: by default it goes beside the program, which an installed one may not write to.
        wchar_t chosen[2];
        if (GetEnvironmentVariableW(L"WEBVIEW2_USER_DATA_FOLDER", chosen, 2) == 0) {
            wchar_t local[MAX_PATH];
            wchar_t program[MAX_PATH];
            DWORD localLength = GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH);
            DWORD programLength = GetModuleFileNameW(nullptr, program, MAX_PATH);
            if (localLength > 0 && localLength < MAX_PATH && programLength > 0 && programLength < MAX_PATH) {
                std::wstring name(program, programLength);
                size_t slash = name.find_last_of(L"\\/");
                name = slash == std::wstring::npos ? name : name.substr(slash + 1);
                size_t dot = name.find_last_of(L'.');
                name = dot == std::wstring::npos ? name : name.substr(0, dot);
                std::wstring folder = std::wstring(local, localLength) + L"\\" + name + L"\\WebView2";
                SetEnvironmentVariableW(L"WEBVIEW2_USER_DATA_FOLDER", folder.c_str());
            }
        }
        muxc::WebView2 view;
        auto data = std::make_shared<WebViewData>();
        data->view = winrt::make_weak(view);
        webViews()[identity(view)] = data;
        // The handlers hold the data; the data holds the view weakly.
        view.CoreWebView2Initialized([data](muxc::WebView2 const &sender, muxc::CoreWebView2InitializedEventArgs const &args) {
            if (FAILED(args.Exception())) {
                data->failure = winrt::to_string(winrt::hresult_error(args.Exception()).message());
                fail("web view create", "the WebView2 runtime could not start the web view");
                notify(data);
                return;
            }
            webcore::CoreWebView2 core = sender.CoreWebView2();
            data->core = core;
            // The data holds the CoreWebView2, so its handlers hold the data weakly: strongly, they
            // would keep each other alive after the view is gone.
            std::weak_ptr<WebViewData> weak = data;
            // The app decides each navigation, frame navigation, external scheme, new window and download
            // first (actionUIWinUIWebViewSetNavigationDecider): WebView2 would otherwise hand an address
            // of another scheme to the app registered for it, open new windows of its own and save files
            // into the user's Downloads.
            core.NavigationStarting([weak](auto &&, webcore::CoreWebView2NavigationStartingEventArgs const &args) {
                if (!decides(weak, args.Uri(), ActionUIWinUIWebViewNavigationPage)) {
                    args.Cancel(true);
                    // The html's own navigation to its base, refused: its answer is not given later
                    // to another request for that address.
                    std::shared_ptr<WebViewData> held = weak.lock();
                    if (held != nullptr && held->baseDocument != nullptr && args.Uri() == held->baseDocumentURI) {
                        try {
                            dropBaseDocument(*held);
                        } catch (...) {
                            // The filter stays; with no html held, its requests go to the server.
                        }
                    }
                    return;
                }
                if (std::shared_ptr<WebViewData> held = weak.lock()) {
                    held->loading = true;
                    held->progress = 0.1;
                    notify(held);
                }
            });
            core.FrameNavigationStarting([weak](auto &&, webcore::CoreWebView2NavigationStartingEventArgs const &args) {
                if (!decides(weak, args.Uri(), ActionUIWinUIWebViewNavigationFrame)) {
                    args.Cancel(true);
                }
            });
            core.LaunchingExternalUriScheme([weak](auto &&, webcore::CoreWebView2LaunchingExternalUriSchemeEventArgs const &args) {
                if (!decides(weak, args.Uri(), ActionUIWinUIWebViewNavigationExternalScheme)) {
                    args.Cancel(true);
                }
            });
            core.NewWindowRequested([weak](auto &&, webcore::CoreWebView2NewWindowRequestedEventArgs const &args) {
                // Handled with no NewWindow: nothing opens or loads (window.open gets a window object that
                // stays empty).
                if (!decides(weak, args.Uri(), ActionUIWinUIWebViewNavigationNewWindow)) {
                    args.Handled(true);
                }
            });
            core.DownloadStarting([weak](auto &&, webcore::CoreWebView2DownloadStartingEventArgs const &args) {
                if (!decides(weak, args.DownloadOperation().Uri(), ActionUIWinUIWebViewNavigationDownload)) {
                    args.Cancel(true);
                }
            });
            // html under a base address (actionUIWinUIWebViewNavigateToString): its document request is
            // answered with the html, once; the base's later loads (a reload, a link back to it) go to
            // the server.
            core.WebResourceRequested([weak](webcore::CoreWebView2 const &sender, webcore::CoreWebView2WebResourceRequestedEventArgs const &args) {
                std::shared_ptr<WebViewData> held = weak.lock();
                if (held == nullptr || held->baseDocument == nullptr || args.Request().Uri() != held->baseDocumentURI) {
                    return;
                }
                try {
                    args.Response(sender.Environment().CreateWebResourceResponse(held->baseDocument, 200, L"OK",
                                                                                 L"Content-Type: text/html; charset=utf-8"));
                    sender.RemoveWebResourceRequestedFilter(held->baseDocumentURI, webcore::CoreWebView2WebResourceContext::Document);
                } catch (...) {
                    // Left to the server's answer.
                }
                held->baseDocument = nullptr;
                held->baseDocumentURI = winrt::hstring();
            });
            core.NavigationCompleted([weak](auto &&, auto &&) {
                if (std::shared_ptr<WebViewData> held = weak.lock()) {
                    held->loading = false;
                    held->progress = 1;
                    notify(held);
                }
            });
            auto notifyWeak = [weak](auto &&, auto &&) {
                if (std::shared_ptr<WebViewData> held = weak.lock()) {
                    notify(held);
                }
            };
            core.SourceChanged(notifyWeak);
            core.DocumentTitleChanged(notifyWeak);
            core.HistoryChanged(notifyWeak);
            // The documentEnd scripts, in the main frame and in each frame of it.
            core.DOMContentLoaded([weak](webcore::CoreWebView2 const &sender, auto &&) {
                if (std::shared_ptr<WebViewData> held = weak.lock()) {
                    for (EndScript const &script : held->endScripts) {
                        sender.ExecuteScriptAsync(script.source);
                    }
                }
            });
            core.FrameCreated([weak](auto &&, webcore::CoreWebView2FrameCreatedEventArgs const &args) {
                args.Frame().DOMContentLoaded([weak](webcore::CoreWebView2Frame const &frame, auto &&) {
                    if (std::shared_ptr<WebViewData> held = weak.lock()) {
                        for (EndScript const &script : held->endScripts) {
                            if (!script.mainFrameOnly) {
                                frame.ExecuteScriptAsync(script.source);
                            }
                        }
                    }
                });
            });
            drain(data);
        });
        // Started now; what is asked before it completes waits (WebViewData::pending). Its own end is
        // watched too: a start that fails may not raise CoreWebView2Initialized.
        std::weak_ptr<WebViewData> weak = data;
        view.EnsureCoreWebView2Async().Completed([weak](wf::IAsyncAction const &operation, wf::AsyncStatus status) {
            std::shared_ptr<WebViewData> held = weak.lock();
            if (held == nullptr || status == wf::AsyncStatus::Completed || held->core != nullptr) {
                return;
            }
            if (held->failure.empty()) {
                held->failure = status == wf::AsyncStatus::Error ? winrt::to_string(winrt::hresult_error(operation.ErrorCode()).message())
                                                                 : std::string("the start was canceled");
                if (held->failure.empty()) {
                    held->failure = "the start failed";
                }
            }
            notify(held);
        });
        return toObject(view);
    });
}

bool actionUIWinUIWebViewSetUserAgent(ActionUIWinUIObject *webView, const char *userAgent) {
    return guarded("web view set user agent", [&]() {
        enqueue(dataOf(webView), WebViewStep{WebViewStep::Kind::userAgent, std::wstring(toHString(userAgent))});
        return true;
    });
}

bool actionUIWinUIWebViewAddScript(ActionUIWinUIObject *webView, const char *source, bool atDocumentEnd, bool mainFrameOnly) {
    return guarded("web view add script", [&]() {
        WebViewStep step{WebViewStep::Kind::script, std::wstring(toHString(source))};
        step.atDocumentEnd = atDocumentEnd;
        step.mainFrameOnly = mainFrameOnly;
        enqueue(dataOf(webView), step);
        return true;
    });
}

bool actionUIWinUIWebViewNavigate(ActionUIWinUIObject *webView, const char *url) {
    return guarded("web view navigate", [&]() {
        enqueue(dataOf(webView), WebViewStep{WebViewStep::Kind::navigate, std::wstring(toHString(url))});
        return true;
    });
}

bool actionUIWinUIWebViewNavigateToString(ActionUIWinUIObject *webView, const char *html, const char *baseURL) {
    return guarded("web view navigate to string", [&]() {
        WebViewStep step{WebViewStep::Kind::html, std::wstring(toHString(html))};
        if (baseURL != nullptr) {
            wf::Uri base{nullptr};
            try {
                base = wf::Uri(toHString(baseURL));
            } catch (winrt::hresult_error const &) {
                return fail("web view navigate to string", "the base URL is not an absolute URL");
            }
            std::wstring scheme(base.SchemeName());
            for (wchar_t &character : scheme) {
                character = towlower(character);
            }
            if (scheme != L"http" && scheme != L"https") {
                return fail("web view navigate to string", "only an http or https base URL is used");
            }
            // The address the document request carries: no fragment (it never reaches a request).
            std::wstring address(base.AbsoluteUri());
            size_t fragment = address.find(L'#');
            step.base = fragment == std::wstring::npos ? address : address.substr(0, fragment);
        }
        enqueue(dataOf(webView), step);
        return true;
    });
}

bool actionUIWinUIWebViewRun(ActionUIWinUIObject *webView, ActionUIWinUIWebViewCommand command) {
    return guarded("web view run", [&]() {
        WebViewStep step{WebViewStep::Kind::command, std::wstring()};
        step.command = command;
        enqueue(dataOf(webView), step);
        return true;
    });
}

bool actionUIWinUIWebViewGetState(ActionUIWinUIObject *webView, ActionUIWinUIWebViewState *state) {
    return guarded("web view get state", [&]() {
        if (state == nullptr) {
            return fail("web view get state", "no state to write to");
        }
        std::shared_ptr<WebViewData> data = dataOf(webView);
        if (data->core == nullptr && !data->failure.empty()) {
            return fail("web view get state", ("the web view could not start: " + data->failure).c_str());
        }
        *state = ActionUIWinUIWebViewState{data->loading, data->progress, false, false};
        if (data->core != nullptr) {
            state->canGoBack = data->core.CanGoBack();
            state->canGoForward = data->core.CanGoForward();
        }
        return true;
    });
}

char *actionUIWinUIWebViewCopyURL(ActionUIWinUIObject *webView) {
    char *copy = nullptr;
    guarded("web view copy URL", [&]() {
        std::shared_ptr<WebViewData> data = dataOf(webView);
        copy = copyString(data->core != nullptr ? winrt::to_string(data->core.Source()) : std::string());
        return true;
    });
    return copy;
}

char *actionUIWinUIWebViewCopyStatus(ActionUIWinUIObject *webView) {
    char *copy = nullptr;
    guarded("web view copy status", [&]() {
        std::shared_ptr<WebViewData> data = dataOf(webView);
        copy = copyString(data->core != nullptr ? std::string("started")
                          : data->failure.empty() ? std::string("starting") : "failed: " + data->failure);
        return true;
    });
    return copy;
}

char *actionUIWinUIWebViewCopyTitle(ActionUIWinUIObject *webView) {
    char *copy = nullptr;
    guarded("web view copy title", [&]() {
        std::shared_ptr<WebViewData> data = dataOf(webView);
        copy = copyString(data->core != nullptr ? winrt::to_string(data->core.DocumentTitle()) : std::string());
        return true;
    });
    return copy;
}

bool actionUIWinUIWebViewSetNavigationDecider(ActionUIWinUIObject *webView, ActionUIWinUIWebViewNavigationDecider decide,
                                             void *context, ActionUIWinUICallback destroyContext) {
    std::shared_ptr<NavigationDecider> decider;
    bool set = guarded("web view set navigation decider", [&]() {
        if (decide == nullptr) {
            return fail("web view set navigation decider", "the decider is NULL");
        }
        std::shared_ptr<WebViewData> data = dataOf(webView);
        decider = std::make_shared<NavigationDecider>(decide, context, destroyContext, currentQueue());
        data->decider = decider;
        return true;
    });
    // Not made: the context is given back here (once made, the decider gives it back).
    if (!set && decider == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return set;
}

bool actionUIWinUIWebViewOnChanged(ActionUIWinUIObject *webView, ActionUIWinUICallback handler, void *context,
                                   ActionUIWinUICallback destroyContext) {
    return registerHandler("web view on changed", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        dataOf(webView)->changed = holder;
    });
}

} // extern "C"

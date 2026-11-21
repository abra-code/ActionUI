// Network.cpp - fetching a URL's contents (a LoadableView's remote description) with Windows' HTTP
// client, without blocking the UI thread.

#include "ShimInternal.h"

#include <string>

#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Web.Http.h>

namespace actionui_winui {

namespace {

namespace http = winrt::Windows::Web::Http;
namespace streams = winrt::Windows::Storage::Streams;

// Fetches `uri` and calls `completion` on the UI thread (the coroutine resumes in the caller's
// apartment after each wait): the bytes, or NULL and why not.
winrt::fire_and_forget fetch(wf::Uri uri, ActionUIWinUIDataCompletion completion, void *context) {
    std::string error;
    streams::IBuffer body{nullptr};
    const uint8_t *bytes = nullptr;
    uint32_t length = 0;
    bool received = false;
    try {
        http::HttpClient client;
        http::HttpResponseMessage response = co_await client.GetAsync(uri);
        if (!response.IsSuccessStatusCode()) {
            error = "the server answered " + std::to_string(static_cast<int32_t>(response.StatusCode())) + " " +
                    winrt::to_string(response.ReasonPhrase());
        } else {
            body = co_await response.Content().ReadAsBufferAsync();
            // Inside the try: data() and Length() can throw, and an exception leaving a
            // fire_and_forget coroutine ends the process.
            bytes = body.data();
            length = body.Length();
            received = true;
        }
    } catch (winrt::hresult_error const &failure) {
        error = winrt::to_string(failure.message());
        if (error.empty()) {
            error = "the request failed";
        }
    } catch (std::exception const &failure) {
        error = failure.what();
        if (error.empty()) {
            error = "the request failed";
        }
    } catch (...) {
        error = "an unknown C++ exception";
    }
    if (received) {
        // An empty body is a success too: never NULL, which the caller takes for a failure.
        static const uint8_t empty = 0;
        completion(context, bytes != nullptr ? bytes : &empty, length, nullptr);
    } else {
        completion(context, nullptr, 0, error.c_str());
    }
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

bool actionUIWinUIFetchURL(const char *url, ActionUIWinUIDataCompletion completion, void *context) {
    return guarded("fetch URL", [&]() {
        if (completion == nullptr) {
            return fail("fetch URL", "no completion to call");
        }
        wf::Uri uri{nullptr};
        try {
            uri = wf::Uri(toHString(url));
        } catch (winrt::hresult_error const &) {
            return fail("fetch URL", "the URL is not an absolute URL");
        }
        winrt::hstring scheme = uri.SchemeName();
        if (scheme != L"http" && scheme != L"https") {
            return fail("fetch URL", "only http and https URLs are fetched");
        }
        dispatching::DispatcherQueue queue = dispatching::DispatcherQueue::GetForCurrentThread();
        if (queue == nullptr) {
            return fail("fetch URL", "not on the UI thread (no DispatcherQueue)");
        }
        // Started from the queue, so the completion always comes after this function returns.
        bool queued = queue.TryEnqueue([uri, completion, context]() {
            fetch(uri, completion, context);
        });
        if (!queued) {
            return fail("fetch URL", "the UI thread's queue refused the call (shutting down?)");
        }
        return true;
    });
}

} // extern "C"

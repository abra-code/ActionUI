// Network.cpp - fetching a URL's contents (a LoadableView's remote description) with Windows' HTTP
// client, without blocking the UI thread, within a size and a time limit, following redirects itself.

#include "ShimInternal.h"

#include <chrono>
#include <cwctype>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Filters.h>
#include <winrt/Windows.Web.Http.Headers.h>

namespace actionui_winui {

namespace {

namespace http = winrt::Windows::Web::Http;
namespace streams = winrt::Windows::Storage::Streams;

// The most redirects a fetch follows.
constexpr int maximumRedirects = 20;

// A fetch's time limit: the timer cancels the step under way once it is reached.
struct Deadline {
    dispatching::DispatcherQueueTimer timer{nullptr};
    wf::IAsyncInfo current{nullptr};
    bool expired = false;
};

// Whether `status` is a redirect the fetch follows (its Location).
bool isRedirect(int32_t status) {
    return status == 301 || status == 302 || status == 303 || status == 307 || status == 308;
}

// Fetches `uri` and calls `completion` on the UI thread (the coroutine resumes in the caller's
// apartment after each wait): the bytes, or NULL and why not. Redirects are followed here, their
// bodies unread (HttpBaseProtocolFilter would read them, outside the size limit); the body is read in
// pieces and refused past `maximumBytes`; every step is canceled once `timeout` has passed.
winrt::fire_and_forget fetch(wf::Uri uri, int64_t maximumBytes, std::chrono::milliseconds timeout,
                             ActionUIWinUIDataCompletion completion, void *context) {
    std::string error;
    std::vector<uint8_t> body;
    std::string finalURL;
    bool redirected = false;
    bool received = false;
    auto deadline = std::make_shared<Deadline>();
    const std::string limitText = maximumBytes % (1024 * 1024) == 0 ? std::to_string(maximumBytes / (1024 * 1024)) + " MB"
                                                                   : std::to_string(maximumBytes) + " bytes";
    try {
        deadline->timer = dispatching::DispatcherQueue::GetForCurrentThread().CreateTimer();
        deadline->timer.Interval(timeout);
        deadline->timer.IsRepeating(false);
        std::weak_ptr<Deadline> weak = deadline;
        deadline->timer.Tick([weak](auto &&, auto &&) {
            if (std::shared_ptr<Deadline> held = weak.lock()) {
                held->expired = true;
                // A reference of its own: the canceled step may resume the coroutine inside Cancel, which
                // lets go of `current`.
                wf::IAsyncInfo step = held->current;
                if (step != nullptr) {
                    try {
                        step.Cancel();
                    } catch (...) {
                    }
                }
            }
        });
        deadline->timer.Start();
        http::Filters::HttpBaseProtocolFilter filter;
        filter.AllowAutoRedirect(false);
        // No credential dialog for a server that answers 401: the user is not asked for a password on a
        // LoadableView's behalf (the answer is a failure, as URLSession gives without a delegate).
        filter.AllowUI(false);
        http::HttpClient client(filter);
        wf::Uri current = uri;
        http::HttpResponseMessage response{nullptr};
        for (int redirects = 0;; ++redirects) {
            http::HttpRequestMessage request(http::HttpMethod::Get(), current);
            auto sending = client.SendRequestAsync(request, http::HttpCompletionOption::ResponseHeadersRead);
            deadline->current = sending;
            response = co_await sending;
            // The timer fires once: a step that finished just before it is not canceled, so the next would
            // run unbounded.
            if (deadline->expired) {
                throw winrt::hresult_canceled();
            }
            int32_t status = static_cast<int32_t>(response.StatusCode());
            if (!isRedirect(status)) {
                break;
            }
            winrt::hstring location;
            if (auto found = response.Headers().TryLookup(L"Location")) {
                location = *found;
            }
            // The redirect's body is dropped unread.
            response.Close();
            if (location.empty()) {
                throw std::runtime_error("the server answered " + std::to_string(status) + " without a Location");
            }
            if (redirects + 1 > maximumRedirects) {
                throw std::runtime_error("more than " + std::to_string(maximumRedirects) + " redirects");
            }
            wf::Uri next = current.CombineUri(location);
            std::wstring scheme(next.SchemeName());
            for (wchar_t &character : scheme) {
                character = towlower(character);
            }
            if (scheme != L"http" && scheme != L"https") {
                throw std::runtime_error("a redirect to " + winrt::to_string(next.AbsoluteUri()) + " (only http and https are followed)");
            }
            std::wstring from(current.SchemeName());
            for (wchar_t &character : from) {
                character = towlower(character);
            }
            if (from == L"https" && scheme == L"http") {
                throw std::runtime_error("a redirect from https to http (" + winrt::to_string(next.AbsoluteUri()) + ")");
            }
            current = next;
            redirected = true;
        }
        if (!response.IsSuccessStatusCode()) {
            error = "the server answered " + std::to_string(static_cast<int32_t>(response.StatusCode()));
            // HTTP/2 answers carry no reason phrase.
            std::string reason = winrt::to_string(response.ReasonPhrase());
            if (!reason.empty()) {
                error += " " + reason;
            }
        } else {
            // Refused at once when the server says how long the body is.
            if (auto length = response.Content().Headers().ContentLength()) {
                if (length.Value() > static_cast<uint64_t>(maximumBytes)) {
                    throw std::runtime_error("the response is larger than " + limitText);
                }
            }
            auto opening = response.Content().ReadAsInputStreamAsync();
            deadline->current = opening;
            streams::IInputStream stream = co_await opening;
            if (deadline->expired) {
                throw winrt::hresult_canceled();
            }
            streams::Buffer buffer(64 * 1024);
            while (true) {
                auto reading = stream.ReadAsync(buffer, buffer.Capacity(), streams::InputStreamOptions::Partial);
                deadline->current = reading;
                streams::IBuffer piece = co_await reading;
                if (deadline->expired) {
                    throw winrt::hresult_canceled();
                }
                uint32_t count = piece.Length();
                if (count == 0) {
                    break;
                }
                if (static_cast<int64_t>(body.size()) + count > maximumBytes) {
                    throw std::runtime_error("the response is larger than " + limitText);
                }
                body.insert(body.end(), piece.data(), piece.data() + count);
            }
            if (redirected) {
                finalURL = winrt::to_string(current.AbsoluteUri());
            }
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
    if (deadline->expired) {
        received = false;
        error = "loading it took longer than " + std::to_string(timeout.count() / 1000) + " seconds";
    }
    try {
        if (deadline->timer != nullptr) {
            deadline->timer.Stop();
        }
    } catch (...) {
    }
    deadline->current = nullptr;
    if (received) {
        // An empty body is a success too: never NULL, which the caller takes for a failure.
        static const uint8_t empty = 0;
        completion(context, body.empty() ? &empty : body.data(), body.size(), redirected ? finalURL.c_str() : nullptr, nullptr);
    } else {
        completion(context, nullptr, 0, nullptr, error.c_str());
    }
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

bool actionUIWinUIFetchURL(const char *url, int64_t maximumBytes, double timeoutSeconds, ActionUIWinUIDataCompletion completion,
                          void *context) {
    return guarded("fetch URL", [&]() {
        if (completion == nullptr) {
            return fail("fetch URL", "no completion to call");
        }
        if (maximumBytes <= 0 || !(timeoutSeconds > 0)) {
            return fail("fetch URL", "the size and time limits must be positive");
        }
        auto timeout = std::chrono::milliseconds(static_cast<int64_t>(timeoutSeconds * 1000));
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
        bool queued = queue.TryEnqueue([uri, maximumBytes, timeout, completion, context]() {
            fetch(uri, maximumBytes, timeout, completion, context);
        });
        if (!queued) {
            return fail("fetch URL", "the UI thread's queue refused the call (shutting down?)");
        }
        return true;
    });
}

} // extern "C"

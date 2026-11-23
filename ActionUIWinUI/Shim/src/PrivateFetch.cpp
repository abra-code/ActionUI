// PrivateFetch.cpp - fetching a URL's contents for content the app does not trust (a LoadableView's
// remote description in ActionUI JSON from a server) with WinHTTP, carrying nothing of the user's or the
// app's: no cookies (none sent, none kept), no Windows sign-in (Negotiate, NTLM, Kerberos) and no
// credential dialog, no cache shared with other programs. The same limits and redirect rules as
// Network.cpp's fetch: within a size and a time limit, redirects followed here.

#include "ShimInternal.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <chrono>
#include <cwctype>
#include <memory>
#include <stdexcept>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

#pragma comment(lib, "winhttp.lib")

namespace actionui_winui {

namespace {

// The most redirects a fetch follows.
constexpr int maximumRedirects = 20;

using Clock = std::chrono::steady_clock;

// The fetch's handles, used only by its worker thread. The time limit is kept by giving each blocking
// call the time that is left (at most 30 seconds, a limit on any one pause) as its WinHTTP timeouts, so
// no other thread ever closes a handle under it; the caller hears at the deadline at the latest
// (Delivery).
struct PrivateFetchState {
    HINTERNET session = nullptr;
    HINTERNET connection = nullptr;
    HINTERNET request = nullptr;
    Clock::time_point deadline;
    // Whether the current step was given less than the time left (a step's 30-second cap), so that
    // its WinHTTP timeout is not the fetch's time limit.
    bool stepCapped = false;

    void closeRequest() {
        if (request != nullptr) {
            WinHttpCloseHandle(request);
            request = nullptr;
        }
        if (connection != nullptr) {
            WinHttpCloseHandle(connection);
            connection = nullptr;
        }
    }

    ~PrivateFetchState() {
        closeRequest();
        if (session != nullptr) {
            WinHttpCloseHandle(session);
        }
    }
};

// Thrown when the time limit is reached.
struct Expired {};

// The caller's side, on the UI thread only: the completion is called once, with the worker's outcome or,
// at the deadline, with the time limit's failure (the worker's late outcome is then dropped). The timer
// never touches the worker's handles.
struct Delivery {
    bool delivered = false;
    dispatching::DispatcherQueueTimer timer{nullptr};
    ActionUIWinUIDataCompletion completion = nullptr;
    void *context = nullptr;
};

// Gives the request's next blocking call the time that is left (Expired when none is).
void limitNextStep(PrivateFetchState &state) {
    auto left = std::chrono::duration_cast<std::chrono::milliseconds>(state.deadline - Clock::now()).count();
    if (left <= 0) {
        throw Expired();
    }
    state.stepCapped = left > 30000;
    int milliseconds = static_cast<int>(std::min<long long>(left, 30000));
    WinHttpSetTimeouts(state.request, milliseconds, milliseconds, milliseconds, milliseconds);
    // The receive timeout covers one read from the connection; this one covers all of the response's
    // headers, which a server could otherwise send a byte at a time (its default is 90 seconds).
    DWORD headers = static_cast<DWORD>(milliseconds);
    WinHttpSetOption(state.request, WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT, &headers, sizeof(headers));
}

std::wstring lowercased(std::wstring text) {
    for (wchar_t &character : text) {
        character = towlower(character);
    }
    return text;
}

// The system's text for a WinHTTP or Windows error.
std::string errorText(DWORD code) {
    wchar_t *text = nullptr;
    DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_FROM_SYSTEM;
    HMODULE winhttp = GetModuleHandleW(L"winhttp.dll");
    if (code >= 12000 && code <= 12999 && winhttp != nullptr) {
        flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_FROM_HMODULE;
    }
    DWORD length = FormatMessageW(flags, winhttp, code, 0, reinterpret_cast<wchar_t *>(&text), 0, nullptr);
    std::string message;
    if (length > 0 && text != nullptr) {
        message = winrt::to_string(std::wstring_view(text, length));
        while (!message.empty() && (message.back() == '\n' || message.back() == '\r' || message.back() == ' ' || message.back() == '.')) {
            message.pop_back();
        }
    }
    if (text != nullptr) {
        LocalFree(text);
    }
    if (message.empty()) {
        message = "error " + std::to_string(code);
    }
    return message;
}

// Fails with the last error, or as Expired when it was the time limit.
[[noreturn]] void failStep(PrivateFetchState &state, const char *step) {
    DWORD code = GetLastError();
    if ((code == ERROR_WINHTTP_TIMEOUT && !state.stepCapped) || Clock::now() >= state.deadline) {
        throw Expired();
    }
    throw std::runtime_error(std::string(step) + ": " + errorText(code));
}

DWORD statusCode(PrivateFetchState &state) {
    DWORD status = 0;
    DWORD size = sizeof(status);
    if (!WinHttpQueryHeaders(state.request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX)) {
        failStep(state, "reading the status");
    }
    return status;
}

// A header's text, or an empty string when the response has none.
std::wstring headerText(PrivateFetchState &state, DWORD query) {
    HINTERNET request = state.request;
    DWORD size = 0;
    WinHttpQueryHeaders(request, query, WINHTTP_HEADER_NAME_BY_INDEX, WINHTTP_NO_OUTPUT_BUFFER, &size, WINHTTP_NO_HEADER_INDEX);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0) {
        return std::wstring();
    }
    std::wstring text(size / sizeof(wchar_t) + 1, L'\0');
    if (!WinHttpQueryHeaders(request, query, WINHTTP_HEADER_NAME_BY_INDEX, text.data(), &size, WINHTTP_NO_HEADER_INDEX)) {
        return std::wstring();
    }
    text.resize(size / sizeof(wchar_t));
    return text;
}

// Opens the request for `uri` on a new connection: GET, nothing of the user's attached, then sends it.
void sendRequest(PrivateFetchState &state, wf::Uri const &uri) {
    std::wstring scheme = lowercased(std::wstring(uri.SchemeName()));
    bool secure = scheme == L"https";
    std::wstring host(uri.Host());
    if (host.empty()) {
        throw std::runtime_error("the address has no host");
    }
    // An IPv6 address keeps its brackets in Uri.Host only in some forms; WinHttpConnect wants none.
    if (host.size() > 2 && host.front() == L'[' && host.back() == L']') {
        host = host.substr(1, host.size() - 2);
    }
    INTERNET_PORT port = static_cast<INTERNET_PORT>(uri.Port());
    // The path and query as the address spells them (escaped), never the fragment.
    std::wstring target(uri.Path());
    if (target.empty()) {
        target = L"/";
    }
    target += std::wstring(uri.Query());
    state.closeRequest();
    state.connection = WinHttpConnect(state.session, host.c_str(), port, 0);
    if (state.connection == nullptr) {
        throw std::runtime_error("connecting: " + errorText(GetLastError()));
    }
    state.request = WinHttpOpenRequest(state.connection, L"GET", target.c_str(), nullptr, WINHTTP_NO_REFERER,
                                       WINHTTP_DEFAULT_ACCEPT_TYPES, secure ? WINHTTP_FLAG_SECURE : 0);
    if (state.request == nullptr) {
        throw std::runtime_error("opening the request: " + errorText(GetLastError()));
    }
    // No sign-in of any kind answered, no cookie sent or kept, no redirect followed by WinHTTP (here,
    // with the rules below). Authentication off covers what the logon level does not: Windows does
    // not apply the HIGH level to localhost or to an address by number.
    DWORD features = WINHTTP_DISABLE_AUTHENTICATION | WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_REDIRECTS;
    if (!WinHttpSetOption(state.request, WINHTTP_OPTION_DISABLE_FEATURE, &features, sizeof(features))) {
        throw std::runtime_error("turning off sign-in and cookies: " + errorText(GetLastError()));
    }
    DWORD logon = WINHTTP_AUTOLOGON_SECURITY_LEVEL_HIGH;
    if (!WinHttpSetOption(state.request, WINHTTP_OPTION_AUTOLOGON_POLICY, &logon, sizeof(logon))) {
        throw std::runtime_error("turning off automatic sign-in: " + errorText(GetLastError()));
    }
    limitNextStep(state);
    bool sent = WinHttpSendRequest(state.request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
                WinHttpReceiveResponse(state.request, nullptr);
    if (!sent && GetLastError() == ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED) {
        // A server that asks for a client certificate gets none (never one of the user's), once more.
        if (!WinHttpSetOption(state.request, WINHTTP_OPTION_CLIENT_CERT_CONTEXT, WINHTTP_NO_CLIENT_CERT_CONTEXT, 0)) {
            failStep(state, "declining the client certificate");
        }
        limitNextStep(state);
        sent = WinHttpSendRequest(state.request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
               WinHttpReceiveResponse(state.request, nullptr);
    }
    if (!sent) {
        failStep(state, "sending the request");
    }
}

// Whether `status` is a redirect the fetch follows (its Location).
bool isRedirect(DWORD status) {
    return status == 301 || status == 302 || status == 303 || status == 307 || status == 308;
}

struct Outcome {
    bool received = false;
    std::vector<uint8_t> body;
    std::string finalURL;
    std::string error;
};

// The worker's part: every step blocks, off the UI thread.
Outcome run(PrivateFetchState &state, wf::Uri uri, int64_t maximumBytes) {
    Outcome outcome;
    const std::string limitText = maximumBytes % (1024 * 1024) == 0 ? std::to_string(maximumBytes / (1024 * 1024)) + " MB"
                                                                   : std::to_string(maximumBytes) + " bytes";
    wf::Uri current = uri;
    bool redirected = false;
    DWORD status = 0;
    for (int redirects = 0;; ++redirects) {
        sendRequest(state, current);
        status = statusCode(state);
        if (!isRedirect(status)) {
            break;
        }
        std::wstring location = headerText(state, WINHTTP_QUERY_LOCATION);
        if (location.empty()) {
            throw std::runtime_error("the server answered " + std::to_string(status) + " without a Location");
        }
        if (redirects + 1 > maximumRedirects) {
            throw std::runtime_error("more than " + std::to_string(maximumRedirects) + " redirects");
        }
        wf::Uri next = current.CombineUri(winrt::hstring(location));
        std::wstring scheme = lowercased(std::wstring(next.SchemeName()));
        if (scheme != L"http" && scheme != L"https") {
            throw std::runtime_error("a redirect to " + winrt::to_string(next.AbsoluteUri()) + " (only http and https are followed)");
        }
        if (lowercased(std::wstring(current.SchemeName())) == L"https" && scheme == L"http") {
            throw std::runtime_error("a redirect from https to http (" + winrt::to_string(next.AbsoluteUri()) + ")");
        }
        current = next;
        redirected = true;
    }
    if (status == 401) {
        outcome.error = "the server asks for a sign-in (401), which is not answered for this content";
        return outcome;
    }
    if (status == 407) {
        outcome.error = "the proxy asks for a sign-in (407), which is not answered for this content";
        return outcome;
    }
    if (status < 200 || status > 299) {
        outcome.error = "the server answered " + std::to_string(status);
        std::string reason = winrt::to_string(headerText(state, WINHTTP_QUERY_STATUS_TEXT));
        if (!reason.empty()) {
            outcome.error += " " + reason;
        }
        return outcome;
    }
    // Refused at once when the server says how long the body is.
    std::wstring length = headerText(state, WINHTTP_QUERY_CONTENT_LENGTH);
    if (!length.empty()) {
        bool digits = true;
        for (wchar_t character : length) {
            digits = digits && character >= L'0' && character <= L'9';
        }
        if (!digits || length.size() > 18 || std::stoll(length) > maximumBytes) {
            throw std::runtime_error("the response is larger than " + limitText);
        }
    }
    std::vector<uint8_t> buffer(64 * 1024);
    while (true) {
        // What has arrived, then that much: a read never waits to fill its buffer.
        DWORD available = 0;
        limitNextStep(state);
        if (!WinHttpQueryDataAvailable(state.request, &available)) {
            failStep(state, "reading the response");
        }
        if (available == 0) {
            break;
        }
        DWORD count = 0;
        DWORD wanted = std::min<DWORD>(available, static_cast<DWORD>(buffer.size()));
        if (!WinHttpReadData(state.request, buffer.data(), wanted, &count)) {
            failStep(state, "reading the response");
        }
        if (count == 0) {
            break;
        }
        if (static_cast<int64_t>(outcome.body.size()) + count > maximumBytes) {
            throw std::runtime_error("the response is larger than " + limitText);
        }
        outcome.body.insert(outcome.body.end(), buffer.data(), buffer.data() + count);
    }
    if (redirected) {
        outcome.finalURL = winrt::to_string(current.AbsoluteUri());
    }
    outcome.received = true;
    return outcome;
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

bool actionUIWinUIFetchURLPrivately(const char *url, int64_t maximumBytes, double timeoutSeconds,
                                   ActionUIWinUIDataCompletion completion, void *context) {
    return guarded("fetch URL privately", [&]() {
        if (completion == nullptr) {
            return fail("fetch URL privately", "no completion to call");
        }
        if (maximumBytes <= 0 || !(timeoutSeconds > 0) || !(timeoutSeconds <= 24 * 60 * 60)) {
            return fail("fetch URL privately", "the size limit must be positive, the time limit between 0 and a day");
        }
        auto timeout = std::chrono::milliseconds(static_cast<int64_t>(timeoutSeconds * 1000));
        wf::Uri uri{nullptr};
        try {
            uri = wf::Uri(toHString(url));
        } catch (winrt::hresult_error const &) {
            return fail("fetch URL privately", "the URL is not an absolute URL");
        }
        std::wstring scheme = lowercased(std::wstring(uri.SchemeName()));
        if (scheme != L"http" && scheme != L"https") {
            return fail("fetch URL privately", "only http and https URLs are fetched");
        }
        dispatching::DispatcherQueue queue = dispatching::DispatcherQueue::GetForCurrentThread();
        if (queue == nullptr) {
            return fail("fetch URL privately", "not on the UI thread (no DispatcherQueue)");
        }
        auto state = std::make_shared<PrivateFetchState>();
        state->deadline = Clock::now() + timeout;
        // The system's proxy settings (a proxy that asks for a sign-in is not answered: a failure).
        state->session = WinHttpOpen(L"ActionUI", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                                     WINHTTP_NO_PROXY_BYPASS, 0);
        if (state->session == nullptr) {
            return fail("fetch URL privately", errorText(GetLastError()).c_str());
        }
        int64_t timeoutSecondsWhole = timeout.count() / 1000;
        std::string lateText = "loading it took longer than " + std::to_string(timeoutSecondsWhole) + " seconds";
        auto delivery = std::make_shared<Delivery>();
        delivery->completion = completion;
        delivery->context = context;
        // A little after the deadline, so a worker that ends right at it still reports its own outcome.
        delivery->timer = queue.CreateTimer();
        delivery->timer.Interval(timeout + std::chrono::milliseconds(500));
        delivery->timer.IsRepeating(false);
        std::weak_ptr<Delivery> weak = delivery;
        delivery->timer.Tick([weak, lateText](auto &&, auto &&) {
            std::shared_ptr<Delivery> held = weak.lock();
            if (held == nullptr || held->delivered) {
                return;
            }
            held->delivered = true;
            held->completion(held->context, nullptr, 0, nullptr, lateText.c_str());
        });
        delivery->timer.Start();
        try {
            std::thread([state, uri, maximumBytes, lateText, delivery, queue]() mutable {
                // The worker's own apartment, for the WinRT Uri it reads.
                bool apartment = false;
                try {
                    winrt::init_apartment(winrt::apartment_type::multi_threaded);
                    apartment = true;
                } catch (...) {
                }
                Outcome outcome;
                bool expired = false;
                try {
                    outcome = run(*state, uri, maximumBytes);
                } catch (Expired const &) {
                    expired = true;
                } catch (winrt::hresult_error const &failure) {
                    outcome.error = winrt::to_string(failure.message());
                } catch (std::exception const &failure) {
                    outcome.error = failure.what();
                } catch (...) {
                    outcome.error = "an unknown C++ exception";
                }
                state->closeRequest();
                if (expired) {
                    outcome.received = false;
                    outcome.error = lateText;
                }
                if (!outcome.received && outcome.error.empty()) {
                    outcome.error = "the request failed";
                }
                // A queue that is shutting down runs nothing more: the completion is not called, as for a
                // fetch still under way when the application ends. Nothing may throw out of the thread's
                // function (that ends the process).
                try {
                    auto shared = std::make_shared<Outcome>(std::move(outcome));
                    queue.TryEnqueue([shared, delivery]() {
                        try {
                            delivery->timer.Stop();
                            delivery->timer = nullptr;
                        } catch (...) {
                        }
                        if (delivery->delivered) {
                            return;
                        }
                        delivery->delivered = true;
                        if (shared->received) {
                            // An empty body is a success too: never NULL, which the caller takes for a failure.
                            static const uint8_t empty = 0;
                            delivery->completion(delivery->context, shared->body.empty() ? &empty : shared->body.data(),
                                                 shared->body.size(), shared->finalURL.empty() ? nullptr : shared->finalURL.c_str(),
                                                 nullptr);
                        } else {
                            delivery->completion(delivery->context, nullptr, 0, nullptr, shared->error.c_str());
                        }
                    });
                } catch (...) {
                }
                // The thread's WinRT references let go inside its apartment, before it is left.
                delivery = nullptr;
                queue = nullptr;
                uri = nullptr;
                state = nullptr;
                if (apartment) {
                    winrt::uninit_apartment();
                }
            }).detach();
        } catch (std::system_error const &failure) {
            delivery->timer.Stop();
            return fail("fetch URL privately", failure);
        }
        return true;
    });
}

} // extern "C"

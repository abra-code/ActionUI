// Images.cpp - WinUI's Image control for ActionUI's Image with a file and AsyncImage with a URL: a
// bitmap or an SVG image, at its own size or scaled to fit or cover the size it is arranged in.

#include "ShimInternal.h"

#include <memory>
#include <string>
#include <vector>

#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;

using namespace actionui_winui;

namespace {

// `path` as an absolute file URI ("file:///C:/folder/name.png", "file://server/share/name.png"), spaces
// and other characters escaped by Uri itself. "%" and "#" are escaped here: Uri would read "%20" in a
// name as an escaped space and "#" as the start of a fragment, loading another file.
wf::Uri fileUri(std::wstring const &path) {
    DWORD needed = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (needed == 0) {
        throw winrt::hresult_invalid_argument(L"the image path cannot be made absolute");
    }
    std::vector<wchar_t> full(needed);
    DWORD written = GetFullPathNameW(path.c_str(), needed, full.data(), nullptr);
    if (written == 0 || written >= needed) {
        throw winrt::hresult_invalid_argument(L"the image path cannot be made absolute");
    }
    std::wstring text;
    text.reserve(written);
    for (wchar_t character : std::wstring_view(full.data(), written)) {
        if (character == L'\\') {
            text += L'/';
        } else if (character == L'%') {
            text += L"%25";
        } else if (character == L'#') {
            text += L"%23";
        } else {
            text += character;
        }
    }
    // A UNC path ("//server/share/...") has its server as the URI's host.
    bool unc = text.size() >= 2 && text[0] == L'/' && text[1] == L'/';
    return wf::Uri((unc ? L"file:" : L"file:///") + text);
}

bool isSVG(std::wstring const &path) {
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos) {
        return false;
    }
    std::wstring extension = path.substr(dot + 1);
    for (wchar_t &character : extension) {
        character = static_cast<wchar_t>(towlower(character));
    }
    return extension == L"svg";
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIImageCreate(void) {
    return guardedObject("image create", []() {
        muxc::Image image;
        image.Stretch(media::Stretch::None);
        return toObject(image);
    });
}

bool actionUIWinUIImageSetFile(ActionUIWinUIObject *image, const char *path) {
    return guarded("image set file", [&]() {
        muxc::Image typed = objectAs<muxc::Image>(image, L"Image");
        std::wstring wide(toHString(path));
        wf::Uri uri = fileUri(wide);
        if (isSVG(wide)) {
            imaging::SvgImageSource source;
            source.UriSource(uri);
            typed.Source(source);
        } else {
            imaging::BitmapImage source;
            // Read the file again: a host that rewrites an image under the same name shows the new one.
            source.CreateOptions(imaging::BitmapCreateOptions::IgnoreImageCache);
            source.UriSource(uri);
            typed.Source(source);
        }
        return true;
    });
}

bool actionUIWinUIImageSetURL(ActionUIWinUIObject *image, const char *url) {
    return guarded("image set URL", [&]() {
        muxc::Image typed = objectAs<muxc::Image>(image, L"Image");
        // Throws for text that is no absolute URI.
        wf::Uri uri(toHString(url));
        if (isSVG(std::wstring(uri.Path()))) {
            imaging::SvgImageSource source;
            source.UriSource(uri);
            typed.Source(source);
        } else {
            // WinUI's image cache is kept: the same URL shown in several places loads once.
            imaging::BitmapImage source;
            source.UriSource(uri);
            typed.Source(source);
        }
        return true;
    });
}

bool actionUIWinUIImageOnOpened(ActionUIWinUIObject *image, ActionUIWinUICallback handler, void *context,
                                ActionUIWinUICallback destroyContext) {
    return registerHandler("image on opened", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::Image>(image, L"Image").ImageOpened([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUIImageOnFailed(ActionUIWinUIObject *image, ActionUIWinUICallback handler, void *context,
                                ActionUIWinUICallback destroyContext) {
    return registerHandler("image on failed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::Image>(image, L"Image").ImageFailed([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUIImageSetStretch(ActionUIWinUIObject *image, ActionUIWinUIImageStretch stretch) {
    return guarded("image set stretch", [&]() {
        muxc::Image typed = objectAs<muxc::Image>(image, L"Image");
        switch (stretch) {
        case ActionUIWinUIImageStretchNone:
            typed.Stretch(media::Stretch::None);
            return true;
        case ActionUIWinUIImageStretchFit:
            typed.Stretch(media::Stretch::Uniform);
            return true;
        case ActionUIWinUIImageStretchFill:
            typed.Stretch(media::Stretch::UniformToFill);
            return true;
        }
        return fail("image set stretch", "unknown stretch");
    });
}

bool actionUIWinUIFileExists(const char *path) {
    if (path == nullptr) {
        return false;
    }
    try {
        std::wstring wide(toHString(path));
        DWORD attributes = GetFileAttributesW(wide.c_str());
        return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
    } catch (...) {
        return false;
    }
}

} // extern "C"

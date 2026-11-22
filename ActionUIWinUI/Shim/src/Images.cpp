// Images.cpp - WinUI's Image control for ActionUI's Image with a file and AsyncImage with a URL: a
// bitmap or an SVG image, at its own size or scaled to fit or cover the size it is arranged in.

#include "ShimInternal.h"

#include <cwctype>
#include <memory>
#include <string>
#include <vector>

#include <propidl.h>  // PROPVARIANT: a GIF's logical screen
#include <wincodec.h>  // WIC: an image file's size from its header

#pragma comment(lib, "windowscodecs.lib")

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

bool startsWith(std::wstring const &text, std::wstring_view prefix) {
    return text.size() >= prefix.size() && std::wstring_view(text).substr(0, prefix.size()) == prefix;
}

std::wstring lowercased(std::wstring text) {
    for (wchar_t &character : text) {
        character = static_cast<wchar_t>(towlower(character));
    }
    return text;
}

// Whether `path` (absolute, or relative to the current folder) names a regular file, symbolic links
// and junctions followed: not missing, not a folder, not a device (NUL, CON, COM1, \\.\...), not a
// pipe. A document names the path, and WinUI would read a device or a pipe forever, or wait on it.
// The name rules come first, so a device or a pipe the path names directly is never opened; one
// reached through a link is opened for its attributes only, and refused.
bool isRegularFile(std::wstring const &path) {
    if (path.empty()) {
        return false;
    }
    DWORD needed = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (needed == 0) {
        return false;
    }
    std::vector<wchar_t> buffer(needed);
    DWORD written = GetFullPathNameW(path.c_str(), needed, buffer.data(), nullptr);
    if (written == 0 || written >= needed) {
        return false;
    }
    std::wstring full(buffer.data(), written);
    // The device namespace: "\\.\pipe\name", "\\.\COM1", and a reserved name anywhere ("NUL",
    // "C:\folder\CON"), which GetFullPathName turns into "\\.\NUL".
    if (startsWith(full, L"\\\\.\\")) {
        return false;
    }
    // "\\?\" is a device path too, except a long path on a drive ("\\?\C:\...") or a share
    // ("\\?\UNC\server\share\...").
    std::wstring server;
    if (startsWith(full, L"\\\\?\\")) {
        std::wstring rest = full.substr(4);
        bool drive = rest.size() >= 3 && iswalpha(rest[0]) && rest[1] == L':' && rest[2] == L'\\';
        bool share = startsWith(lowercased(rest.substr(0, 4)), L"unc\\");
        if (!drive && !share) {
            return false;
        }
        if (share) {
            server = rest.substr(4);
        }
    } else if (startsWith(full, L"\\\\")) {
        server = full.substr(2);
    }
    // A pipe or a mailslot on a server: "\\server\pipe\name", "\\server\mailslot\name".
    if (!server.empty()) {
        size_t slash = server.find(L'\\');
        std::wstring share = slash == std::wstring::npos ? std::wstring() : server.substr(slash + 1, server.find(L'\\', slash + 1) - slash - 1);
        if (lowercased(share) == L"pipe" || lowercased(share) == L"mailslot") {
            return false;
        }
    }
    DWORD attributes = GetFileAttributesW(full.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_DEVICE)) != 0) {
        return false;
    }
    // What the path leads to must be a regular file on a disk. Asked of a handle for every path, not
    // only a link: a link or a drive letter earlier in the path (not only its last name) can lead into
    // the pipe or device namespace, where the attributes above look like a file's (a pipe reports
    // FILE_ATTRIBUTE_NORMAL). Opened for its attributes only, never read.
    HANDLE file = CreateFileW(full.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                              OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }
    BY_HANDLE_FILE_INFORMATION information{};
    bool onDisk = GetFileType(file) == FILE_TYPE_DISK;
    bool read = GetFileInformationByHandle(file, &information) != 0;
    CloseHandle(file);
    return onDisk && read && (information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_DEVICE)) == 0;
}

// The path a file URI names ("file:///C:/folder/a%20b.png" is "C:\folder\a b.png", "file://server/
// share/a.png" is "\\server\share\a.png").
std::wstring filePathOf(wf::Uri const &uri) {
    std::wstring path(wf::Uri::UnescapeComponent(uri.Path()));
    for (wchar_t &character : path) {
        if (character == L'/') {
            character = L'\\';
        }
    }
    bool drive = path.size() >= 3 && path[0] == L'\\' && iswalpha(path[1]) && path[2] == L':';
    std::wstring host(uri.Host());
    // "file://localhost/C:/a.png" is a local path; "file://localhost/pipe/x" is read as the share it may
    // be ("\\localhost\pipe\x"), so the pipe rule sees what Windows could open.
    if (!host.empty() && (!drive || lowercased(host) != L"localhost")) {
        return L"\\\\" + host + path;
    }
    if (drive) {
        path.erase(0, 1);
    }
    return path;
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
        if (!isRegularFile(wide)) {
            return fail("image set file", "the path names no regular file (a missing file, a folder, a device or a pipe)");
        }
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
        if (lowercased(std::wstring(uri.SchemeName())) == L"file" && !isRegularFile(filePathOf(uri))) {
            return fail("image set URL", "the file URL names no regular file (a missing file, a folder, a device or a pipe)");
        }
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

bool actionUIWinUIImageFileGetSize(const char *path, uint32_t *width, uint32_t *height) {
    if (path == nullptr || width == nullptr || height == nullptr) {
        return false;
    }
    try {
        winrt::com_ptr<IWICImagingFactory> factory;
        if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.put())))) {
            return false;
        }
        // The decoder reads the header (and the frame's, at GetFrame); pixels are decoded only when
        // asked for (CopyPixels), which this never does.
        std::wstring wide(toHString(path));
        winrt::com_ptr<IWICBitmapDecoder> decoder;
        if (FAILED(factory->CreateDecoderFromFilename(wide.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
                                                      decoder.put()))) {
            return false;
        }
        // The largest the image can be drawn at: the largest frame (an icon holds several sizes, an
        // animation several frames; a reasonable number of them is read), and a GIF's logical screen,
        // which an animation is drawn on whatever its frames' sizes.
        UINT frameCount = 0;
        if (FAILED(decoder->GetFrameCount(&frameCount)) || frameCount == 0) {
            return false;
        }
        uint64_t largest = 0;
        UINT largestWidth = 0;
        UINT largestHeight = 0;
        auto consider = [&](UINT frameWidth, UINT frameHeight) {
            uint64_t pixels = static_cast<uint64_t>(frameWidth) * frameHeight;
            if (pixels >= largest) {
                largest = pixels;
                largestWidth = frameWidth;
                largestHeight = frameHeight;
            }
        };
        for (UINT index = 0; index < frameCount && index < 256; ++index) {
            winrt::com_ptr<IWICBitmapFrameDecode> frame;
            UINT frameWidth = 0;
            UINT frameHeight = 0;
            if (FAILED(decoder->GetFrame(index, frame.put())) || FAILED(frame->GetSize(&frameWidth, &frameHeight))) {
                return false;
            }
            consider(frameWidth, frameHeight);
        }
        winrt::com_ptr<IWICMetadataQueryReader> metadata;
        if (SUCCEEDED(decoder->GetMetadataQueryReader(metadata.put())) && metadata != nullptr) {
            PROPVARIANT screenWidth;
            PROPVARIANT screenHeight;
            PropVariantInit(&screenWidth);
            PropVariantInit(&screenHeight);
            if (SUCCEEDED(metadata->GetMetadataByName(L"/logscrdesc/Width", &screenWidth)) && screenWidth.vt == VT_UI2
                && SUCCEEDED(metadata->GetMetadataByName(L"/logscrdesc/Height", &screenHeight)) && screenHeight.vt == VT_UI2) {
                consider(screenWidth.uiVal, screenHeight.uiVal);
            }
            PropVariantClear(&screenWidth);
            PropVariantClear(&screenHeight);
        }
        *width = largestWidth;
        *height = largestHeight;
        return true;
    } catch (...) {
        return false;
    }
}

bool actionUIWinUIIsRegularFile(const char *path) {
    if (path == nullptr) {
        return false;
    }
    try {
        return isRegularFile(std::wstring(toHString(path)));
    } catch (...) {
        return false;
    }
}

} // extern "C"

// Symbols.cpp - SF Symbols on Windows: the Material Symbols outline that ActionUI's SF -> Material map gives
// a name, at the row's fill and weight (at most 300), or for a name that map lacks the Fluent System Icons
// outline of its SF -> Fluent map, compiled into the shim (generated/symbols.inc, written by
// Scripts/prepare-windows-symbols.py), drawn as a WinUI PathIcon in the Material glyph's em box. No font
// ships; the Material outlines are those of the Linux icons, thinner where Linux draws them at 400. Their path text is compressed with Windows'
// Compression API (about 2.1 MB in 0.6 MB) and unpacked once, at the first symbol drawn.

#include "ShimInternal.h"

#include <algorithm>
#include <cstring>
#include <iterator>
#include <string>
#include <vector>

#include <compressapi.h>

#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.UI.Xaml.Interop.h>

#pragma comment(lib, "cabinet.lib")

namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

namespace {

struct SymbolRow {
    const char *name;
    unsigned short path;
};

#if __has_include("generated/symbols.inc")
#include "generated/symbols.inc"
constexpr size_t kSymbolRowCount = std::size(kSymbolRows);
#else
#define ACTIONUI_SYMBOL_UNITS 960
#define ACTIONUI_SYMBOL_ALGORITHM COMPRESS_ALGORITHM_LZMS
#define ACTIONUI_SYMBOL_TEXT_SIZE 0
const unsigned char kSymbolData[] = {0};
const unsigned int kSymbolOffsets[] = {0};
const SymbolRow kSymbolRows[] = {{"", 0}};
constexpr size_t kSymbolRowCount = 0;
#endif

// The outlines' path text, unpacked once (C++ makes the first call's initialization thread-safe; a
// failure throws, and the next call tries again).
std::vector<char> const &symbolText() {
    static std::vector<char> const text = []() {
        std::vector<char> unpacked(ACTIONUI_SYMBOL_TEXT_SIZE);
        DECOMPRESSOR_HANDLE handle = nullptr;
        if (!CreateDecompressor(ACTIONUI_SYMBOL_ALGORITHM, nullptr, &handle)) {
            winrt::throw_last_error();
        }
        SIZE_T written = 0;
        BOOL unpackedAll = Decompress(handle, kSymbolData, sizeof(kSymbolData), unpacked.data(), unpacked.size(),
                                      &written);
        DWORD error = GetLastError();
        CloseDecompressor(handle);
        if (!unpackedAll) {
            winrt::throw_hresult(HRESULT_FROM_WIN32(error));
        }
        if (written != unpacked.size()) {
            throw winrt::hresult_error(E_FAIL, L"the symbol outlines unpacked to an unexpected size");
        }
        return unpacked;
    }();
    return text;
}

// The path text of outline `index` (NUL-terminated, inside symbolText()).
const char *symbolPath(unsigned short index) {
    return symbolText().data() + kSymbolOffsets[index];
}

// The row of `name`, or nullptr. The rows are sorted by name, byte by byte.
const SymbolRow *findRow(const char *name) {
    const SymbolRow *begin = kSymbolRows;
    const SymbolRow *end = kSymbolRows + kSymbolRowCount;
    const SymbolRow *found = std::lower_bound(begin, end, name, [](SymbolRow const &row, const char *wanted) {
        return std::strcmp(row.name, wanted) < 0;
    });
    return found != end && std::strcmp(found->name, name) == 0 ? found : nullptr;
}

// The outline as a geometry: XAML's path syntax, with "F1" for the nonzero fill rule fonts use (the
// syntax's default, even-odd, would hollow out overlapping contours).
media::Geometry geometry(const char *path) {
    std::string text = std::string("F1 ") + path;
    wf::IInspectable converted = mux::Markup::XamlBindingHelper::ConvertValue(
        winrt::xaml_typename<media::Geometry>(), winrt::box_value(winrt::to_hstring(text)));
    return converted.as<media::Geometry>();
}

} // namespace

namespace actionui_winui {

const char *symbolOutline(const char *name) {
    const SymbolRow *row = name != nullptr ? findRow(name) : nullptr;
    return row != nullptr ? symbolPath(row->path) : nullptr;
}

double symbolUnits() {
    return ACTIONUI_SYMBOL_UNITS;
}

} // namespace actionui_winui

extern "C" {

bool actionUIWinUISymbolsAvailable(void) {
    return kSymbolRowCount != 0;
}

bool actionUIWinUISymbolExists(const char *name) {
    return name != nullptr && findRow(name) != nullptr;
}

ActionUIWinUIObject *actionUIWinUISymbolCreate(const char *name) {
    return guardedObject("symbol create", [&]() -> ActionUIWinUIObject * {
        const SymbolRow *row = name != nullptr ? findRow(name) : nullptr;
        if (row == nullptr) {
            fail("symbol create", kSymbolRowCount == 0 ? "the shim was built without symbol outlines"
                                                       : "no outline for that symbol name");
            return nullptr;
        }
        // A PathIcon, not a Path: an icon draws in the inherited text color (a button's, which changes
        // with its state), as SF Symbols take the text color.
        muxc::PathIcon icon;
        icon.Data(geometry(symbolPath(row->path)));
        double units = ACTIONUI_SYMBOL_UNITS;
        icon.Width(units);
        icon.Height(units);
        return toObject(icon);
    });
}

bool actionUIWinUISymbolSetSize(ActionUIWinUIObject *symbol, double size) {
    return guarded("symbol set size", [&]() {
        muxc::PathIcon icon = objectAs<muxc::PathIcon>(symbol, L"PathIcon");
        if (!(size >= 0)) {
            return fail("symbol set size", "the size is not a number of pixels");
        }
        // One transform per symbol, made at the first size: stacks size a symbol several times a pass.
        media::ScaleTransform scale = icon.Data().Transform().try_as<media::ScaleTransform>();
        if (scale == nullptr) {
            scale = media::ScaleTransform();
            icon.Data().Transform(scale);
        }
        scale.ScaleX(size / ACTIONUI_SYMBOL_UNITS);
        scale.ScaleY(size / ACTIONUI_SYMBOL_UNITS);
        icon.Width(size);
        icon.Height(size);
        return true;
    });
}

} // extern "C"

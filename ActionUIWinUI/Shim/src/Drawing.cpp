// Drawing.cpp - a Canvas's drawing: Direct2D into a WIC bitmap (in software, premultiplied BGRA) at the
// window's scale, shown by a WinUI Image through a WriteableBitmap. Direct2D ships with Windows: no
// package or DLL to deploy. The caller builds each path (move, line, curves, close), then fills,
// strokes or clips with it under the transform it set; finishing shows the bitmap.

#include "ShimInternal.h"

#include <charconv>
#include <cmath>
#include <cstring>
#include <vector>

#include <d2d1_1.h>
#include <dwrite.h>
#include <wincodec.h>

#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "windowscodecs.lib")

namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;

using namespace actionui_winui;

// One drawing, from actionUIWinUIDrawingBegin to actionUIWinUIDrawingFinish.
struct ActionUIWinUIDrawing {
    winrt::com_ptr<IWICBitmap> bitmap;
    winrt::com_ptr<ID2D1RenderTarget> target;
    UINT pixelWidth = 0;
    UINT pixelHeight = 0;
    D2D1_MATRIX_3X2_F transform = D2D1::Matrix3x2F::Identity();
    // The path being built, and where its figure stands.
    winrt::com_ptr<ID2D1PathGeometry> path;
    winrt::com_ptr<ID2D1GeometrySink> sink;
    bool figureOpen = false;
    bool hasPoint = false;
    D2D1_POINT_2F current{};
    D2D1_POINT_2F start{};
    // Clip layers pushed, popped at the end.
    int layers = 0;
};

namespace {

// One factory for the UI thread's drawings (single-threaded: every drawing is made on it).
ID2D1Factory1 *factory() {
    static winrt::com_ptr<ID2D1Factory1> shared;
    if (!shared) {
        D2D1_FACTORY_OPTIONS options{};
        winrt::check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), &options, shared.put_void()));
    }
    return shared.get();
}

IWICImagingFactory *imagingFactory() {
    static winrt::com_ptr<IWICImagingFactory> shared;
    if (!shared) {
        shared = winrt::create_instance<IWICImagingFactory>(CLSID_WICImagingFactory, CLSCTX_INPROC_SERVER);
    }
    return shared.get();
}

IDWriteFactory *writeFactory() {
    static winrt::com_ptr<IDWriteFactory> shared;
    if (!shared) {
        winrt::check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                                 reinterpret_cast<IUnknown **>(shared.put())));
    }
    return shared.get();
}

D2D1_COLOR_F colorOf(ActionUIWinUIColor color) {
    auto part = [](double value) { return static_cast<float>(std::isfinite(value) ? std::fmin(std::fmax(value, 0.0), 1.0) : 0.0); };
    return D2D1::ColorF(part(color.red), part(color.green), part(color.blue), part(color.alpha));
}

// The drawing's pending path, closed for use (the figure ended open unless closed); null when it
// has no figure. The drawing starts a new path after.
winrt::com_ptr<ID2D1PathGeometry> takePath(ActionUIWinUIDrawing *drawing) {
    winrt::com_ptr<ID2D1PathGeometry> path = drawing->path;
    winrt::com_ptr<ID2D1GeometrySink> sink = drawing->sink;
    bool figureOpen = drawing->figureOpen;
    // Reset first: a sink whose Close fails must not stay pending, or every later use and the
    // finish would fail on it again.
    drawing->path = nullptr;
    drawing->sink = nullptr;
    drawing->figureOpen = false;
    drawing->hasPoint = false;
    if (!sink) {
        return nullptr;
    }
    if (figureOpen) {
        sink->EndFigure(D2D1_FIGURE_END_OPEN);
    }
    winrt::check_hresult(sink->Close());
    return path;
}

// The sink, made with the path at the first segment.
ID2D1GeometrySink *sinkOf(ActionUIWinUIDrawing *drawing) {
    if (!drawing->sink) {
        winrt::check_hresult(factory()->CreatePathGeometry(drawing->path.put()));
        winrt::check_hresult(drawing->path->Open(drawing->sink.put()));
        drawing->sink->SetFillMode(D2D1_FILL_MODE_WINDING);
    }
    return drawing->sink.get();
}

// A figure to add a segment to: after a close, the next segment starts again where the closed
// figure started, as a path continues from its subpath's start.
ID2D1GeometrySink *figureSink(ActionUIWinUIDrawing *drawing) {
    ID2D1GeometrySink *sink = sinkOf(drawing);
    if (!drawing->figureOpen) {
        sink->BeginFigure(drawing->current, D2D1_FIGURE_BEGIN_FILLED);
        drawing->start = drawing->current;
        drawing->figureOpen = true;
    }
    return sink;
}

// `count` stops (at least one; offsets 0...1 in order) as Direct2D's, the colors past the ends
// extended.
winrt::com_ptr<ID2D1GradientStopCollection> stopsOf(ID2D1RenderTarget *target, const ActionUIWinUIColor *colors,
                                                    const double *offsets, int32_t count) {
    if (colors == nullptr || offsets == nullptr || count < 1) {
        throw winrt::hresult_invalid_argument(L"a gradient needs at least one color");
    }
    std::vector<D2D1_GRADIENT_STOP> stops;
    for (int32_t index = 0; index < count; ++index) {
        double offset = std::isfinite(offsets[index]) ? std::fmin(std::fmax(offsets[index], 0.0), 1.0) : 0.0;
        stops.push_back(D2D1::GradientStop(static_cast<float>(offset), colorOf(colors[index])));
    }
    winrt::com_ptr<ID2D1GradientStopCollection> collection;
    winrt::check_hresult(target->CreateGradientStopCollection(stops.data(), static_cast<UINT32>(stops.size()), D2D1_GAMMA_2_2,
                                                             D2D1_EXTEND_MODE_CLAMP, collection.put()));
    return collection;
}

// Adds SVG path text (M, L, H, V, Q, C, Z, absolute or relative; the symbols' outlines) to `sink`.
// False at anything else, or a command short of numbers.
bool addSVGPath(const char *text, ID2D1GeometrySink *sink) {
    const char *cursor = text;
    const char *end = text + std::strlen(text);
    char command = 0;
    bool figureOpen = false;
    D2D1_POINT_2F current{0, 0};
    D2D1_POINT_2F start{0, 0};
    auto skip = [&]() {
        while (cursor < end && (*cursor == ' ' || *cursor == ',' || *cursor == '\t' || *cursor == '\n' || *cursor == '\r')) {
            ++cursor;
        }
    };
    auto number = [&](float &value) {
        skip();
        double parsed = 0;
        std::from_chars_result result = std::from_chars(cursor, end, parsed);
        if (result.ec != std::errc() || !std::isfinite(parsed)) {
            return false;
        }
        cursor = result.ptr;
        value = static_cast<float>(parsed);
        return true;
    };
    auto begin = [&]() {
        if (!figureOpen) {
            sink->BeginFigure(current, D2D1_FIGURE_BEGIN_FILLED);
            start = current;
            figureOpen = true;
        }
    };
    while (true) {
        skip();
        if (cursor >= end) {
            break;
        }
        char next = *cursor;
        if ((next >= 'A' && next <= 'Z') || (next >= 'a' && next <= 'z')) {
            command = next;
            ++cursor;
        } else if (command == 0) {
            return false;
        }
        bool relative = command >= 'a' && command <= 'z';
        float dx = relative ? current.x : 0;
        float dy = relative ? current.y : 0;
        switch (command) {
        case 'M':
        case 'm': {
            float x = 0, y = 0;
            if (!number(x) || !number(y)) {
                return false;
            }
            if (figureOpen) {
                sink->EndFigure(D2D1_FIGURE_END_OPEN);
                figureOpen = false;
            }
            current = D2D1::Point2F(x + dx, y + dy);
            // More pairs after a move are lines.
            command = relative ? 'l' : 'L';
            break;
        }
        case 'L':
        case 'l': {
            float x = 0, y = 0;
            if (!number(x) || !number(y)) {
                return false;
            }
            begin();
            current = D2D1::Point2F(x + dx, y + dy);
            sink->AddLine(current);
            break;
        }
        case 'H':
        case 'h': {
            float x = 0;
            if (!number(x)) {
                return false;
            }
            begin();
            current = D2D1::Point2F(x + dx, current.y);
            sink->AddLine(current);
            break;
        }
        case 'V':
        case 'v': {
            float y = 0;
            if (!number(y)) {
                return false;
            }
            begin();
            current = D2D1::Point2F(current.x, y + dy);
            sink->AddLine(current);
            break;
        }
        case 'Q':
        case 'q': {
            float cx = 0, cy = 0, x = 0, y = 0;
            if (!number(cx) || !number(cy) || !number(x) || !number(y)) {
                return false;
            }
            begin();
            D2D1_POINT_2F control = D2D1::Point2F(cx + dx, cy + dy);
            current = D2D1::Point2F(x + dx, y + dy);
            sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(control, current));
            break;
        }
        case 'C':
        case 'c': {
            float c1x = 0, c1y = 0, c2x = 0, c2y = 0, x = 0, y = 0;
            if (!number(c1x) || !number(c1y) || !number(c2x) || !number(c2y) || !number(x) || !number(y)) {
                return false;
            }
            begin();
            D2D1_POINT_2F first = D2D1::Point2F(c1x + dx, c1y + dy);
            D2D1_POINT_2F second = D2D1::Point2F(c2x + dx, c2y + dy);
            current = D2D1::Point2F(x + dx, y + dy);
            sink->AddBezier(D2D1::BezierSegment(first, second, current));
            break;
        }
        case 'Z':
        case 'z':
            if (figureOpen) {
                sink->EndFigure(D2D1_FIGURE_END_CLOSED);
                figureOpen = false;
            }
            current = start;
            // A number after Z is no command's.
            command = 0;
            break;
        default:
            return false;
        }
    }
    if (figureOpen) {
        sink->EndFigure(D2D1_FIGURE_END_OPEN);
    }
    return true;
}

// The theme's primary text color (what an Image's symbol draws in), black when the theme has none.
D2D1_COLOR_F themeTextColor() {
    try {
        wf::IInspectable found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"TextFillColorPrimaryBrush"));
        if (media::SolidColorBrush brush = found != nullptr ? found.try_as<media::SolidColorBrush>() : nullptr) {
            winrt::Windows::UI::Color color = brush.Color();
            return D2D1::ColorF(color.R / 255.0f, color.G / 255.0f, color.B / 255.0f, color.A / 255.0f * static_cast<float>(brush.Opacity()));
        }
    } catch (winrt::hresult_error const &) {
    }
    return D2D1::ColorF(0, 0, 0, 1);
}

float opacityOf(double opacity) {
    return static_cast<float>(std::isfinite(opacity) ? std::fmin(std::fmax(opacity, 0.0), 1.0) : 1.0);
}

ActionUIWinUIDrawing *drawingOf(ActionUIWinUIDrawing *drawing) {
    if (drawing == nullptr) {
        throw winrt::hresult_invalid_argument(L"the drawing is NULL");
    }
    if (!drawing->target) {
        throw winrt::hresult_illegal_method_call(L"the drawing has ended");
    }
    return drawing;
}

} // namespace

extern "C" {

ActionUIWinUIDrawing *actionUIWinUIDrawingBegin(double width, double height, double scale) {
    ActionUIWinUIDrawing *made = nullptr;
    bool begun = guarded("drawing begin", [&]() {
        if (!(width > 0) || !(height > 0) || !(scale > 0) || !std::isfinite(width * scale) || !std::isfinite(height * scale)) {
            return fail("drawing begin", "the size or the scale is not a positive number");
        }
        double pixelWidth = std::ceil(width * scale);
        double pixelHeight = std::ceil(height * scale);
        // Direct2D's software target takes up to 16384 pixels a side; past it the canvas is not drawn.
        if (pixelWidth > 16384 || pixelHeight > 16384) {
            return fail("drawing begin", "the canvas is larger than 16384 pixels a side");
        }
        auto drawing = std::make_unique<ActionUIWinUIDrawing>();
        drawing->pixelWidth = static_cast<UINT>(pixelWidth);
        drawing->pixelHeight = static_cast<UINT>(pixelHeight);
        winrt::check_hresult(imagingFactory()->CreateBitmap(drawing->pixelWidth, drawing->pixelHeight, GUID_WICPixelFormat32bppPBGRA,
                                                            WICBitmapCacheOnLoad, drawing->bitmap.put()));
        // Drawn in points: 96 dots per inch at a scale of 1.
        float dpi = static_cast<float>(96.0 * scale);
        D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_SOFTWARE, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
        winrt::check_hresult(factory()->CreateWicBitmapRenderTarget(drawing->bitmap.get(), properties, drawing->target.put()));
        drawing->target->BeginDraw();
        drawing->target->Clear(D2D1::ColorF(0, 0, 0, 0));
        made = drawing.release();
        return true;
    });
    return begun ? made : nullptr;
}

bool actionUIWinUIDrawingSetTransform(ActionUIWinUIDrawing *drawing, double a, double b, double c, double d, double tx, double ty) {
    return guarded("drawing set transform", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        // A path not used yet is dropped: each path starts with its transform.
        takePath(typed);
        typed->transform = D2D1::Matrix3x2F(static_cast<float>(a), static_cast<float>(b), static_cast<float>(c), static_cast<float>(d),
                                            static_cast<float>(tx), static_cast<float>(ty));
        typed->target->SetTransform(typed->transform);
        return true;
    });
}

bool actionUIWinUIDrawingMoveTo(ActionUIWinUIDrawing *drawing, double x, double y) {
    return guarded("drawing move to", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        ID2D1GeometrySink *sink = sinkOf(typed);
        if (typed->figureOpen) {
            sink->EndFigure(D2D1_FIGURE_END_OPEN);
            typed->figureOpen = false;
        }
        typed->current = D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
        typed->hasPoint = true;
        return true;
    });
}

bool actionUIWinUIDrawingLineTo(ActionUIWinUIDrawing *drawing, double x, double y) {
    return guarded("drawing line to", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        if (!typed->hasPoint) {
            return fail("drawing line to", "no point to draw from (no move before)");
        }
        D2D1_POINT_2F point = D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
        figureSink(typed)->AddLine(point);
        typed->current = point;
        return true;
    });
}

bool actionUIWinUIDrawingQuadTo(ActionUIWinUIDrawing *drawing, double cx, double cy, double x, double y) {
    return guarded("drawing quad to", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        if (!typed->hasPoint) {
            return fail("drawing quad to", "no point to draw from (no move before)");
        }
        D2D1_POINT_2F point = D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
        figureSink(typed)->AddQuadraticBezier(D2D1::QuadraticBezierSegment(D2D1::Point2F(static_cast<float>(cx), static_cast<float>(cy)), point));
        typed->current = point;
        return true;
    });
}

bool actionUIWinUIDrawingCubicTo(ActionUIWinUIDrawing *drawing, double c1x, double c1y, double c2x, double c2y, double x, double y) {
    return guarded("drawing cubic to", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        if (!typed->hasPoint) {
            return fail("drawing cubic to", "no point to draw from (no move before)");
        }
        D2D1_POINT_2F point = D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
        figureSink(typed)->AddBezier(D2D1::BezierSegment(D2D1::Point2F(static_cast<float>(c1x), static_cast<float>(c1y)),
                                                         D2D1::Point2F(static_cast<float>(c2x), static_cast<float>(c2y)), point));
        typed->current = point;
        return true;
    });
}

bool actionUIWinUIDrawingClose(ActionUIWinUIDrawing *drawing) {
    return guarded("drawing close", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        if (typed->figureOpen) {
            typed->sink->EndFigure(D2D1_FIGURE_END_CLOSED);
            typed->figureOpen = false;
            typed->current = typed->start;
        }
        return true;
    });
}

bool actionUIWinUIDrawingFill(ActionUIWinUIDrawing *drawing, ActionUIWinUIColor color) {
    return guarded("drawing fill", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        winrt::com_ptr<ID2D1PathGeometry> path = takePath(typed);
        if (!path) {
            return true;
        }
        winrt::com_ptr<ID2D1SolidColorBrush> brush;
        winrt::check_hresult(typed->target->CreateSolidColorBrush(colorOf(color), brush.put()));
        typed->target->FillGeometry(path.get(), brush.get());
        return true;
    });
}

bool actionUIWinUIDrawingFillLinearGradient(ActionUIWinUIDrawing *drawing, double x0, double y0, double x1, double y1,
                                            const ActionUIWinUIColor *colors, const double *offsets, int32_t count) {
    return guarded("drawing fill linear gradient", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        winrt::com_ptr<ID2D1PathGeometry> path = takePath(typed);
        if (!path) {
            return true;
        }
        winrt::com_ptr<ID2D1GradientStopCollection> stops = stopsOf(typed->target.get(), colors, offsets, count);
        winrt::com_ptr<ID2D1LinearGradientBrush> brush;
        winrt::check_hresult(typed->target->CreateLinearGradientBrush(
            D2D1::LinearGradientBrushProperties(D2D1::Point2F(static_cast<float>(x0), static_cast<float>(y0)),
                                                D2D1::Point2F(static_cast<float>(x1), static_cast<float>(y1))),
            stops.get(), brush.put()));
        typed->target->FillGeometry(path.get(), brush.get());
        return true;
    });
}

bool actionUIWinUIDrawingFillRadialGradient(ActionUIWinUIDrawing *drawing, double cx, double cy, double radius,
                                            const ActionUIWinUIColor *colors, const double *offsets, int32_t count) {
    return guarded("drawing fill radial gradient", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        winrt::com_ptr<ID2D1PathGeometry> path = takePath(typed);
        if (!path) {
            return true;
        }
        winrt::com_ptr<ID2D1GradientStopCollection> stops = stopsOf(typed->target.get(), colors, offsets, count);
        winrt::com_ptr<ID2D1RadialGradientBrush> brush;
        float r = static_cast<float>(radius);
        winrt::check_hresult(typed->target->CreateRadialGradientBrush(
            D2D1::RadialGradientBrushProperties(D2D1::Point2F(static_cast<float>(cx), static_cast<float>(cy)), D2D1::Point2F(0, 0), r, r),
            stops.get(), brush.put()));
        typed->target->FillGeometry(path.get(), brush.get());
        return true;
    });
}

bool actionUIWinUIDrawingText(ActionUIWinUIDrawing *drawing, const char *text, double x, double y, double width, double fontSize,
                              int32_t weight, ActionUIWinUIColor color) {
    return guarded("drawing text", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        takePath(typed);
        if (!(fontSize > 0) || !std::isfinite(fontSize) || !std::isfinite(x) || !std::isfinite(y)) {
            return true;
        }
        winrt::hstring wide = toHString(text);
        if (wide.empty()) {
            return true;
        }
        DWRITE_FONT_WEIGHT fontWeight = static_cast<DWRITE_FONT_WEIGHT>(weight >= 1 && weight <= 999 ? weight : 400);
        winrt::com_ptr<IDWriteTextFormat> format;
        // WinUI's text font on Windows 11 (Segoe UI Variable); a family the system lacks falls back to
        // its default.
        winrt::check_hresult(writeFactory()->CreateTextFormat(L"Segoe UI Variable Text", nullptr, fontWeight, DWRITE_FONT_STYLE_NORMAL,
                                                              DWRITE_FONT_STRETCH_NORMAL, static_cast<float>(fontSize), L"",
                                                              format.put()));
        // Wrapped at the frame's width, a long word broken where it must be; none past an empty frame.
        bool wraps = width > 0 && std::isfinite(width);
        winrt::check_hresult(format->SetWordWrapping(wraps ? DWRITE_WORD_WRAPPING_EMERGENCY_BREAK : DWRITE_WORD_WRAPPING_NO_WRAP));
        winrt::com_ptr<IDWriteTextLayout> layout;
        winrt::check_hresult(writeFactory()->CreateTextLayout(wide.c_str(), static_cast<UINT32>(wide.size()), format.get(),
                                                              wraps ? static_cast<float>(width) : 1.0e6f, 1.0e6f, layout.put()));
        winrt::com_ptr<ID2D1SolidColorBrush> brush;
        winrt::check_hresult(typed->target->CreateSolidColorBrush(colorOf(color), brush.put()));
        // Color emoji in color, as Apple draws them.
        typed->target->DrawTextLayout(D2D1::Point2F(static_cast<float>(x), static_cast<float>(y)), layout.get(), brush.get(),
                                      D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
        return true;
    });
}

bool actionUIWinUIDrawingImageFile(ActionUIWinUIDrawing *drawing, const char *path, double x, double y, double width,
                                   double height, double opacity) {
    return guarded("drawing image file", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        takePath(typed);
        // A document names the path: a device or a pipe is never opened (Images.cpp).
        if (!actionUIWinUIIsRegularFile(path)) {
            return fail("drawing image file", "the path names no regular file");
        }
        std::wstring wide(toHString(path));
        winrt::com_ptr<IWICBitmapDecoder> decoder;
        winrt::check_hresult(imagingFactory()->CreateDecoderFromFilename(wide.c_str(), nullptr, GENERIC_READ,
                                                                         WICDecodeMetadataCacheOnDemand, decoder.put()));
        winrt::com_ptr<IWICBitmapFrameDecode> frame;
        winrt::check_hresult(decoder->GetFrame(0, frame.put()));
        winrt::com_ptr<IWICFormatConverter> converter;
        winrt::check_hresult(imagingFactory()->CreateFormatConverter(converter.put()));
        winrt::check_hresult(converter->Initialize(frame.get(), GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr, 0,
                                                   WICBitmapPaletteTypeMedianCut));
        winrt::com_ptr<ID2D1Bitmap> bitmap;
        winrt::check_hresult(typed->target->CreateBitmapFromWicBitmap(converter.get(), nullptr, bitmap.put()));
        // Stretched to the frame.
        typed->target->DrawBitmap(bitmap.get(),
                                  D2D1::RectF(static_cast<float>(x), static_cast<float>(y), static_cast<float>(x + width),
                                              static_cast<float>(y + height)),
                                  opacityOf(opacity), D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        return true;
    });
}

bool actionUIWinUIDrawingSymbol(ActionUIWinUIDrawing *drawing, const char *name, double x, double y, double width, double height,
                                const ActionUIWinUIColor *color, double opacity) {
    return guarded("drawing symbol", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        takePath(typed);
        const char *outline = symbolOutline(name);
        if (outline == nullptr) {
            return fail("drawing symbol", "no outline for that symbol name");
        }
        winrt::com_ptr<ID2D1PathGeometry> geometry;
        winrt::check_hresult(factory()->CreatePathGeometry(geometry.put()));
        winrt::com_ptr<ID2D1GeometrySink> sink;
        winrt::check_hresult(geometry->Open(sink.put()));
        // The nonzero rule fonts use (even-odd would hollow out overlapping contours).
        sink->SetFillMode(D2D1_FILL_MODE_WINDING);
        bool parsed = addSVGPath(outline, sink.get());
        winrt::check_hresult(sink->Close());
        if (!parsed) {
            return fail("drawing symbol", "the symbol's outline cannot be read");
        }
        D2D1_COLOR_F fill = color != nullptr ? colorOf(*color) : themeTextColor();
        fill.a *= opacityOf(opacity);
        winrt::com_ptr<ID2D1SolidColorBrush> brush;
        winrt::check_hresult(typed->target->CreateSolidColorBrush(fill, brush.put()));
        // The symbol's box stretched to the frame, under the transform set.
        double units = symbolUnits();
        D2D1_MATRIX_3X2_F place = D2D1::Matrix3x2F::Scale(static_cast<float>(width / units), static_cast<float>(height / units)) *
                                  D2D1::Matrix3x2F::Translation(static_cast<float>(x), static_cast<float>(y));
        typed->target->SetTransform(place * typed->transform);
        typed->target->FillGeometry(geometry.get(), brush.get());
        typed->target->SetTransform(typed->transform);
        return true;
    });
}

bool actionUIWinUIDrawingStroke(ActionUIWinUIDrawing *drawing, ActionUIWinUIColor color, double width, ActionUIWinUILineCap cap,
                                ActionUIWinUILineJoin join, double miterLimit, const double *dashes, int32_t dashCount, double dashPhase) {
    return guarded("drawing stroke", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        winrt::com_ptr<ID2D1PathGeometry> path = takePath(typed);
        if (!path || !(width > 0) || !std::isfinite(width)) {
            return true;
        }
        D2D1_CAP_STYLE capStyle = cap == ActionUIWinUILineCapRound    ? D2D1_CAP_STYLE_ROUND
                                  : cap == ActionUIWinUILineCapSquare ? D2D1_CAP_STYLE_SQUARE
                                                                      : D2D1_CAP_STYLE_FLAT;
        // Past the miter limit a corner is beveled, as Core Graphics and GSK do.
        D2D1_LINE_JOIN lineJoin = join == ActionUIWinUILineJoinRound   ? D2D1_LINE_JOIN_ROUND
                                  : join == ActionUIWinUILineJoinBevel ? D2D1_LINE_JOIN_BEVEL
                                                                       : D2D1_LINE_JOIN_MITER_OR_BEVEL;
        // Direct2D's dashes are in line widths; the caller's are in points.
        std::vector<float> pattern;
        if (dashes != nullptr) {
            for (int32_t index = 0; index < dashCount; ++index) {
                double length = std::isfinite(dashes[index]) ? std::fmax(dashes[index], 0.0) : 0.0;
                pattern.push_back(static_cast<float>(length / width));
            }
        }
        // An odd count repeats the list, as Core Graphics cycles it (dash, gap, dash, ...).
        if (pattern.size() % 2 == 1) {
            std::vector<float> twice = pattern;
            pattern.insert(pattern.end(), twice.begin(), twice.end());
        }
        // A pattern of nothing but zeros draws as solid, as Core Graphics draws it.
        bool dashed = false;
        for (float length : pattern) {
            dashed = dashed || length > 0;
        }
        D2D1_STROKE_STYLE_PROPERTIES properties = D2D1::StrokeStyleProperties(
            capStyle, capStyle, capStyle, lineJoin, static_cast<float>(std::isfinite(miterLimit) ? std::fmax(miterLimit, 1.0) : 10.0),
            dashed ? D2D1_DASH_STYLE_CUSTOM : D2D1_DASH_STYLE_SOLID,
            dashed && std::isfinite(dashPhase) ? static_cast<float>(dashPhase / width) : 0.0f);
        winrt::com_ptr<ID2D1StrokeStyle> style;
        winrt::check_hresult(factory()->CreateStrokeStyle(properties, dashed ? pattern.data() : nullptr,
                                                          dashed ? static_cast<UINT32>(pattern.size()) : 0, style.put()));
        winrt::com_ptr<ID2D1SolidColorBrush> brush;
        winrt::check_hresult(typed->target->CreateSolidColorBrush(colorOf(color), brush.put()));
        typed->target->DrawGeometry(path.get(), brush.get(), static_cast<float>(width), style.get());
        return true;
    });
}

bool actionUIWinUIDrawingClip(ActionUIWinUIDrawing *drawing) {
    return guarded("drawing clip", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        winrt::com_ptr<ID2D1PathGeometry> path = takePath(typed);
        // An empty clip leaves nothing to draw in, as an empty clip path does on Apple.
        winrt::com_ptr<ID2D1Geometry> mask;
        if (path) {
            mask = path;
        } else {
            winrt::com_ptr<ID2D1RectangleGeometry> nothing;
            winrt::check_hresult(factory()->CreateRectangleGeometry(D2D1::RectF(0, 0, 0, 0), nothing.put()));
            mask = nothing;
        }
        // The mask is in the transform set now; the drawings after it are clipped where it lies.
        typed->target->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), mask.get()), nullptr);
        typed->layers += 1;
        return true;
    });
}

bool actionUIWinUIDrawingFinish(ActionUIWinUIDrawing *drawing, ActionUIWinUIObject *image) {
    bool shown = guarded("drawing finish", [&]() {
        ActionUIWinUIDrawing *typed = drawingOf(drawing);
        takePath(typed);
        for (; typed->layers > 0; --typed->layers) {
            typed->target->PopLayer();
        }
        typed->target->SetTransform(D2D1::Matrix3x2F::Identity());
        HRESULT ended = typed->target->EndDraw();
        typed->target = nullptr;
        winrt::check_hresult(ended);
        muxc::Image shownImage = objectAs<muxc::Image>(image, L"Image");
        imaging::WriteableBitmap pixels(static_cast<int32_t>(typed->pixelWidth), static_cast<int32_t>(typed->pixelHeight));
        winrt::Windows::Storage::Streams::IBuffer buffer = pixels.PixelBuffer();
        uint8_t *destination = buffer.data();
        size_t rowBytes = static_cast<size_t>(typed->pixelWidth) * 4;
        if (destination == nullptr || buffer.Capacity() < rowBytes * typed->pixelHeight) {
            return fail("drawing finish", "the bitmap has no room for the drawing");
        }
        WICRect whole{0, 0, static_cast<INT>(typed->pixelWidth), static_cast<INT>(typed->pixelHeight)};
        winrt::com_ptr<IWICBitmapLock> lock;
        winrt::check_hresult(typed->bitmap->Lock(&whole, WICBitmapLockRead, lock.put()));
        UINT stride = 0;
        UINT size = 0;
        BYTE *source = nullptr;
        winrt::check_hresult(lock->GetStride(&stride));
        winrt::check_hresult(lock->GetDataPointer(&size, &source));
        if (source == nullptr || stride < rowBytes ||
            size < static_cast<size_t>(stride) * (typed->pixelHeight - 1) + rowBytes) {
            return fail("drawing finish", "the drawing's pixels cannot be read");
        }
        // Both are premultiplied BGRA, top row first.
        for (UINT row = 0; row < typed->pixelHeight; ++row) {
            std::memcpy(destination + row * rowBytes, source + static_cast<size_t>(row) * stride, rowBytes);
        }
        lock = nullptr;
        pixels.Invalidate();
        // The bitmap is the canvas's size at the window's scale: stretched to the canvas exactly.
        shownImage.Stretch(media::Stretch::Fill);
        shownImage.Source(pixels);
        return true;
    });
    delete drawing;
    return shown;
}

void actionUIWinUIDrawingDiscard(ActionUIWinUIDrawing *drawing) {
    if (drawing == nullptr) {
        return;
    }
    try {
        if (drawing->target) {
            takePath(drawing);
            for (; drawing->layers > 0; --drawing->layers) {
                drawing->target->PopLayer();
            }
            drawing->target->EndDraw();
        }
    } catch (...) {
    }
    delete drawing;
}

double actionUIWinUIElementRasterizationScale(ActionUIWinUIObject *element) {
    double scale = 1;
    guarded("element rasterization scale", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (mux::XamlRoot root = typed.XamlRoot()) {
            double value = root.RasterizationScale();
            if (value > 0 && std::isfinite(value)) {
                scale = value;
            }
        }
        return true;
    });
    return scale;
}

bool actionUIWinUIElementOnTapped(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("element on tapped", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        objectAs<mux::UIElement>(element, L"UIElement")
            .Tapped([holder](auto &&, mux::Input::TappedRoutedEventArgs const &arguments) {
                // The element's own: an enclosing element does not see it.
                arguments.Handled(true);
                holder->fire();
            });
    });
}

bool actionUIWinUIElementOnActualThemeChanged(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                              ActionUIWinUICallback destroyContext) {
    return registerHandler("element on actual theme changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<mux::FrameworkElement>(element, L"FrameworkElement")
                                   .ActualThemeChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

} // extern "C"

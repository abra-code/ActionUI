// Drawing.cpp - a Canvas's drawing: Direct2D into a WIC bitmap (in software, premultiplied BGRA) at the
// window's scale, shown by a WinUI Image through a WriteableBitmap. Direct2D ships with Windows: no
// package or DLL to deploy. The caller builds each path (move, line, curves, close), then fills,
// strokes or clips with it under the transform it set; finishing shows the bitmap.

#include "ShimInternal.h"

#include <cmath>
#include <cstring>
#include <vector>

#include <d2d1_1.h>
#include <wincodec.h>

#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>

#pragma comment(lib, "d2d1.lib")
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

} // extern "C"

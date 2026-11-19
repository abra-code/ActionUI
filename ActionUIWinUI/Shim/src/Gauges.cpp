// Gauges.cpp - the drawn forms of ActionUI's Gauge (WinUI has no gauge control): a bar with a dot at the
// value, an open arc with a dot (its gap at the bottom), and a full ring filled clockwise from the top.
// Each is a Canvas of XAML shapes in the accent color over a faint track of the same color, drawn again
// for its size whenever it is resized, as the Linux renderer draws its own.

#include "ShimInternal.h"

#include <cmath>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

namespace shapes = winrt::Microsoft::UI::Xaml::Shapes;
namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace wfc = winrt::Windows::Foundation::Collections;

using namespace actionui_winui;

namespace {

constexpr double pi = 3.14159265358979323846;
// The bar's line, and its dot's diameter; the circular forms' line (the dot's diameter is twice it).
constexpr double barLine = 4;
constexpr double barDot = 8;
constexpr double ringLine = 6;

// The theme's accent brush (a fixed blue when the theme has none).
media::Brush accentBrush() {
    wf::IInspectable found{nullptr};
    try {
        found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"AccentFillColorDefaultBrush"));
    } catch (winrt::hresult_error const &) {
    }
    if (media::Brush brush = found != nullptr ? found.try_as<media::Brush>() : nullptr) {
        return brush;
    }
    return media::SolidColorBrush(winrt::Windows::UI::Color{255, 0, 103, 192});
}

shapes::Path strokePath(media::Brush const &brush, double thickness, double opacity) {
    shapes::Path path;
    path.Stroke(brush);
    path.StrokeThickness(thickness);
    path.StrokeStartLineCap(media::PenLineCap::Round);
    path.StrokeEndLineCap(media::PenLineCap::Round);
    path.Opacity(opacity);
    return path;
}

wf::Point point(double x, double y) {
    return wf::Point{static_cast<float>(x), static_cast<float>(y)};
}

media::Geometry line(double fromX, double toX, double y) {
    media::LineGeometry geometry;
    geometry.StartPoint(point(fromX, y));
    geometry.EndPoint(point(toX, y));
    return geometry;
}

// The arc around (cx, cy) from `start` clockwise through `sweep` (radians, clockwise from the positive x
// axis: -pi/2 is the top); null when `sweep` is not positive. Within a hair of a full turn it is the
// circle: an arc that ends where it starts draws nothing.
media::Geometry arc(double cx, double cy, double radius, double start, double sweep) {
    if (!(sweep > 0)) {
        return nullptr;
    }
    if (sweep >= 2 * pi * (1 - 1e-6)) {
        media::EllipseGeometry circle;
        circle.Center(point(cx, cy));
        circle.RadiusX(radius);
        circle.RadiusY(radius);
        return circle;
    }
    double end = start + sweep;
    media::ArcSegment segment;
    segment.Point(point(cx + radius * std::cos(end), cy + radius * std::sin(end)));
    segment.Size(wf::Size{static_cast<float>(radius), static_cast<float>(radius)});
    segment.IsLargeArc(sweep > pi);
    segment.SweepDirection(media::SweepDirection::Clockwise);
    media::PathFigure figure;
    figure.StartPoint(point(cx + radius * std::cos(start), cy + radius * std::sin(start)));
    figure.IsClosed(false);
    figure.IsFilled(false);
    figure.Segments().Append(segment);
    media::PathGeometry geometry;
    geometry.Figures().Append(figure);
    return geometry;
}

// Draws the gauge for the canvas's size and the fraction kept in its Tag.
void redraw(muxc::Canvas const &canvas) {
    wfc::PropertySet state = canvas.Tag().as<wfc::PropertySet>();
    auto kind = static_cast<ActionUIWinUIGaugeShape>(winrt::unbox_value<int32_t>(state.Lookup(L"shape")));
    double fraction = winrt::unbox_value<double>(state.Lookup(L"fraction"));
    fraction = std::isfinite(fraction) ? (fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction)) : 0;
    double width = canvas.ActualWidth();
    double height = canvas.ActualHeight();
    auto children = canvas.Children();
    shapes::Path track = children.GetAt(0).as<shapes::Path>();
    shapes::Path filled = children.GetAt(1).as<shapes::Path>();
    shapes::Ellipse dot = children.Size() > 2 ? children.GetAt(2).as<shapes::Ellipse>() : nullptr;

    if (kind == ActionUIWinUIGaugeBar) {
        double y = height / 2;
        double left = barLine;
        double right = width - barLine;
        if (!(right > left)) {
            track.Data(nullptr);
            filled.Data(nullptr);
            dot.Visibility(mux::Visibility::Collapsed);
            return;
        }
        double end = left + (right - left) * fraction;
        track.Data(line(left, right, y));
        filled.Data(end > left ? line(left, end, y) : nullptr);
        dot.Visibility(mux::Visibility::Visible);
        muxc::Canvas::SetLeft(dot, end - barDot / 2);
        muxc::Canvas::SetTop(dot, y - barDot / 2);
        return;
    }

    bool marker = kind == ActionUIWinUIGaugeArc;
    double side = width < height ? width : height;
    if (!(side > ringLine * 2)) {
        track.Data(nullptr);
        filled.Data(nullptr);
        if (dot != nullptr) {
            dot.Visibility(mux::Visibility::Collapsed);
        }
        return;
    }
    double cx = width / 2;
    double cy = height / 2;
    double radius = (side - ringLine * (marker ? 2 : 1)) / 2;
    // The arc: three quarters, its gap centered at the bottom; the ring: a full turn from the top.
    double start = marker ? 0.75 * pi : -pi / 2;
    double sweep = marker ? 1.5 * pi : 2 * pi;
    double reached = fraction * sweep;
    track.Data(arc(cx, cy, radius, start, sweep));
    filled.Data(arc(cx, cy, radius, start, reached));
    if (dot != nullptr) {
        double end = start + reached;
        dot.Visibility(mux::Visibility::Visible);
        muxc::Canvas::SetLeft(dot, cx + radius * std::cos(end) - ringLine);
        muxc::Canvas::SetTop(dot, cy + radius * std::sin(end) - ringLine);
    }
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIGaugeDrawingCreate(ActionUIWinUIGaugeShape shape) {
    return guardedObject("gauge drawing create", [&]() -> ActionUIWinUIObject * {
        if (shape != ActionUIWinUIGaugeBar && shape != ActionUIWinUIGaugeArc && shape != ActionUIWinUIGaugeRing) {
            fail("gauge drawing create", "an unknown shape");
            return nullptr;
        }
        muxc::Canvas canvas;
        wfc::PropertySet state;
        state.Insert(L"shape", winrt::box_value(static_cast<int32_t>(shape)));
        state.Insert(L"fraction", winrt::box_value(0.0));
        canvas.Tag(state);
        media::Brush accent = accentBrush();
        double thickness = shape == ActionUIWinUIGaugeBar ? barLine : ringLine;
        canvas.Children().Append(strokePath(accent, thickness, 0.2));
        canvas.Children().Append(strokePath(accent, thickness, 1));
        if (shape != ActionUIWinUIGaugeRing) {
            shapes::Ellipse dot;
            double diameter = shape == ActionUIWinUIGaugeBar ? barDot : 2 * ringLine;
            dot.Width(diameter);
            dot.Height(diameter);
            dot.Fill(accent);
            canvas.Children().Append(dot);
        }
        // Drawn again at each size; weak, so the handler does not keep the canvas alive.
        winrt::weak_ref<muxc::Canvas> weak = canvas;
        canvas.SizeChanged([weak](auto &&, auto &&) {
            // Nothing may leave an event handler: XAML would end the app.
            try {
                if (muxc::Canvas strong = weak.get()) {
                    redraw(strong);
                }
            } catch (...) {
            }
        });
        return toObject(canvas);
    });
}

bool actionUIWinUIGaugeDrawingSetFraction(ActionUIWinUIObject *drawing, double fraction) {
    return guarded("gauge drawing set fraction", [&]() {
        muxc::Canvas canvas = objectAs<muxc::Canvas>(drawing, L"Canvas");
        wfc::PropertySet state = canvas.Tag().try_as<wfc::PropertySet>();
        if (state == nullptr) {
            return fail("gauge drawing set fraction", "the canvas is no gauge drawing");
        }
        state.Insert(L"fraction", winrt::box_value(fraction));
        redraw(canvas);
        return true;
    });
}

} // extern "C"

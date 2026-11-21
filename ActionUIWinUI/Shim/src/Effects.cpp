// Effects.cpp - what an element's box does to what it draws without changing its layout: a 2D transform
// (an offset, a rotation and a scale, composed by the caller) and a clip to a shape (clipShape), on the
// element's composition visual.

#include "ShimInternal.h"

#include <cmath>

#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.Foundation.Numerics.h>

using namespace actionui_winui;

namespace {

namespace composition = winrt::Microsoft::UI::Composition;
namespace numerics = winrt::Windows::Foundation::Numerics;

bool finite(std::initializer_list<double> values) {
    for (double value : values) {
        if (!std::isfinite(value)) {
            return false;
        }
    }
    return true;
}

} // namespace

extern "C" {

bool actionUIWinUIElementSetRenderMatrix(ActionUIWinUIObject *element, double m11, double m12, double m21, double m22,
                                         double offsetX, double offsetY) {
    return guarded("element set render matrix", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (!finite({m11, m12, m21, m22, offsetX, offsetY})) {
            return fail("element set render matrix", "the matrix is not made of numbers");
        }
        bool identity = m11 == 1 && m12 == 0 && m21 == 0 && m22 == 1 && offsetX == 0 && offsetY == 0;
        // The element's own transform, not RenderTransform's getter: with none set, that returns a
        // default identity MatrixTransform the element does not draw with, so a matrix written to it
        // moves nothing.
        wf::IInspectable local = typed.ReadLocalValue(mux::UIElement::RenderTransformProperty());
        bool set = local != nullptr && local != mux::DependencyProperty::UnsetValue();
        mux::Media::MatrixTransform transform = set ? local.try_as<mux::Media::MatrixTransform>() : nullptr;
        if (identity) {
            if (set) {
                typed.ClearValue(mux::UIElement::RenderTransformProperty());
            }
            return true;
        }
        mux::Media::Matrix wanted{m11, m12, m21, m22, offsetX, offsetY};
        if (transform == nullptr) {
            transform = mux::Media::MatrixTransform();
            transform.Matrix(wanted);
            typed.RenderTransform(transform);
            return true;
        }
        mux::Media::Matrix current = transform.Matrix();
        // Set only when it changed: an arrange sets it, and must not redraw for nothing.
        if (current.M11 != m11 || current.M12 != m12 || current.M21 != m21 || current.M22 != m22 ||
            current.OffsetX != offsetX || current.OffsetY != offsetY) {
            transform.Matrix(wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetClipShape(ActionUIWinUIObject *element, ActionUIWinUIClipShapeKind kind, double width,
                                      double height, double radiusX, double radiusY) {
    return guarded("element set clip shape", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        composition::Visual visual = mux::Hosting::ElementCompositionPreview::GetElementVisual(typed);
        if (kind == ActionUIWinUIClipShapeNone) {
            if (visual.Clip() != nullptr) {
                visual.Clip(nullptr);
            }
            return true;
        }
        if (!finite({width, height, radiusX, radiusY}) || width < 0 || height < 0) {
            return fail("element set clip shape", "the size is not a number of pixels");
        }
        composition::Compositor compositor = visual.Compositor();
        float w = static_cast<float>(width);
        float h = static_cast<float>(height);
        composition::CompositionGeometry geometry{nullptr};
        switch (kind) {
        case ActionUIWinUIClipShapeCircle: {
            // The largest circle in the frame, centered, as SwiftUI's Circle.
            float radius = std::fmin(w, h) / 2;
            composition::CompositionEllipseGeometry ellipse = compositor.CreateEllipseGeometry();
            ellipse.Center(numerics::float2{w / 2, h / 2});
            ellipse.Radius(numerics::float2{radius, radius});
            geometry = ellipse;
            break;
        }
        case ActionUIWinUIClipShapeEllipse: {
            composition::CompositionEllipseGeometry ellipse = compositor.CreateEllipseGeometry();
            ellipse.Center(numerics::float2{w / 2, h / 2});
            ellipse.Radius(numerics::float2{w / 2, h / 2});
            geometry = ellipse;
            break;
        }
        case ActionUIWinUIClipShapeRectangle:
        case ActionUIWinUIClipShapeRoundedRectangle: {
            composition::CompositionRoundedRectangleGeometry rounded = compositor.CreateRoundedRectangleGeometry();
            rounded.Size(numerics::float2{w, h});
            float rx = kind == ActionUIWinUIClipShapeRectangle ? 0 : std::fmax(static_cast<float>(radiusX), 0.0f);
            float ry = kind == ActionUIWinUIClipShapeRectangle ? 0 : std::fmax(static_cast<float>(radiusY), 0.0f);
            // A corner too big for the size shrinks keeping its proportions, as SwiftUI's RoundedRectangle
            // (20 by 50 in 64 by 40 is drawn 8 by 20), not each axis on its own.
            float fit = 1;
            if (rx > w / 2) {
                fit = std::fmin(fit, (w / 2) / rx);
            }
            if (ry > h / 2) {
                fit = std::fmin(fit, (h / 2) / ry);
            }
            rounded.CornerRadius(numerics::float2{rx * fit, ry * fit});
            geometry = rounded;
            break;
        }
        default:
            return fail("element set clip shape", "unknown clip shape");
        }
        visual.Clip(compositor.CreateGeometricClip(geometry));
        return true;
    });
}

} // extern "C"

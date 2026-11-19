// Shapes.cpp - WinUI shapes for ActionUI's Rectangle, RoundedRectangle, Ellipse, Circle and Capsule:
// each fills the size it is arranged in, as SwiftUI's shapes fill their frame. A WinUI shape draws
// its stroke inside that size; the caller arranges it half a stroke larger on every side, so the
// stroke is centered on the outline as SwiftUI's is.

#include "ShimInternal.h"

#include <cmath>

#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

namespace shapes = winrt::Microsoft::UI::Xaml::Shapes;
namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIShapeCreate(ActionUIWinUIShapeKind kind) {
    return guardedObject("shape create", [&]() -> ActionUIWinUIObject * {
        switch (kind) {
        case ActionUIWinUIShapeRectangle:
        case ActionUIWinUIShapeRoundedRectangle:
        case ActionUIWinUIShapeCapsule: {
            // Rounded by the caller (actionUIWinUIShapeSetCornerRadius), which knows the shape's
            // frame: SwiftUI clamps a radius to half the shorter side, WinUI each axis on its own.
            shapes::Rectangle rectangle;
            rectangle.Stretch(media::Stretch::Fill);
            return toObject(rectangle);
        }
        case ActionUIWinUIShapeEllipse: {
            shapes::Ellipse ellipse;
            ellipse.Stretch(media::Stretch::Fill);
            return toObject(ellipse);
        }
        case ActionUIWinUIShapeCircle: {
            // An ellipse that fills the size it is given: its caller arranges it in a square (the
            // largest one in the circle's frame, centered), as SwiftUI's Circle. A Uniform stretch
            // with centered alignment draws nothing: WinUI then arranges it at its desired size, 0.
            shapes::Ellipse circle;
            circle.Stretch(media::Stretch::Fill);
            return toObject(circle);
        }
        }
        fail("shape create", "unknown shape kind");
        return nullptr;
    });
}

bool actionUIWinUIShapeSetCornerRadius(ActionUIWinUIObject *shape, double radius) {
    return guarded("shape set corner radius", [&]() {
        shapes::Rectangle rectangle = objectAs<shapes::Rectangle>(shape, L"Rectangle");
        double value = std::isfinite(radius) && radius > 0 ? radius : 0.0;
        if (rectangle.RadiusX() != value || rectangle.RadiusY() != value) {
            rectangle.RadiusX(value);
            rectangle.RadiusY(value);
        }
        return true;
    });
}

bool actionUIWinUIShapeSetStrokeThickness(ActionUIWinUIObject *shape, double thickness) {
    return guarded("shape set stroke thickness", [&]() {
        shapes::Shape typed = objectAs<shapes::Shape>(shape, L"Shape");
        double value = std::isfinite(thickness) && thickness > 0 ? thickness : 0.0;
        if (typed.StrokeThickness() != value) {
            typed.StrokeThickness(value);
        }
        return true;
    });
}

} // extern "C"

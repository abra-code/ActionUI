// Marks.cpp - the yellow and black mark a host puts above a window's content (WindowSetTopBar): a yellow
// band, bright at the top and darker at the bottom like a bent plastic tape, with black notches along its
// top edge that lean like a backslash; as a line, black stripes across its whole height. The sizes and
// colors are those of actionui-mcp's mark on macOS and Linux. The notches are drawn again for each width,
// so the mark follows the window as it resizes.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

namespace actionui_winui {

namespace {

namespace shapes = winrt::Microsoft::UI::Xaml::Shapes;
namespace media = winrt::Microsoft::UI::Xaml::Media;

// The strip's notches, in proportion to the 12-point strip: as deep as 0.4 of it, 0.8 wide, 2.1 apart.
// The line's stripes have the same width and spacing and lean at 45 degrees across its whole height.
constexpr double notchDepth = 12 * 0.4;
constexpr double notchWidth = 12 * 0.8;
constexpr double notchSpacing = 12 * 2.1;

winrt::Windows::UI::Color rgb(uint8_t red, uint8_t green, uint8_t blue) {
    return winrt::Windows::UI::Color{255, red, green, blue};
}

// The parallelograms along the top edge, `depth` deep, across `width`.
media::PathGeometry notches(double width, double depth) {
    media::PathGeometry geometry;
    for (double x = -depth - notchSpacing; x < width; x += notchSpacing) {
        media::PathFigure figure;
        figure.StartPoint(wf::Point{static_cast<float>(x), 0});
        figure.IsClosed(true);
        figure.IsFilled(true);
        for (auto point : {wf::Point{static_cast<float>(x + notchWidth), 0},
                           wf::Point{static_cast<float>(x + depth + notchWidth), static_cast<float>(depth)},
                           wf::Point{static_cast<float>(x + depth), static_cast<float>(depth)}}) {
            media::LineSegment segment;
            segment.Point(point);
            figure.Segments().Append(segment);
        }
        geometry.Figures().Append(figure);
    }
    return geometry;
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIMarkCreate(ActionUIWinUIMarkKind kind, double height) {
    return guardedObject("mark create", [&]() -> ActionUIWinUIObject * {
        if (!(height > 0 && height < 1000)) {
            fail("mark create", "the height is not a number of pixels");
            return nullptr;
        }
        muxc::Grid mark;
        mark.Height(height);
        mark.HorizontalAlignment(mux::HorizontalAlignment::Stretch);
        // Dark text and light controls on the yellow, in light and dark mode alike.
        mark.RequestedTheme(mux::ElementTheme::Light);
        media::LinearGradientBrush yellow;
        yellow.StartPoint(wf::Point{0, 0});
        yellow.EndPoint(wf::Point{0, 1});
        media::GradientStop top;
        top.Color(rgb(252, 240, 97));
        top.Offset(0);
        media::GradientStop bottom;
        bottom.Color(rgb(216, 185, 74));
        bottom.Offset(1);
        yellow.GradientStops().Append(top);
        yellow.GradientStops().Append(bottom);
        mark.Background(yellow);
        shapes::Path path;
        path.Fill(media::SolidColorBrush(rgb(8, 8, 9)));
        path.IsHitTestVisible(false);
        path.VerticalAlignment(mux::VerticalAlignment::Top);
        path.HorizontalAlignment(mux::HorizontalAlignment::Left);
        mark.Children().Append(path);
        double depth = kind == ActionUIWinUIMarkLine ? height : notchDepth;
        // Clipped to the band: the first and last notches start and end past its edges.
        mark.SizeChanged([depth](wf::IInspectable const &sender, mux::SizeChangedEventArgs const &args) {
            try {
                muxc::Grid grid = sender.as<muxc::Grid>();
                double width = args.NewSize().Width;
                grid.Children().GetAt(0).as<shapes::Path>().Data(notches(width, depth));
                media::RectangleGeometry clip;
                clip.Rect(wf::Rect{0, 0, args.NewSize().Width, args.NewSize().Height});
                grid.Clip(clip);
            } catch (...) {
            }
        });
        return toObject(mark);
    });
}

bool actionUIWinUIMarkSetRow(ActionUIWinUIObject *mark, ActionUIWinUIObject *row) {
    return guarded("mark set row", [&]() {
        muxc::Grid grid = objectAs<muxc::Grid>(mark, L"Grid");
        mux::FrameworkElement element{nullptr};
        if (row != nullptr) {
            element = objectAs<mux::FrameworkElement>(row, L"FrameworkElement");
        }
        while (grid.Children().Size() > 1) {
            grid.Children().RemoveAt(grid.Children().Size() - 1);
        }
        if (element != nullptr) {
            // Under the notches, in the band's lower part.
            element.VerticalAlignment(mux::VerticalAlignment::Bottom);
            element.Height(std::max(grid.Height() - notchDepth, 0.0));
            grid.Children().Append(element);
        }
        return true;
    });
}

} // extern "C"

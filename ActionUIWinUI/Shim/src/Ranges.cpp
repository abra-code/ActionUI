// Ranges.cpp - the controls that show a number in a range: Slider, for ActionUI's Slider; ProgressBar and
// ProgressRing, for ActionUI's ProgressView.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUISliderCreate(void) {
    return guardedObject("slider create", []() {
        muxc::Slider slider;
        // No value beside the thumb while dragging, as SwiftUI's Slider shows none.
        slider.IsThumbToolTipEnabled(false);
        slider.TickPlacement(muxc::Primitives::TickPlacement::None);
        // 0...1, continuous, as the header promises (WinUI's Slider starts at 0...100 in steps of 1).
        slider.Maximum(1);
        slider.StepFrequency(1.0 / 10000);
        slider.SmallChange(1.0 / 100);
        slider.LargeChange(1.0 / 10);
        return toObject(slider);
    });
}

bool actionUIWinUISliderSetRange(ActionUIWinUIObject *slider, double minimum, double maximum, double step) {
    return guarded("slider set range", [&]() {
        if (!(minimum <= maximum)) {
            return fail("slider set range", "the minimum is past the maximum");
        }
        muxc::Slider typed = objectAs<muxc::Slider>(slider, L"Slider");
        double span = maximum - minimum;
        // Maximum first when the range moves up, Minimum first when it moves down: WinUI keeps Maximum
        // at least Minimum, and moving one past the other would move it too.
        if (minimum > typed.Maximum()) {
            typed.Maximum(maximum);
            typed.Minimum(minimum);
        } else {
            typed.Minimum(minimum);
            typed.Maximum(maximum);
        }
        // Without a step the slider is continuous: a ten-thousandth of the range (WinUI snaps to
        // StepFrequency, 1 by default). The arrow keys move by the step, else a hundredth.
        double frequency = step > 0 ? step : (span > 0 ? span / 10000 : 1);
        typed.StepFrequency(frequency);
        typed.SmallChange(step > 0 ? step : (span > 0 ? span / 100 : 1));
        // At least one step, as on Linux: a tenth of the range below the step would snap back to where it
        // started (0...10 by 5: a change of 1 rounds back to 0).
        typed.LargeChange(span > 0 ? (step > span / 10 ? step : span / 10) : 1);
        // A tick below for each step, as macOS draws them; WinUI makes an element per tick, so none past
        // 200 steps, where macOS's ticks already run together into a line.
        bool ticks = step > 0 && span > 0 && span / step <= 200;
        if (ticks) {
            typed.TickFrequency(step);
        }
        typed.TickPlacement(ticks ? muxc::Primitives::TickPlacement::BottomRight : muxc::Primitives::TickPlacement::None);
        return true;
    });
}

bool actionUIWinUISliderSetValue(ActionUIWinUIObject *slider, double value) {
    return guarded("slider set value", [&]() {
        muxc::Slider typed = objectAs<muxc::Slider>(slider, L"Slider");
        if (typed.Value() != value) {
            typed.Value(value);
        }
        return true;
    });
}

double actionUIWinUISliderGetValue(ActionUIWinUIObject *slider) {
    double value = 0;
    guarded("slider get value", [&]() {
        value = objectAs<muxc::Slider>(slider, L"Slider").Value();
        return true;
    });
    return value;
}

bool actionUIWinUISliderOnValueChanged(ActionUIWinUIObject *slider, ActionUIWinUICallback handler, void *context,
                                       ActionUIWinUICallback destroyContext) {
    return registerHandler("slider on value changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::Slider>(slider, L"Slider")
                                   .ValueChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

ActionUIWinUIObject *actionUIWinUIProgressCreate(ActionUIWinUIProgressKind kind) {
    return guardedObject("progress create", [&]() -> ActionUIWinUIObject * {
        switch (kind) {
        case ActionUIWinUIProgressBar: {
            muxc::ProgressBar bar;
            bar.IsIndeterminate(true);
            return toObject(bar);
        }
        case ActionUIWinUIProgressRing: {
            muxc::ProgressRing ring;
            ring.IsIndeterminate(true);
            ring.Width(32);
            ring.Height(32);
            return toObject(ring);
        }
        }
        fail("progress create", "an unknown kind");
        return nullptr;
    });
}

bool actionUIWinUIProgressSet(ActionUIWinUIObject *progress, bool determinate, double value, double total) {
    return guarded("progress set", [&]() {
        if (determinate && !(total > 0 && value >= 0 && value <= total)) {
            return fail("progress set", "the progress is not within 0 and a positive total");
        }
        wf::IInspectable object = objectAs<wf::IInspectable>(progress, L"IInspectable");
        if (auto bar = object.try_as<muxc::ProgressBar>()) {
            if (determinate) {
                bar.Minimum(0);
                bar.Maximum(total);
                bar.Value(value);
            }
            if (bar.IsIndeterminate() == determinate) {
                bar.IsIndeterminate(!determinate);
            }
            return true;
        }
        muxc::ProgressRing ring = objectAs<muxc::ProgressRing>(progress, L"ProgressBar or ProgressRing");
        if (determinate) {
            ring.Minimum(0);
            ring.Maximum(total);
            ring.Value(value);
        }
        if (ring.IsIndeterminate() == determinate) {
            ring.IsIndeterminate(!determinate);
        }
        return true;
    });
}

} // extern "C"

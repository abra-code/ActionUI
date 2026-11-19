// Dates.cpp - the controls that pick a date or a time for ActionUI's DatePicker: CalendarDatePicker (a field
// that opens a calendar), CalendarView (a calendar shown inline) and TimePicker. Days cross the C API as
// local calendar days (year, month, day in the Gregorian calendar and the system's time zone) and times as
// minutes after midnight, so neither side converts between time zones.

#include "ShimInternal.h"

#include <chrono>

#include <winrt/Windows.Globalization.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>

using namespace actionui_winui;

namespace {

namespace globalization = winrt::Windows::Globalization;

// A Gregorian calendar in the system's time zone (the user's default calendar may be another one).
globalization::Calendar gregorian() {
    globalization::Calendar calendar;
    calendar.ChangeCalendarSystem(globalization::CalendarIdentifiers::Gregorian());
    calendar.ChangeClock(globalization::ClockIdentifiers::TwentyFourHour());
    return calendar;
}

// Noon of the local day: far from a daylight saving change, which happens at night.
wf::DateTime dayTime(int32_t year, int32_t month, int32_t day) {
    globalization::Calendar calendar = gregorian();
    // Day 1 first, which every month has: today's day (the 31st, or February 29) need not exist in the
    // month and year set next.
    calendar.Day(1);
    calendar.Year(year);
    calendar.Month(month);
    calendar.Day(day);
    calendar.Period(calendar.FirstPeriodInThisDay());
    calendar.Hour(12);
    calendar.Minute(0);
    calendar.Second(0);
    calendar.Nanosecond(0);
    return calendar.GetDateTime();
}

void localDay(wf::DateTime const &time, int32_t *year, int32_t *month, int32_t *day) {
    globalization::Calendar calendar = gregorian();
    calendar.SetDateTime(time);
    *year = calendar.Year();
    *month = calendar.Month();
    *day = calendar.Day();
}

// WinUI's own limits, a hundred years either side of today, for a picker whose range is taken away.
void defaultLimits(wf::DateTime *minimum, wf::DateTime *maximum) {
    globalization::Calendar calendar = gregorian();
    calendar.SetToNow();
    calendar.AddYears(-100);
    *minimum = calendar.GetDateTime();
    calendar.AddYears(200);
    *maximum = calendar.GetDateTime();
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIDateControlCreate(ActionUIWinUIDateKind kind) {
    return guardedObject("date control create", [&]() -> ActionUIWinUIObject * {
        switch (kind) {
        case ActionUIWinUIDateField: {
            muxc::CalendarDatePicker picker;
            return toObject(picker);
        }
        case ActionUIWinUIDateCalendar: {
            muxc::CalendarView calendar;
            calendar.SelectionMode(muxc::CalendarViewSelectionMode::Single);
            return toObject(calendar);
        }
        case ActionUIWinUIDateTime: {
            muxc::TimePicker picker;
            return toObject(picker);
        }
        }
        fail("date control create", "an unknown kind");
        return nullptr;
    });
}

bool actionUIWinUIDateControlSetDay(ActionUIWinUIObject *control, int32_t year, int32_t month, int32_t day) {
    return guarded("date control set day", [&]() {
        wf::DateTime wanted = dayTime(year, month, day);
        int32_t shownYear = 0;
        int32_t shownMonth = 0;
        int32_t shownDay = 0;
        if (auto picker = objectAs<wf::IInspectable>(control, L"IInspectable").try_as<muxc::CalendarDatePicker>()) {
            auto shown = picker.Date();
            if (shown != nullptr) {
                localDay(shown.Value(), &shownYear, &shownMonth, &shownDay);
            }
            if (shown == nullptr || shownYear != year || shownMonth != month || shownDay != day) {
                picker.Date(wanted);
            }
            return true;
        }
        muxc::CalendarView calendar = objectAs<muxc::CalendarView>(control, L"CalendarView or CalendarDatePicker");
        auto selected = calendar.SelectedDates();
        if (selected.Size() == 1) {
            localDay(selected.GetAt(0), &shownYear, &shownMonth, &shownDay);
            if (shownYear == year && shownMonth == month && shownDay == day) {
                return true;
            }
        }
        selected.Clear();
        selected.Append(wanted);
        calendar.SetDisplayDate(wanted);
        return true;
    });
}

bool actionUIWinUIDateControlGetDay(ActionUIWinUIObject *control, int32_t *year, int32_t *month, int32_t *day) {
    return guarded("date control get day", [&]() {
        if (auto picker = objectAs<wf::IInspectable>(control, L"IInspectable").try_as<muxc::CalendarDatePicker>()) {
            auto shown = picker.Date();
            if (shown == nullptr) {
                return fail("date control get day", "no day is picked");
            }
            localDay(shown.Value(), year, month, day);
            return true;
        }
        auto selected = objectAs<muxc::CalendarView>(control, L"CalendarView or CalendarDatePicker").SelectedDates();
        if (selected.Size() == 0) {
            return fail("date control get day", "no day is picked");
        }
        localDay(selected.GetAt(0), year, month, day);
        return true;
    });
}

bool actionUIWinUIDateControlSetRange(ActionUIWinUIObject *control, bool limited, int32_t startYear, int32_t startMonth,
                                      int32_t startDay, int32_t endYear, int32_t endMonth, int32_t endDay) {
    return guarded("date control set range", [&]() {
        wf::DateTime minimum;
        wf::DateTime maximum;
        if (limited) {
            minimum = dayTime(startYear, startMonth, startDay);
            maximum = dayTime(endYear, endMonth, endDay);
        } else {
            defaultLimits(&minimum, &maximum);
        }
        if (auto picker = objectAs<wf::IInspectable>(control, L"IInspectable").try_as<muxc::CalendarDatePicker>()) {
            picker.MinDate(minimum);
            picker.MaxDate(maximum);
            return true;
        }
        muxc::CalendarView calendar = objectAs<muxc::CalendarView>(control, L"CalendarView or CalendarDatePicker");
        calendar.MinDate(minimum);
        calendar.MaxDate(maximum);
        return true;
    });
}

bool actionUIWinUIDateControlSetTime(ActionUIWinUIObject *control, int32_t minutes) {
    return guarded("date control set time", [&]() {
        muxc::TimePicker picker = objectAs<muxc::TimePicker>(control, L"TimePicker");
        wf::TimeSpan wanted = std::chrono::minutes(minutes);
        if (picker.Time() != wanted) {
            picker.Time(wanted);
        }
        return true;
    });
}

int32_t actionUIWinUIDateControlGetTime(ActionUIWinUIObject *control) {
    int32_t minutes = -1;
    guarded("date control get time", [&]() {
        wf::TimeSpan time = objectAs<muxc::TimePicker>(control, L"TimePicker").Time();
        minutes = static_cast<int32_t>(std::chrono::duration_cast<std::chrono::minutes>(time).count());
        return true;
    });
    return minutes;
}

bool actionUIWinUIDateControlOnChanged(ActionUIWinUIObject *control, ActionUIWinUICallback handler, void *context,
                                       ActionUIWinUICallback destroyContext) {
    return registerHandler("date control on changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               wf::IInspectable object = objectAs<wf::IInspectable>(control, L"IInspectable");
                               if (auto picker = object.try_as<muxc::CalendarDatePicker>()) {
                                   picker.DateChanged([holder](auto &&, auto &&) { holder->fire(); });
                               } else if (auto calendar = object.try_as<muxc::CalendarView>()) {
                                   calendar.SelectedDatesChanged([holder](auto &&, auto &&) { holder->fire(); });
                               } else {
                                   objectAs<muxc::TimePicker>(control, L"TimePicker")
                                       .TimeChanged([holder](auto &&, auto &&) { holder->fire(); });
                               }
                           });
}

} // extern "C"

// The Rust host for Examples/TemperatureConverter: the same JSON the Swift, Android and
// web hosts use, compiled into the program.
//
//   cargo run --example temperature_converter

use actionui::{App, Window};

const UI: &str = include_str!("../../../Examples/TemperatureConverter/shared/TemperatureConverter.json");

// The element IDs in the JSON.
const INPUT: i64 = 10;
const FROM_UNIT: i64 = 20;
const TO_UNIT: i64 = 30;
const OUTPUT: i64 = 40;

fn convert(value: f64, from: &str, to: &str) -> f64 {
    let celsius = match from {
        "F" => (value - 32.0) * 5.0 / 9.0,
        "K" => value - 273.15,
        _ => value,
    };
    match to {
        "F" => celsius * 9.0 / 5.0 + 32.0,
        "K" => celsius + 273.15,
        _ => celsius,
    }
}

fn recompute(window: &Window) -> actionui::Result<()> {
    let input = window.get_string(INPUT)?.unwrap_or_default();
    // A Picker's value is the tag of the selected option, not its title.
    let from = window.get_string(FROM_UNIT)?.unwrap_or_else(|| "C".to_string());
    let to = window.get_string(TO_UNIT)?.unwrap_or_else(|| "F".to_string());

    let output = match input.trim().parse::<f64>() {
        Ok(value) => format!("{:.2}", convert(value, &from, &to)),
        Err(_) => String::new(),
    };
    window.set_string(OUTPUT, &output)
}

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    app.set_name("Temperature Converter")?;

    // The JSON fires this one action when the number or either unit changes.
    app.on_action("temp.recompute", |action| {
        if let Err(error) = recompute(&action.window) {
            eprintln!("recompute failed: {error}");
        }
    });

    app.present_window_from_json(UI, Some("Temperature Converter"))?;
    app.run()
}

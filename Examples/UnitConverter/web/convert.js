//  UnitConverter - the shared brain, JS port.
//
//  This is a line-for-line port of shared/c/convert.c. Apple and Android compile
//  the C file itself; the web runtime is JS-only, so it needs a JS twin. Keep the
//  two in lockstep: same factor tables, same affine temperature formulas, same
//  results. (STRETCH, documented in the README: compile convert.c to WASM with
//  emscripten and call that instead, deleting this file - emscripten was not
//  installed in the authoring environment, so the JS port ships today.)

// Category indices (match AuiCategory in convert.h).
export const AUI_CAT_LENGTH = 0;
export const AUI_CAT_MASS = 1;
export const AUI_CAT_TEMPERATURE = 2;

// Meters per one length unit (match kLengthToMeters in convert.c).
const LENGTH_TO_METERS = [
  1.0,        // m
  0.01,       // cm
  1000.0,     // km
  0.0254,     // in
  0.3048,     // ft
  1609.344,   // mi
];

// Kilograms per one mass unit (match kMassToKilograms in convert.c).
const MASS_TO_KILOGRAMS = [
  1.0,            // kg
  0.001,          // g
  0.45359237,     // lb
  0.028349523125, // oz
];

function convertFactor(table, from, to, value) {
  if (from < 0 || from >= table.length || to < 0 || to >= table.length) {
    return value;
  }
  const base = value * table[from];
  return base / table[to];
}

function convertTemperature(from, to, value) {
  if (from < 0 || from >= 3 || to < 0 || to >= 3) {
    return value;
  }
  // to Celsius
  let celsius;
  if (from === 1) celsius = (value - 32.0) * 5.0 / 9.0; // F
  else if (from === 2) celsius = value - 273.15;        // K
  else celsius = value;                                 // C
  // from Celsius
  if (to === 1) return celsius * 9.0 / 5.0 + 32.0;      // F
  if (to === 2) return celsius + 273.15;                // K
  return celsius;                                       // C
}

// The one entry point, mirroring aui_convert(category, fromUnit, toUnit, value).
export function auiConvert(category, fromUnit, toUnit, value) {
  switch (category) {
    case AUI_CAT_LENGTH:
      return convertFactor(LENGTH_TO_METERS, fromUnit, toUnit, value);
    case AUI_CAT_MASS:
      return convertFactor(MASS_TO_KILOGRAMS, fromUnit, toUnit, value);
    case AUI_CAT_TEMPERATURE:
      return convertTemperature(fromUnit, toUnit, value);
    default:
      return value;
  }
}

/*
 * UnitConverter - the shared C brain (implementation).
 *
 * This single translation unit is compiled UNCHANGED on Apple (Clang C module
 * imported by Swift) and Android (NDK/CMake, reached over JNI). web/convert.js
 * is a line-for-line JS port of the same math.
 *
 * Strategy: each non-temperature category has a factor table giving the size of
 * one unit in that category's base unit (meters for length, kilograms for mass).
 * Converting is then "to base, then from base": value * factor[from] / factor[to].
 * Temperature is affine (offsets, not just scales), so it converts through
 * Celsius as the pivot.
 */

#include "convert.h"

/* Meters per one length unit. */
static const double kLengthToMeters[AUI_LEN_COUNT] = {
    1.0,        /* AUI_LEN_M  */
    0.01,       /* AUI_LEN_CM */
    1000.0,     /* AUI_LEN_KM */
    0.0254,     /* AUI_LEN_IN (exact) */
    0.3048,     /* AUI_LEN_FT (exact, 12 in) */
    1609.344    /* AUI_LEN_MI (exact, 5280 ft) */
};

/* Kilograms per one mass unit. */
static const double kMassToKilograms[AUI_MASS_COUNT] = {
    1.0,            /* AUI_MASS_KG */
    0.001,          /* AUI_MASS_G  */
    0.45359237,     /* AUI_MASS_LB (exact, international pound) */
    0.028349523125  /* AUI_MASS_OZ (exact, lb / 16) */
};

/* Factor-table conversion shared by length and mass. */
static double convert_factor(const double *table, int count, int from, int to, double value) {
    if (from < 0 || from >= count || to < 0 || to >= count) {
        return value;
    }
    /* value in base units, then back out into the target unit. */
    double base = value * table[from];
    return base / table[to];
}

/* Affine temperature conversion through Celsius. */
static double convert_temperature(int from, int to, double value) {
    if (from < 0 || from >= AUI_TEMP_COUNT || to < 0 || to >= AUI_TEMP_COUNT) {
        return value;
    }
    /* to Celsius */
    double celsius;
    switch (from) {
        case AUI_TEMP_F: celsius = (value - 32.0) * 5.0 / 9.0; break;
        case AUI_TEMP_K: celsius = value - 273.15;             break;
        default:         celsius = value;                      break; /* AUI_TEMP_C */
    }
    /* from Celsius */
    switch (to) {
        case AUI_TEMP_F: return celsius * 9.0 / 5.0 + 32.0;
        case AUI_TEMP_K: return celsius + 273.15;
        default:         return celsius; /* AUI_TEMP_C */
    }
}

double aui_convert(int category, int fromUnit, int toUnit, double value) {
    switch (category) {
        case AUI_CAT_LENGTH:
            return convert_factor(kLengthToMeters, AUI_LEN_COUNT, fromUnit, toUnit, value);
        case AUI_CAT_MASS:
            return convert_factor(kMassToKilograms, AUI_MASS_COUNT, fromUnit, toUnit, value);
        case AUI_CAT_TEMPERATURE:
            return convert_temperature(fromUnit, toUnit, value);
        default:
            return value;
    }
}

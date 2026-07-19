/*
 * UnitConverter - the shared C brain (header).
 *
 * ONE C file (convert.c) holds all conversion logic and is compiled UNCHANGED
 * on every native platform:
 *   - Apple (iOS + macOS): compiled as a Clang C module, imported into Swift.
 *   - Android: compiled by the NDK via CMake, reached from Kotlin over JNI.
 *   - Web: a hand-kept JS port (web/convert.js) mirrors this file exactly;
 *     compiling this same .c to WASM with emscripten is the documented next step.
 *
 * Identical numeric results everywhere, because Apple and Android run the very
 * same translation unit.
 *
 * Public API (the only symbol hosts call):
 *     double aui_convert(int category, int fromUnit, int toUnit, double value);
 *
 * `category`, `fromUnit`, and `toUnit` are the small integer enums below. Unit
 * indices are LOCAL to a category (length unit 0 is meters; mass unit 0 is
 * kilograms; ...). An out-of-range argument returns the input value unchanged.
 */

#ifndef AUI_CONVERT_H
#define AUI_CONVERT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Conversion categories. */
typedef enum {
    AUI_CAT_LENGTH      = 0,
    AUI_CAT_MASS        = 1,
    AUI_CAT_TEMPERATURE = 2,
    AUI_CAT_COUNT       = 3
} AuiCategory;

/* Length units (factor table; each value is "how many meters in one unit"). */
typedef enum {
    AUI_LEN_M  = 0,  /* meter      */
    AUI_LEN_CM = 1,  /* centimeter */
    AUI_LEN_KM = 2,  /* kilometer  */
    AUI_LEN_IN = 3,  /* inch       */
    AUI_LEN_FT = 4,  /* foot       */
    AUI_LEN_MI = 5,  /* mile       */
    AUI_LEN_COUNT = 6
} AuiLengthUnit;

/* Mass units (factor table; each value is "how many kilograms in one unit"). */
typedef enum {
    AUI_MASS_KG = 0, /* kilogram */
    AUI_MASS_G  = 1, /* gram     */
    AUI_MASS_LB = 2, /* pound    */
    AUI_MASS_OZ = 3, /* ounce    */
    AUI_MASS_COUNT = 4
} AuiMassUnit;

/* Temperature units (affine formulas, NOT plain factors). */
typedef enum {
    AUI_TEMP_C = 0, /* Celsius    */
    AUI_TEMP_F = 1, /* Fahrenheit */
    AUI_TEMP_K = 2, /* Kelvin     */
    AUI_TEMP_COUNT = 3
} AuiTempUnit;

/*
 * Convert `value` from `fromUnit` to `toUnit` within `category`.
 * Returns `value` unchanged if any argument is out of range.
 */
double aui_convert(int category, int fromUnit, int toUnit, double value);

#ifdef __cplusplus
}
#endif

#endif /* AUI_CONVERT_H */

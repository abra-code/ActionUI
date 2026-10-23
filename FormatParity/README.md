# Format parity cases

Cases every renderer checks, so a document reads the same on every platform: Stepper's `labelFormat` (below) and Link's `url` (`link-url-cases.json`, at the end).

Stepper's `labelFormat` ("Quantity: %.0f") shows the same text on every platform. `labelformat-cases.json` checks it with examples: each case is a format, a value and the text every renderer must show, or `null` where the format is refused (and the plain value is shown instead).

- `cases` - a `format`, a `value` and the `expected` text. A `decimalSeparator` stands for the user's locale (`"."` when absent). Values JSON cannot write are strings: `"inf"`, `"-inf"`, `"nan"`, `"-0"`.
- `plain` - a `value` and the `expected` plain text (`%g`), which a refused format shows.

The rule: exactly one conversion among `d i f F e E g G` (flags `- + space # 0`, width and precision up to 4096) plus any `%%`; `%d` and `%i` truncate the value; the number is formatted as C's printf formats it in the C locale, then its decimal point is the user's decimal separator; NaN has no sign.

## Who checks them

- Apple and Linux: `ActionUITests/Core/FormatParityTests.swift` (NumberPrintf.swift, which formats with the C library).
- Android: `ActionUIAndroid/library/src/test/java/com/abracode/actionui/Helpers/NumberPrintfTest.kt` (NumberPrintf.kt).
- Web: `ActionUIWeb/test/number-printf.test.mjs` (NumberPrintf.js).

## Recording

The C library on a Mac is the reference. After adding a case, record the expected texts there, then look at the changes before committing them:

```
ACTIONUI_FORMAT_RECORD=1 swift test --filter FormatParityTests
```

Android's Gradle does not see this file as a test input: after changing it, run the Android tests with `--rerun`.

## Link URLs

`link-url-cases.json` holds a `url` and the `expected` destination for each case, as Apple's `URL(string:)` reads the text: `none` (refused: the Link shows nothing), `relative` (no scheme: shown, opens nothing) or `absolute` (a scheme: handed to the system). Linux's Foundation parses some of them differently, so Link.destination in Core states the rule as plain string checks, and Android and the web follow it.

- Apple: `ActionUITests/Core/LinkParityTests.swift` checks URL(string:) and Link.destination; on Linux, Link.destination.
- Android: `ActionUIAndroid/library/src/test/java/com/abracode/actionui/Views/LinkTest.kt`.
- Web: `ActionUIWeb/test/link.test.mjs`.

Recording takes the expected kinds from URL(string:) on a Mac (a new case can have `"expected": null` until then); as above, look at the changes and rerun Android with `--rerun`:

```
ACTIONUI_FORMAT_RECORD=1 swift test --filter LinkParityTests
```

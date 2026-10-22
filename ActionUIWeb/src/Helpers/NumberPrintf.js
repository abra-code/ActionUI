// NumberPrintf.js — a printf format with one number in it, as Stepper's labelFormat is
// ("Quantity: %.0f"), with the rule every ActionUI renderer follows (Apple and Linux:
// NumberPrintf.swift; Android: NumberPrintf.kt; all check FormatParity/labelformat-cases.json):
//
// - Accepted: text with exactly one conversion among d i f F e E g G, with optional flags
//   (- + space # 0), width and precision, plus any number of "%%". Anything else ("%s",
//   "%d %d", "*" widths, length modifiers, the "'" grouping flag) is refused, as is a width or
//   precision over 4096.
// - An integer conversion gets the value truncated toward zero; a value no 64-bit integer holds
//   (infinite, NaN, beyond its range) is refused.
// - The number is formatted as C's printf formats it in the C locale (toFixed rounds ties up and
//   JavaScript has no %g, so this formats from the double's exact decimal value and rounds half to
//   even, as C does), then its decimal point is the system's decimal separator. The text around
//   it is kept as written.
// - A refused format shows the plain value: "%g", with the system's decimal separator.
// - NaN has no sign, whatever the flags (C libraries differ there).

const LONG_MIN = -(2n ** 63n);
const LONG_MAX = 2n ** 63n - 1n;
// The largest width or precision accepted, as on every platform: larger ones would make texts no
// renderer can build alike (a JavaScript string ends near 2^29 characters).
const MAX_LENGTH = 4096;

/** `format` with `value` in it, or null when the format is refused. */
export function formatNumber(format, value, decimalSeparator = systemDecimalSeparator()) {
    const parsed = parseFormat(format);
    if (parsed === null) return null;
    const number = formatConversion(parsed, value);
    if (number === null) return null;
    return parsed.prefix + localized(number, decimalSeparator) + parsed.suffix;
}

/** The value as "%g" prints it, with the decimal separator: what a refused format shows instead. */
export function plainNumber(value, decimalSeparator = systemDecimalSeparator()) {
    const parsed = { prefix: "", flags: "", width: null, precision: null, conversion: "g", suffix: "" };
    return localized(formatConversion(parsed, value) ?? "", decimalSeparator);
}

/** The decimal separator of the user's locale. */
export function systemDecimalSeparator() {
    try {
        const part = new Intl.NumberFormat().formatToParts(1.5).find((p) => p.type === "decimal");
        return part ? part.value : ".";
    } catch {
        return ".";
    }
}

/**
 * The format split around its one conversion ({ prefix, flags, width, precision, conversion,
 * suffix }, with "%%" as "%" in the text), or null when the format is refused.
 */
export function parseFormat(format) {
    // Code points, as the C library reads the text: a "%" is a "%" whatever comes before it.
    const points = Array.from(format);
    let prefix = "";
    let suffix = "";
    let parsed = null;
    let index = 0;
    const isDigit = (c) => c !== undefined && c >= "0" && c <= "9";
    while (index < points.length) {
        const point = points[index++];
        if (point !== "%") {
            if (parsed === null) prefix += point; else suffix += point;
            continue;
        }
        if (index >= points.length) return null;
        if (points[index] === "%") {
            if (parsed === null) prefix += "%"; else suffix += "%";
            index++;
            continue;
        }
        if (parsed !== null) return null;
        let flags = "";
        while (index < points.length && "-+ #0".includes(points[index]) && points[index].length === 1) {
            flags += points[index++];
        }
        let width = "";
        while (isDigit(points[index])) width += points[index++];
        let precision = null;
        if (points[index] === ".") {
            index++;
            let digits = "";
            while (isDigit(points[index])) digits += points[index++];
            precision = digits === "" ? 0 : Number(digits);
        }
        const conversion = points[index];
        if (conversion === undefined || !"difFeEgG".includes(conversion) || conversion.length !== 1) return null;
        index++;
        const widthValue = width === "" ? null : Number(width);
        if (widthValue > MAX_LENGTH || precision > MAX_LENGTH) return null;
        parsed = { flags, width: widthValue, precision, conversion };
    }
    if (parsed === null) return null;
    return { ...parsed, prefix, suffix };
}

/** The conversion applied to `value`, C's text in the C locale; null when refused. */
function formatConversion(parsed, value) {
    const { flags, conversion } = parsed;
    const leftAlign = flags.includes("-");
    const alternate = flags.includes("#");
    let zeroPad = flags.includes("0") && !leftAlign;
    const flagSign = flags.includes("+") ? "+" : (flags.includes(" ") ? " " : "");

    if (conversion === "d" || conversion === "i") {
        if (!Number.isFinite(value)) return null;
        const truncated = exactInteger(Math.trunc(value));
        if (truncated < LONG_MIN || truncated > LONG_MAX) return null;
        // The sign of the integer, not of the value: -0.4 is 0, which "+" shows as "+0".
        const sign = truncated < 0n ? "-" : flagSign;
        let digits = (truncated < 0n ? -truncated : truncated).toString();
        if (parsed.precision !== null) {
            zeroPad = false;
            digits = parsed.precision === 0 && truncated === 0n ? "" : digits.padStart(parsed.precision, "0");
        }
        return pad(sign, digits, parsed.width, leftAlign, zeroPad);
    }

    const negative = value < 0 || Object.is(value, -0);
    const sign = negative ? "-" : flagSign;
    let body;
    if (!Number.isFinite(value)) {
        body = Number.isNaN(value) ? "nan" : "inf";
        zeroPad = false;
    } else {
        const magnitude = exactDecimal(Math.abs(value));
        const precision = parsed.precision ?? 6;
        switch (conversion.toLowerCase()) {
        case "f": body = fixed(magnitude, precision, alternate); break;
        case "e": body = exponential(magnitude, precision, alternate); break;
        default: body = general(magnitude, precision, alternate); break;
        }
    }
    if (conversion === conversion.toUpperCase()) body = body.toUpperCase();
    // No sign for NaN, where C libraries differ.
    return pad(Number.isNaN(value) ? "" : sign, body, parsed.width, leftAlign, zeroPad);
}

/** An integral double as a BigInt. */
function exactInteger(value) {
    const { digits, scale } = exactDecimal(Math.abs(value));
    const magnitude = digits / 10n ** BigInt(scale);
    return value < 0 ? -magnitude : magnitude;
}

/** A finite double >= 0 as digits / 10^scale, exactly (a binary fraction is a finite decimal one). */
function exactDecimal(value) {
    if (value === 0) return { digits: 0n, scale: 0 };
    const view = new DataView(new ArrayBuffer(8));
    view.setFloat64(0, value);
    const high = view.getUint32(0);
    const low = view.getUint32(4);
    let exponent = (high >>> 20) & 0x7ff;
    let mantissa = (BigInt(high & 0xfffff) << 32n) | BigInt(low);
    if (exponent === 0) exponent = 1; else mantissa |= 1n << 52n;
    const power = exponent - 1075; // value = mantissa * 2^power
    if (power >= 0) return { digits: mantissa << BigInt(power), scale: 0 };
    // mantissa * 2^power = mantissa * 5^-power / 10^-power
    return { digits: mantissa * 5n ** BigInt(-power), scale: -power };
}

/** The value times 10^places, rounded half to even to an integer. */
function scaledRounded({ digits, scale }, places) {
    const shift = scale - places;
    if (shift <= 0) return digits * 10n ** BigInt(-shift);
    const divisor = 10n ** BigInt(shift);
    let quotient = digits / divisor;
    const remainder = digits % divisor;
    const twice = remainder * 2n;
    if (twice > divisor || (twice === divisor && quotient % 2n === 1n)) quotient += 1n;
    return quotient;
}

/** %f: `precision` digits after the point, rounded half to even. */
function fixed(magnitude, precision, alternate) {
    const text = scaledRounded(magnitude, precision).toString().padStart(precision + 1, "0");
    if (precision === 0) return alternate ? text + "." : text;
    return text.slice(0, text.length - precision) + "." + text.slice(text.length - precision);
}

/** The first `count` significant digits, rounded half to even, and the decimal exponent. */
function significant(magnitude, count) {
    if (magnitude.digits === 0n) return { digits: "0".repeat(count), exponent: 0 };
    let exponent = magnitude.digits.toString().length - 1 - magnitude.scale;
    let rounded = scaledRounded(magnitude, count - 1 - exponent).toString();
    if (rounded.length > count) {
        // Rounding carried into a new digit (9.995 to 10.0): one more in the exponent.
        exponent += 1;
        rounded = rounded.slice(0, count);
    }
    return { digits: rounded, exponent };
}

/** %e: one digit, `precision` digits after the point, an exponent of at least two digits. */
function exponential(magnitude, precision, alternate) {
    const { digits, exponent } = significant(magnitude, precision + 1);
    const mantissa = precision === 0 ? digits[0] + (alternate ? "." : "") : digits[0] + "." + digits.slice(1);
    return mantissa + exponentText(exponent);
}

/** %g: %e or %f by the exponent, without trailing zeros unless alternate. */
function general(magnitude, precision, alternate) {
    const p = precision === 0 ? 1 : precision;
    const { exponent } = significant(magnitude, p);
    if (exponent < p && exponent >= -4) {
        const text = fixed(magnitude, p - 1 - exponent, alternate);
        return alternate ? text : stripZeros(text);
    }
    const text = exponential(magnitude, p - 1, alternate);
    if (alternate) return text;
    const split = text.indexOf("e");
    return stripZeros(text.slice(0, split)) + text.slice(split);
}

function exponentText(exponent) {
    return "e" + (exponent < 0 ? "-" : "+") + String(Math.abs(exponent)).padStart(2, "0");
}

function stripZeros(text) {
    return text.includes(".") ? text.replace(/0+$/, "").replace(/\.$/, "") : text;
}

/** The sign and body padded to width: spaces before (after when leftAlign), or zeros after the sign. */
function pad(sign, body, width, leftAlign, zeroPad) {
    const length = sign.length + body.length;
    if (width === null || length >= width) return sign + body;
    const fill = width - length;
    if (leftAlign) return sign + body + " ".repeat(fill);
    if (zeroPad) return sign + "0".repeat(fill) + body;
    return " ".repeat(fill) + sign + body;
}

/** The number with its decimal point as `separator` (a formatted number has at most one "."). */
function localized(number, separator) {
    // A function, so a "$" in the separator is not read as a replacement pattern.
    return separator === "." ? number : number.replace(".", () => separator);
}

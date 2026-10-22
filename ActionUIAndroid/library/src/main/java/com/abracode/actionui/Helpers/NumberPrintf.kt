package com.abracode.actionui.Helpers

import java.math.BigDecimal
import java.math.BigInteger
import java.math.MathContext
import java.math.RoundingMode
import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * A printf format with one number in it, as Stepper's `labelFormat` is ("Quantity: %.0f"), with
 * the rule every ActionUI renderer follows (Apple and Linux: NumberPrintf.swift; the web:
 * NumberPrintf.js; all check FormatParity/labelformat-cases.json):
 *
 * - Accepted: text with exactly one conversion among d i f F e E g G, with optional flags
 *   (- + space # 0), width and precision, plus any number of "%%". Anything else ("%s", "%d %d",
 *   "*" widths, length modifiers, the "'" grouping flag) is refused, as is a width or precision over
 *   4096 ([MAX_LENGTH]: larger ones would make texts no renderer can build alike).
 * - An integer conversion gets the value truncated toward zero; a value no 64-bit integer holds
 *   (infinite, NaN, beyond its range) is refused.
 * - The number is formatted as C's printf formats it in the C locale (Java's String.format rounds
 *   ties up and prints %g and infinities differently, so this formats from the double's exact
 *   decimal value and rounds half to even, as C does), then its decimal point is the system's
 *   decimal separator. The text around it is kept as written.
 * - A refused format shows the plain value: "%g", with the system's decimal separator.
 * - NaN has no sign, whatever the flags (C libraries differ there).
 */
internal object NumberPrintf {
    /** A format split around its one conversion; [prefix] and [suffix] have "%%" as "%". */
    internal data class Parsed(
        val prefix: String,
        val flags: String,
        val width: Int?,
        val precision: Int?,
        val conversion: Char,
        val suffix: String,
    )

    /** [format] with [value] in it, or null when the format is refused. */
    fun format(format: String, value: Double, decimalSeparator: String = systemDecimalSeparator()): String? {
        val parsed = parse(format) ?: return null
        val number = formatNumber(parsed, value) ?: return null
        return parsed.prefix + localized(number, decimalSeparator) + parsed.suffix
    }

    /** The value as "%g" prints it, with the decimal separator: what a refused format shows instead. */
    fun plain(value: Double, decimalSeparator: String = systemDecimalSeparator()): String =
        localized(formatNumber(Parsed("", "", null, null, 'g', ""), value) ?: "", decimalSeparator)

    /** The decimal separator of the user's locale. */
    fun systemDecimalSeparator(): String =
        DecimalFormatSymbols.getInstance(Locale.getDefault()).decimalSeparator.toString()

    /** The format split around its one conversion; null when the format is refused. */
    fun parse(format: String): Parsed? {
        // Code points, as the C library reads the text: a "%" is a "%" whatever comes before it.
        val points = format.codePoints().toArray()
        val prefix = StringBuilder()
        val suffix = StringBuilder()
        var parsed: Parsed? = null
        var index = 0
        while (index < points.size) {
            val point = points[index]
            index += 1
            val text = if (parsed == null) prefix else suffix
            if (point != '%'.code) {
                text.appendCodePoint(point)
                continue
            }
            if (index >= points.size) return null
            if (points[index] == '%'.code) {
                text.append('%')
                index += 1
                continue
            }
            if (parsed != null) return null
            val flags = StringBuilder()
            while (index < points.size && points[index] < 128 && "-+ #0".indexOf(points[index].toChar()) >= 0) {
                flags.append(points[index].toChar())
                index += 1
            }
            val width = StringBuilder()
            while (index < points.size && points[index] in '0'.code..'9'.code) {
                width.append(points[index].toChar())
                index += 1
            }
            var precision: Int? = null
            if (index < points.size && points[index] == '.'.code) {
                index += 1
                val digits = StringBuilder()
                while (index < points.size && points[index] in '0'.code..'9'.code) {
                    digits.append(points[index].toChar())
                    index += 1
                }
                precision = if (digits.isEmpty()) 0 else digits.toString().toIntOrNull()?.takeIf { it <= MAX_LENGTH } ?: return null
            }
            if (index >= points.size || points[index] >= 128 || "difFeEgG".indexOf(points[index].toChar()) < 0) return null
            val conversion = points[index].toChar()
            index += 1
            val widthValue = if (width.isEmpty()) null else width.toString().toIntOrNull()?.takeIf { it <= MAX_LENGTH } ?: return null
            parsed = Parsed("", flags.toString(), widthValue, precision, conversion, "")
        }
        return parsed?.copy(prefix = prefix.toString(), suffix = suffix.toString())
    }

    /** The conversion applied to [value], C's text in the C locale; null when refused. */
    private fun formatNumber(parsed: Parsed, value: Double): String? {
        val flags = parsed.flags
        val leftAlign = '-' in flags
        val alternate = '#' in flags
        val negative = value < 0 || (value == 0.0 && 1 / value < 0)
        // No sign for NaN, where C libraries differ.
        val sign = when {
            value.isNaN() -> ""
            negative -> "-"
            '+' in flags -> "+"
            ' ' in flags -> " "
            else -> ""
        }
        val conversion = parsed.conversion
        val upper = conversion.isUpperCase()
        var zeroPad = '0' in flags && !leftAlign
        val body: String
        when (conversion) {
            'd', 'i' -> {
                if (!value.isFinite()) return null
                val truncated = BigDecimal(value).setScale(0, RoundingMode.DOWN).toBigInteger()
                if (truncated < LONG_MIN || truncated > LONG_MAX) return null
                // The sign of the integer, not of the value: -0.4 is 0, which "+" shows as "+0".
                val integerSign = when {
                    truncated.signum() < 0 -> "-"
                    '+' in flags -> "+"
                    ' ' in flags -> " "
                    else -> ""
                }
                var digits = truncated.abs().toString()
                if (parsed.precision != null) {
                    zeroPad = false
                    digits = if (parsed.precision == 0 && truncated.signum() == 0) "" else digits.padStart(parsed.precision, '0')
                }
                return pad(integerSign, digits, parsed.width, leftAlign, zeroPad)
            }
            else -> {
                if (value.isNaN() || value.isInfinite()) {
                    body = if (value.isNaN()) "nan" else "inf"
                    zeroPad = false
                } else {
                    val magnitude = BigDecimal(Math.abs(value))
                    body = when (conversion.lowercaseChar()) {
                        'f' -> fixed(magnitude, parsed.precision ?: 6, alternate)
                        'e' -> exponential(magnitude, parsed.precision ?: 6, alternate)
                        else -> general(magnitude, parsed.precision ?: 6, alternate)
                    }
                }
            }
        }
        val text = if (upper) body.uppercase(Locale.ROOT) else body
        return pad(sign, text, parsed.width, leftAlign, zeroPad)
    }

    /** %f: [precision] digits after the point, rounded half to even. */
    private fun fixed(magnitude: BigDecimal, precision: Int, alternate: Boolean): String {
        val text = magnitude.setScale(precision, RoundingMode.HALF_EVEN).toPlainString()
        return if (precision == 0 && alternate) "$text." else text
    }

    /** %e: one digit, [precision] digits after the point, and an exponent of at least two digits. */
    private fun exponential(magnitude: BigDecimal, precision: Int, alternate: Boolean): String {
        val (digits, exponent) = significant(magnitude, precision + 1)
        val mantissa = if (precision == 0) digits.take(1) + (if (alternate) "." else "") else digits.take(1) + "." + digits.drop(1)
        return mantissa + exponentText(exponent)
    }

    /** %g: %e or %f by the exponent, at [precision] significant digits, without trailing zeros unless [alternate]. */
    private fun general(magnitude: BigDecimal, precision: Int, alternate: Boolean): String {
        val p = if (precision == 0) 1 else precision
        val exponent = significant(magnitude, p).second
        return if (exponent < p && exponent >= -4) {
            val text = fixed(magnitude, p - 1 - exponent, alternate)
            if (alternate) text else stripZeros(text)
        } else {
            val text = exponential(magnitude, p - 1, alternate)
            if (alternate) text else {
                val split = text.indexOf('e')
                stripZeros(text.substring(0, split)) + text.substring(split)
            }
        }
    }

    /** The first [count] significant digits of [magnitude], rounded half to even, and its decimal exponent. */
    private fun significant(magnitude: BigDecimal, count: Int): Pair<String, Int> {
        if (magnitude.signum() == 0) return "0".repeat(count) to 0
        val rounded = magnitude.round(MathContext(count, RoundingMode.HALF_EVEN))
        val exponent = rounded.precision() - rounded.scale() - 1
        val digits = rounded.unscaledValue().toString().padEnd(count, '0').take(count)
        return digits to exponent
    }

    private fun exponentText(exponent: Int): String =
        "e" + (if (exponent < 0) "-" else "+") + Math.abs(exponent).toString().padStart(2, '0')

    private fun stripZeros(text: String): String =
        if ('.' !in text) text else text.trimEnd('0').trimEnd('.')

    /** The sign and digits padded to [width]: spaces before (after when [leftAlign]), or zeros after the sign. */
    private fun pad(sign: String, body: String, width: Int?, leftAlign: Boolean, zeroPad: Boolean): String {
        val length = sign.length + body.length
        if (width == null || length >= width) return sign + body
        val fill = width - length
        return when {
            leftAlign -> sign + body + " ".repeat(fill)
            zeroPad -> sign + "0".repeat(fill) + body
            else -> " ".repeat(fill) + sign + body
        }
    }

    /** The number with its decimal point as [separator] (a formatted number has at most one "."). */
    private fun localized(number: String, separator: String): String =
        if (separator == ".") number else number.replaceFirst(".", separator)

    /** The largest width or precision accepted, as on every platform. */
    internal const val MAX_LENGTH = 4096

    private val LONG_MIN = BigInteger.valueOf(Long.MIN_VALUE)
    private val LONG_MAX = BigInteger.valueOf(Long.MAX_VALUE)
}

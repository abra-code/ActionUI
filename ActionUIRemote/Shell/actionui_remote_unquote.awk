# actionui_remote_unquote.awk - a JSON string literal to its text, for actionui_remote_linux.bash.
#
#     printf '%s\n' "$literal" | LC_ALL=C /usr/bin/awk -f actionui_remote_unquote.awk
#
# Stdin is one JSON string literal, quotes included, as actionui_remote_walk.awk hands it back.
# Stdout is its text with no newline after it. On macOS actionui_remote.sh has plutil do this;
# Linux has no plutil.
#
# Run under LC_ALL=C, awk works in bytes, as macOS awk always does: a byte that is not part of an
# escape passes through as it is, and a \uXXXX escape (a surrogate pair as one code point) is
# written as its UTF-8 bytes with %c, which gawk and mawk then print as single bytes alike. What
# the host sends is valid JSON from a Swift string, so a lone surrogate, which no text can hold,
# is written as the three bytes its number would take rather than refused.

function hex4(text,    i, digit, value) {
    # Short at the end of the literal: mawk's index(s, "") is 1, which would read as a digit.
    if (length(text) != 4) return -1
    value = 0
    for (i = 1; i <= 4; i++) {
        digit = index("0123456789abcdef", tolower(substr(text, i, 1)))
        if (digit == 0) return -1
        value = value * 16 + digit - 1
    }
    return value
}

function utf8(code) {
    # \u0000 is dropped: a shell variable cannot hold NUL, and bash 5 warns on stderr when its
    # $(...) meets one. (plutil refuses the whole literal instead.)
    if (code == 0) return ""
    if (code < 128) return sprintf("%c", code)
    if (code < 2048) return sprintf("%c%c", 192 + int(code / 64), 128 + code % 64)
    if (code < 65536) return sprintf("%c%c%c", 224 + int(code / 4096), 128 + int(code / 64) % 64, 128 + code % 64)
    return sprintf("%c%c%c%c", 240 + int(code / 262144), 128 + int(code / 4096) % 64, 128 + int(code / 64) % 64, 128 + code % 64)
}

{
    s = $0
    if (substr(s, 1, 1) == "\"") s = substr(s, 2)
    if (substr(s, length(s), 1) == "\"") s = substr(s, 1, length(s) - 1)
    n = length(s)
    out = ""
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c != "\\") {
            out = out c
            continue
        }
        i++
        e = substr(s, i, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "b") out = out "\b"
        else if (e == "f") out = out "\f"
        else if (e == "u") {
            code = hex4(substr(s, i + 1, 4))
            if (code < 0) {
                # Not four hex digits: kept as written, which valid JSON never needs.
                out = out "\\u"
                continue
            }
            i += 4
            if (code >= 55296 && code < 56320 && substr(s, i + 1, 2) == "\\u") {
                low = hex4(substr(s, i + 3, 4))
                if (low >= 56320 && low < 57344) {
                    code = 65536 + (code - 55296) * 1024 + (low - 56320)
                    i += 6
                }
            }
            out = out utf8(code)
        }
        else out = out e
    }
    printf "%s", out
}

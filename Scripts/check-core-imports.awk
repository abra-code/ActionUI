# Scripts/check-core-imports.awk
#
# Checks the import lines of the Swift files given as arguments: the portable code (ActionUI/Core)
# and the GTK renderer (ActionUIAdwaita/Sources), which Linux builds into the same module. Allowed:
#   import Observation, import Dispatch
#   import FoundationEssentials   directly after   #if canImport(FoundationEssentials)
#   import Foundation             directly after an #else that follows that import
#   import Darwin / Glibc / Musl  in Lock.swift (its C library mutex) and NumberPrintf.swift
#                                 (vsnprintf) only
#   import CAdwaita, import Glibc in the GTK renderer, which builds only on Linux
# Anything else is reported as "file:line: message", and the exit status is 1.
# A stray "import Foundation" matters: Linux has full Foundation too, so it would compile there and
# bring the ICU data back into every Linux program.
#
# Usage: /usr/bin/awk -f Scripts/check-core-imports.awk <file.swift>...

function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t\r]+$/, "", s)
    return s
}

FNR == 1 {
    previous = ""
    beforePrevious = ""
    renderer = (FILENAME ~ /(^|\/)ActionUIAdwaita\/Sources\//)
}

{
    line = trim($0)
    if (line == "") {
        next
    }
    # An import may carry attributes (@preconcurrency, @_spi(Name)), an access level
    # (public import, Swift 6) and a kind (import struct Foundation.Date).
    if (line ~ /^((@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?|public|package|internal|fileprivate|private)[ \t]+)*import[ \t]/) {
        module = line
        sub(/^((@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?|public|package|internal|fileprivate|private)[ \t]+)*import[ \t]+/, "", module)
        sub(/^(typealias|struct|class|enum|protocol|let|var|func)[ \t]+/, "", module)
        sub(/[ \t.].*$/, "", module)
        # Compared by the next lines: the #else rule below must see any spelling of this import.
        line = "import " module
        ok = 0
        if (module == "Observation" || module == "Dispatch") {
            ok = 1
        } else if (module == "FoundationEssentials") {
            ok = (previous == "#if canImport(FoundationEssentials)")
        } else if (module == "Foundation") {
            ok = (previous == "#else" && beforePrevious == "import FoundationEssentials")
        } else if (renderer && (module == "CAdwaita" || module == "Glibc")) {
            ok = 1
        } else if (module == "Darwin" || module == "Glibc" || module == "Musl") {
            ok = (FILENAME ~ /(^|\/)(Lock|NumberPrintf)\.swift$/)
        }
        if (!ok) {
            printf "%s:%d: import %s is not allowed in %s\n", FILENAME, FNR, module, (renderer ? "the GTK renderer" : "Core")
            failures++
        }
    }
    beforePrevious = previous
    previous = line
}

END {
    exit (failures > 0) ? 1 : 0
}

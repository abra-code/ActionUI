// Core/Helpers/StyledText.swift
/*
 Styled text in the JSON runs format, the "json" content type of Text and TextEditor:

   [{"text":"Hello","bold":true,"italic":true,"underline":true,"strikethrough":true,
     "color":"#RRGGBB","backgroundColor":"#RRGGBB","link":"https://...",
     "kern":0.0,"baselineOffset":0.0,"fontSize":16.0}]

 Only "text" is required; every other key is optional. A renderer turns the runs into its own
 styled text (on Apple an AttributedString, in Helpers/AttributedStringHelper.swift).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One run of the JSON runs format.
struct StyledRun: Equatable, Sendable {
    var text: String
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    /// A color as written (hex or a name), read with ColorSpec by the renderer.
    var color: String?
    var backgroundColor: String?
    /// A link as written; a renderer uses it when it is a valid URL.
    var link: String?
    var kern: Double?
    var baselineOffset: Double?
    var fontSize: Double?
}

struct StyledText: Equatable, Sendable {
    var runs: [StyledRun]

    init(runs: [StyledRun]) {
        self.runs = runs
    }

    /// The runs of decoded JSON: a run without a "text" string is skipped. A flag is on when it
    /// is true or the number 1 (as JSON 1 was read before); a number is any JSON number (a string
    /// such as "2" is not one).
    init(jsonRuns: [[String: Any]]) {
        runs = jsonRuns.compactMap { run in
            guard let text = run["text"] as? String else { return nil }
            return StyledRun(
                text: text,
                bold: Self.flag(run["bold"]),
                italic: Self.flag(run["italic"]),
                underline: Self.flag(run["underline"]),
                strikethrough: Self.flag(run["strikethrough"]),
                color: run["color"] as? String,
                backgroundColor: run["backgroundColor"] as? String,
                link: run["link"] as? String,
                kern: Self.number(run["kern"]),
                baselineOffset: Self.number(run["baselineOffset"]),
                fontSize: Self.number(run["fontSize"])
            )
        }
    }

    /// The runs in JSON text, or nil when the text is not JSON or not an array of objects.
    static func parse(jsonRuns text: String) -> StyledText? {
        guard let value = try? ActionUIJSON.value(from: text),
              let runs = value as? [[String: Any]] else { return nil }
        return StyledText(jsonRuns: runs)
    }

    /// The runs as JSON text, keys sorted: "text" always, a flag only when on, a color or link
    /// when present, and kern and baselineOffset when present and not zero.
    func jsonString() -> String? {
        let items: [JSONValue] = runs.map { run in
            var object: [String: JSONValue] = ["text": .string(run.text)]
            if run.bold { object["bold"] = .bool(true) }
            if run.italic { object["italic"] = .bool(true) }
            if run.underline { object["underline"] = .bool(true) }
            if run.strikethrough { object["strikethrough"] = .bool(true) }
            if let color = run.color { object["color"] = .string(color) }
            if let color = run.backgroundColor { object["backgroundColor"] = .string(color) }
            if let link = run.link { object["link"] = .string(link) }
            if let kern = run.kern, kern != 0 { object["kern"] = .double(kern) }
            if let baseline = run.baselineOffset, baseline != 0 { object["baselineOffset"] = .double(baseline) }
            if let size = run.fontSize { object["fontSize"] = .double(size) }
            return .object(object)
        }
        return try? JSONValue.array(items).text(sortedKeys: true)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Int: return Double(number)
        case let number as Double: return number
        default: return nil
        }
    }

    private static func flag(_ value: Any?) -> Bool {
        guard let value else { return false }
        return ValueCoercion.coerce(value, to: Bool.self) as? Bool == true
    }
}

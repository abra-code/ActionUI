// Core/Elements/Link.swift
/*
 Sample JSON for Link:
 {
   "type": "Link",
   "id": 1,
   "properties": {
     "title": "Visit Site", // Optional: String for title, defaults to "Link" in buildView
     "url": "https://example.com" // Optional: URL string, returns EmptyView if nil or invalid;
                                  // a URL without a scheme ("example.com") shows a link that opens nothing
   }
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Link {
    /// Link's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = "Link"
        /// The destination as given; the renderer turns it into a URL.
        var url: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? "Link"
            url = properties["url"] as? String
        }
    }

    /// Where a link goes, as SwiftUI's Link goes (measured on macOS 27).
    enum Destination: Equatable {
        /// No URL, or text Apple's URL(string:) refuses: nothing is shown.
        case none
        /// A URL without a scheme ("example.com", "docs/page"): the link is shown and opens nothing,
        /// as the system has nothing to open it with.
        case relative
        /// A URL with a scheme, handed to the system.
        case absolute
    }

    /// The destination of the url property, as Apple's URL(string:) reads it. The Apple renderer
    /// uses URL(string:) itself; this rule is for the platforms whose parser differs (Linux's
    /// Foundation accepts "1abc:x" and refuses "a[b:x"). Android and the web follow the same rule.
    ///
    /// Refused: empty text; text before a first ":" that is no scheme (" https://...", "1abc:x");
    /// an invalid host or port after "//" (a space, "<", a bad "%" escape, an unclosed "[", a port
    /// that is not digits). Every other character is percent-encoded by URL(string:), so accepted.
    /// FormatParity/link-url-cases.json, recorded from Foundation on a Mac, holds the cases every
    /// platform checks.
    nonisolated static func destination(_ text: String?) -> Destination {
        guard let text, !text.isEmpty else { return .none }
        let scalars = Array(text.unicodeScalars)
        var rest = scalars[...]
        var hasScheme = false
        if let end = scalars.firstIndex(where: { ":/?#".unicodeScalars.contains($0) }), scalars[end] == ":" {
            let prefix = scalars[..<end]
            if isScheme(prefix) {
                // An empty prefix (":foo") is accepted with an empty scheme.
                hasScheme = !prefix.isEmpty
                rest = scalars[(end + 1)...]
            } else if !prefix.contains(where: { "@[]".unicodeScalars.contains($0) }) {
                // Foundation reads a prefix with "@", "[" or "]" as a relative path ("a@b:x").
                return .none
            }
        }
        if rest.starts(with: "//".unicodeScalars) {
            let authority = rest.dropFirst(2).prefix { !"/?#".unicodeScalars.contains($0) }
            let hostAndPort = authority.lastIndex(of: "@").map { authority[($0 + 1)...] } ?? authority
            if !isHostAndPort(hostAndPort) { return .none }
        }
        return hasScheme ? .absolute : .relative
    }

    /// A letter, then letters, digits and "+ - ."; or empty.
    private nonisolated static func isScheme(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        guard let first = text.first else { return true }
        return isASCIILetter(first) && text.allSatisfy { isASCIILetter($0) || isASCIIDigit($0) || "+-.".unicodeScalars.contains($0) }
    }

    private nonisolated static func isHostAndPort(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        if text.first == "[" {
            // Inside "[...]", up to a "%" (the zone, "[::1%en0]", which takes anything), only ASCII
            // letters, digits and "-._~!$&'()*+,;=:" ("[::1]", "[v1.x]").
            guard let close = text.firstIndex(of: "]"),
                  text[(text.startIndex + 1)..<close].prefix(while: { $0 != "%" }).allSatisfy({
                      isASCIILetter($0) || isASCIIDigit($0) || "-._~!$&'()*+,;=:".unicodeScalars.contains($0)
                  }) else { return false }
            let after = text[(close + 1)...]
            return after.isEmpty || (after.first == ":" && after.dropFirst().allSatisfy(isASCIIDigit))
        }
        guard let colon = text.firstIndex(of: ":") else { return isHost(text) }
        return text[(colon + 1)...].allSatisfy(isASCIIDigit) && isHost(text[..<colon])
    }

    /// No space, control character or character a host refuses, "%" only as an escape. A non-ASCII
    /// character is part of an international domain name, refused only as a space (U+3000).
    private nonisolated static func isHost(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index]
            if !scalar.isASCII {
                switch scalar.properties.generalCategory {
                case .spaceSeparator, .lineSeparator, .paragraphSeparator: return false
                default: break
                }
            } else if scalar.value <= 0x20 || scalar.value == 0x7F || "\"<>[\\]^`{|}".unicodeScalars.contains(scalar) {
                return false
            } else if scalar == "%" {
                guard index + 2 < text.endIndex, text[index + 1].properties.isASCIIHexDigit,
                      text[index + 2].properties.isASCIIHexDigit else { return false }
                index += 3
                continue
            }
            index += 1
        }
        return true
    }

    private nonisolated static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private nonisolated static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }
}

struct Link: ActionUIElementSpec {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
}

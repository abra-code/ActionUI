// Helpers/AttributedStringHelper.swift
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
extension AttributeScopes {
    static var native: KeyPath<AttributeScopes, AppKitAttributes.Type> { \.appKit }
}
#endif

#if canImport(UIKit)
import UIKit
extension AttributeScopes {
    static var native: KeyPath<AttributeScopes, UIKitAttributes.Type> { \.uiKit }
}
#endif

// MARK: - Parse

/// Parse a string into an AttributedString using the given content-type token.
/// Returns nil when "plain"/nil (caller falls through to generic String path) or parsing fails.
///
/// Tokens: "plain"/nil → nil (fall through), "markdown", "html", "rtf", "json" (runs array)
public func attributedStringParseContent(_ value: String, contentType: String?, logger: any ActionUILogger) -> Any? {
    switch contentType ?? "plain" {
    case "markdown":
        return (try? AttributedString(markdown: value)) ?? AttributedString(value)
    case "html":
#if canImport(AppKit) || canImport(UIKit)
        if let data = value.data(using: .utf8),
           let ns = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil) {
            return (try? AttributedString(ns, including: AttributeScopes.native)) ?? AttributedString(ns)
        }
#endif
        logger.log("AttributedStringHelper: failed to parse HTML", .warning)
        return nil
    case "rtf":
#if canImport(AppKit) || canImport(UIKit)
        if let data = value.data(using: .isoLatin1),
           let ns = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            return (try? AttributedString(ns, including: AttributeScopes.native)) ?? AttributedString(ns)
        }
#endif
        logger.log("AttributedStringHelper: failed to parse RTF", .warning)
        return nil
    case "json":
        if let data = value.data(using: .utf8),
           let runs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            return attributedStringFromJSONRuns(runs)
        }
        logger.log("AttributedStringHelper: failed to parse JSON runs", .warning)
        return nil
    default: // "plain" or unrecognized — fall through to generic String path
        return nil
    }
}

// MARK: - Serialize

/// Serialize an AttributedString value to a string using the given content-type token.
/// Returns nil if the value is not an AttributedString.
///
/// Tokens: "plain"/nil → plain text, "json" → JSON runs array
public func attributedStringSerializeContent(_ value: Any, contentType: String?, logger: any ActionUILogger) -> String? {
    guard let attributed = value as? AttributedString else { return nil }
    switch contentType ?? "plain" {
    case "json":
        return attributedStringToJSONRuns(attributed)
    default: // "plain"
        return String(attributed.characters)
    }
}

// MARK: - JSON Runs Format
//
// Format: [{"text":"Hello","bold":true,"italic":true,"underline":true,"strikethrough":true,
//            "color":"#RRGGBB","backgroundColor":"#RRGGBB","link":"https://...",
//            "kern":0.0,"baselineOffset":0.0,"fontSize":16.0}]
// Only "text" is required; all other keys are optional.

public func attributedStringFromJSONRuns(_ runs: [[String: Any]]) -> AttributedString {
    var result = AttributedString()
    for run in runs {
        guard let text = run["text"] as? String else { continue }
        var segment = AttributedString(text)
        if run["bold"] as? Bool == true {
            segment.font = (segment.font ?? .body).bold()
        }
        if run["italic"] as? Bool == true {
            segment.font = (segment.font ?? .body).italic()
        }
        if run["underline"] as? Bool == true {
            segment.underlineStyle = .single
        }
        if run["strikethrough"] as? Bool == true {
            segment.strikethroughStyle = .single
        }
        if let hex = run["color"] as? String, let color = ColorHelper.resolveColor(hex) {
            segment.foregroundColor = color
        }
        if let hex = run["backgroundColor"] as? String, let color = ColorHelper.resolveColor(hex) {
            segment.backgroundColor = color
        }
        if let urlString = run["link"] as? String, let url = URL(string: urlString) {
            segment.link = url
        }
        if let kern = run["kern"] as? Double {
            segment.kern = kern
        }
        if let baseline = run["baselineOffset"] as? Double {
            segment.baselineOffset = baseline
        }
        if let size = run["fontSize"] as? Double {
            segment.font = .system(size: size)
        }
        result.append(segment)
    }
    return result
}

/// Serialize an AttributedString to the JSON runs format.
/// Note: SwiftUI.Font does not expose bold/italic as inspectable Bool properties;
/// color, link, kern, baseline, underline, and strikethrough are captured when present.
public func attributedStringToJSONRuns(_ attributed: AttributedString) -> String? {
    var runs: [[String: Any]] = []
    for run in attributed.runs {
        var dict: [String: Any] = ["text": String(attributed[run.range].characters)]
        if run.underlineStyle == .single { dict["underline"] = true }
        if run.strikethroughStyle == .single { dict["strikethrough"] = true }
        if let color = run.foregroundColor {
            dict["color"] = ColorHelper.colorToHex(color) ?? ""
        }
        if let color = run.backgroundColor {
            dict["backgroundColor"] = ColorHelper.colorToHex(color) ?? ""
        }
        if let url = run.link {
            dict["link"] = url.absoluteString
        }
        if let kern = run.kern, kern != 0 {
            dict["kern"] = kern
        }
        if let baseline = run.baselineOffset, baseline != 0 {
            dict["baselineOffset"] = baseline
        }
        runs.append(dict)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: runs, options: [.sortedKeys]) else { return nil }
    return String(data: data, encoding: .utf8)
}

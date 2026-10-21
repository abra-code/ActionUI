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
        if let styled = StyledText.parse(jsonRuns: value) {
            return attributedString(from: styled)
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
// The format and its parsing are in Core/Helpers/StyledText.swift; here the runs become an
// AttributedString and back.

public func attributedStringFromJSONRuns(_ runs: [[String: Any]]) -> AttributedString {
    attributedString(from: StyledText(jsonRuns: runs))
}

/// Serialize an AttributedString to the JSON runs format.
/// Note: SwiftUI.Font does not expose bold/italic as inspectable Bool properties;
/// color, link, kern, baseline, underline, and strikethrough are captured when present.
public func attributedStringToJSONRuns(_ attributed: AttributedString) -> String? {
    StyledText(attributed).jsonString()
}

/// The AttributedString of styled runs. A font size replaces a bold or italic font of the same run.
func attributedString(from styled: StyledText) -> AttributedString {
    var result = AttributedString()
    for run in styled.runs {
        var segment = AttributedString(run.text)
        if run.bold {
            segment.font = (segment.font ?? .body).bold()
        }
        if run.italic {
            segment.font = (segment.font ?? .body).italic()
        }
        if run.underline {
            segment.underlineStyle = .single
        }
        if run.strikethrough {
            segment.strikethroughStyle = .single
        }
        if let color = ColorHelper.resolveColor(run.color) {
            segment.foregroundColor = color
        }
        if let color = ColorHelper.resolveColor(run.backgroundColor) {
            segment.backgroundColor = color
        }
        if let urlString = run.link, let url = URL(string: urlString) {
            segment.link = url
        }
        if let kern = run.kern {
            segment.kern = kern
        }
        if let baseline = run.baselineOffset {
            segment.baselineOffset = baseline
        }
        if let size = run.fontSize {
            segment.font = .system(size: size)
        }
        result.append(segment)
    }
    return result
}

extension StyledText {
    /// The runs of an AttributedString: its underline and strikethrough (single), colors (as hex,
    /// "" when a color has no sRGB form), link, kern and baseline offset. Bold, italic and font
    /// size are not read back: a SwiftUI.Font does not tell them.
    init(_ attributed: AttributedString) {
        self.init(runs: attributed.runs.map { run in
            var styled = StyledRun(text: String(attributed[run.range].characters))
            styled.underline = run.underlineStyle == .single
            styled.strikethrough = run.strikethroughStyle == .single
            if let color = run.foregroundColor {
                styled.color = ColorHelper.colorToHex(color) ?? ""
            }
            if let color = run.backgroundColor {
                styled.backgroundColor = ColorHelper.colorToHex(color) ?? ""
            }
            styled.link = run.link?.absoluteString
            styled.kern = run.kern.map(Double.init)
            styled.baselineOffset = run.baselineOffset.map(Double.init)
            return styled
        })
    }
}

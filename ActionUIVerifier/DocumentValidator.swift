// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// DocumentValidator.swift - the Swift twin of the Python ActionUI JSON verifier (Tools/verifier),
// driven by the same schema files (ActionUIVerifier/Schemas), so the two cannot drift on content.
// It catches what ActionUI's loader accepts silently: unknown property names (typos), wrong value
// types, unknown enum values, unexpected top-level keys, missing required properties, unknown
// platform suffixes, and platform-restricted properties.
//
// The rules follow verifier/element_validator.py, property_validator.py, type_checker.py and
// platform_filter.py, and validate_menubar in validate_actionui.py; messages are worded the same,
// so ActionUIVerifierTests/Parity/validator_parity.py can compare the two implementations line by
// line. Keep them in step: a rule changed in one belongs in both.
//
// JSONSerialization does not keep the order of keys in the file, so keys are walked sorted, and
// no rule may depend on key order.

import Foundation

public struct ValidationIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error, warning, info
    }

    public let severity: Severity
    public let path: String
    public let message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }

    /// `[ERROR] path: message`, the Python verifier's line format.
    public var description: String { "[\(severity.rawValue.uppercased())] \(path): \(message)" }
}

// MARK: - Platforms

/// Mirrors ActionUI/Common/PlatformFilter.swift and verifier/platform_filter.py.
enum Platforms {
    static let all: Set<String> = ["ios", "macos", "tvos", "watchos", "visionos", "apple",
                                   "android", "androidtv", "wear", "desktop", "web"]
    static let families: [String: Set<String>] = [
        "apple": ["apple", "ios", "macos", "tvos", "watchos", "visionos"],
        "android": ["android", "androidtv", "wear"],
        "desktop": ["desktop"],
        "web": ["web"],
    ]

    /// Splits a key on its last colon: ("text:ios") -> ("text", "ios").
    static func split(_ key: String) -> (base: String, suffix: String?) {
        guard let index = key.lastIndex(of: ":") else {
            return (key, nil)
        }
        return (String(key[..<index]), String(key[key.index(after: index)...]))
    }

    static func label(_ base: String, _ suffix: String?) -> String {
        suffix.map { "\(base):\($0)" } ?? base
    }

    /// True if `token` (a key suffix or a schema `platforms` entry) applies to `platform`; an
    /// umbrella token matches any member of its family.
    static func matches(_ token: String, _ platform: String) -> Bool {
        token == platform || (families[token]?.contains(platform) ?? false)
    }

    static func include(_ annotation: [String], _ platform: String) -> Bool {
        annotation.contains { matches($0, platform) }
    }

    /// The variant of one key that survives the runtime filter on `platform`, as
    /// PlatformFilter.filterObject picks it: an exact suffix outranks an umbrella suffix, which
    /// outranks the unsuffixed key; other platforms are dropped. A platform matches at most one
    /// suffix per rank, so the result does not depend on the order of `variants`.
    static func select<Value>(_ variants: [(suffix: String?, value: Value)], for platform: String)
        -> (suffix: String?, value: Value)? {
        var best: (suffix: String?, value: Value)?
        var bestRank = -1
        for variant in variants {
            let rank: Int
            if let suffix = variant.suffix {
                if suffix == platform {
                    rank = 2
                } else if matches(suffix, platform) {
                    rank = 1
                } else {
                    continue
                }
            } else {
                rank = 0
            }
            if rank > bestRank {
                best = variant
                bestRank = rank
            }
        }
        return best
    }

    static var sortedList: String { all.sorted().joined(separator: ", ") }
}

// MARK: - Types

enum TypeCheck {
    /// JSON type name, as the Python verifier reports it.
    static func name(_ value: JSONValue) -> String {
        switch value {
        case .bool: return "boolean"
        case .int: return "integer"
        case .double: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        case .null: return "null"
        }
    }

    /// "number" matches integers and non-integers; "integer" only integers.
    static func matches(_ value: JSONValue, _ types: [String]) -> Bool {
        let actual = name(value)
        return types.contains { $0 == actual || ($0 == "number" && actual == "integer") }
    }

    static func matchesSpec(_ value: JSONValue, _ spec: [String: JSONValue]) -> Bool {
        if let types = spec["types"]?.stringArray, !matches(value, types) {
            return false
        }
        if let constant = spec["const"], !equal(value, constant) {
            return false
        }
        if let options = spec["enum"]?.stringArray, case .string(let text) = value, !options.contains(text) {
            return false
        }
        return true
    }

    /// JSON equality with numbers compared by value (1 equals 1.0, as in Python).
    static func equal(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if let x = a.double, let y = b.double {
            return x == y
        }
        return a == b
    }
}

/// A short rendering of a value for messages, like Python's repr truncated to 40 characters.
/// Python counts code points, not grapheme clusters, so the length is taken in Unicode scalars.
private func shortRepr(_ value: JSONValue) -> String {
    let scalars = pyRepr(value).unicodeScalars
    if scalars.count <= 40 {
        return String(scalars)
    }
    return String(String.UnicodeScalarView(scalars.prefix(37))) + "..."
}

/// Python's repr of a str: single quotes unless the text holds a single quote and no double
/// quote; backslash, the quote, tab, newline and carriage return escaped; other control and
/// non-printable characters as \x, \u or \U escapes. A raw newline would also split the output
/// line.
func pyStringRepr(_ text: String) -> String {
    let quote: Unicode.Scalar = text.contains("'") && !text.contains("\"") ? "\"" : "'"
    var result = String(Character(quote))
    for scalar in text.unicodeScalars {
        switch scalar {
        case quote, "\\":
            result += "\\" + String(Character(scalar))
        case "\t":
            result += "\\t"
        case "\n":
            result += "\\n"
        case "\r":
            result += "\\r"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7f {
                result += String(format: "\\x%02x", scalar.value)
            } else if scalar.value < 0x7f || isPrintable(scalar) {
                result.unicodeScalars.append(scalar)
            } else if scalar.value <= 0xff {
                result += String(format: "\\x%02x", scalar.value)
            } else if scalar.value <= 0xffff {
                result += String(format: "\\u%04x", scalar.value)
            } else {
                result += String(format: "\\U%08x", scalar.value)
            }
        }
    }
    result.unicodeScalars.append(quote)
    return result
}

/// Python's str.isprintable for one non-ASCII character: not a control, format, surrogate,
/// private-use, unassigned or separator character.
private func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .format, .surrogate, .privateUse, .unassigned,
         .lineSeparator, .paragraphSeparator, .spaceSeparator:
        return false
    default:
        return true
    }
}

/// Python-style rendering, so messages match the Python verifier's.
func pyRepr(_ value: JSONValue) -> String {
    switch value {
    case .null:
        return "None"
    case .bool(let flag):
        return flag ? "True" : "False"
    case .int(let number):
        return String(number)
    case .double(let number):
        return number == number.rounded() && abs(number) < 1e16 ? String(format: "%.1f", number) : String(number)
    case .string(let text):
        return pyStringRepr(text)
    case .array(let items):
        return "[" + items.map(pyRepr).joined(separator: ", ") + "]"
    case .object(let object):
        return "{" + object.keys.sorted().map { "\(pyStringRepr($0)): \(pyRepr(object[$0]!))" }.joined(separator: ", ") + "}"
    }
}

func pyList(_ strings: [String]) -> String {
    pyRepr(.array(strings.map(JSONValue.string)))
}

// MARK: - Validator

public struct DocumentValidator: Sendable {
    /// Every platform token a key suffix or `targetPlatform` may name.
    public static var knownPlatforms: Set<String> { Platforms.all }

    /// Keys that are structural, never element-specific properties.
    private static let structuralKeys: Set<String> = ["type", "id", "properties"]
    /// Subview keys any element may carry.
    private static let universalSubviewKeys: Set<String> = ["overlay", "sheet", "popover", "fullScreenCover", "background",
                                                           "backgroundView", "toolbar", "contextMenu", "contextMenuPreview",
                                                           "swipeActions", "safeAreaInset"]
    /// Keys used as JSON comments; allowed everywhere.
    private static let annotationKeys: Set<String> = ["description", "note", "comment", "info"]
    private static let menuBarTypes = ["CommandMenu", "CommandGroup"]

    private typealias Variants = [(suffix: String?, value: JSONValue)]

    private let schemas: SchemaSet
    private let viewProperties: [String: JSONValue]
    /// When set, validate as deployed to this platform: each key is resolved as the runtime
    /// resolves it, and platform-restricted properties used here are flagged. When nil, validate
    /// as a cross-platform authoring document.
    private let targetPlatform: String?

    /// - Parameter targetPlatform: one of `knownPlatforms`, or nil for a cross-platform document.
    public init(schemas: SchemaSet, targetPlatform: String? = nil) {
        self.schemas = schemas
        self.viewProperties = schemas.schema("View")?["properties"]?.object ?? [:]
        self.targetPlatform = targetPlatform
    }

    /// Parses `data` as ActionUI's loader does (JSONSerialization: trailing commas are accepted,
    /// comments are not) and validates it. Throws the parse error for invalid JSON.
    public func validate(data: Data, rootPath: String) throws -> [ValidationIssue] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return validate(jsonObject: object, rootPath: rootPath)
    }

    /// Validates a view document (object root) or a menu-bar document (array root), given as
    /// JSONSerialization output. `rootPath` prefixes every issue path, as the file name does in
    /// the Python verifier. Issues are sorted by path, then severity.
    public func validate(jsonObject: Any, rootPath: String) -> [ValidationIssue] {
        validate(document: JSONValue(any: jsonObject), rootPath: rootPath)
    }

    func validate(document: JSONValue, rootPath: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seenIDs: Set<Int> = []
        switch document {
        case .object(let node):
            issues = validate(node: node, path: rootPath, seenIDs: &seenIDs, isRoot: true)
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                let path = "\(rootPath)[\(index)]"
                guard let object = element.object else {
                    issues.append(.init(severity: .error, path: path, message: "menu-bar element must be a JSON object"))
                    continue
                }
                switch object["type"] {
                case .string(let type) where Self.menuBarTypes.contains(type):
                    issues += validate(node: object, path: path, seenIDs: &seenIDs, isRoot: true)
                case nil, .null?:  // an explicit null counts as missing, as Python's dict.get sees it
                    issues.append(.init(severity: .error, path: path, message: "menu-bar element missing 'type'"))
                case let other?:
                    let shown = other.string ?? pyRepr(other)
                    issues.append(.init(severity: .error, path: path, message:
                        "'\(shown)' is not valid at the top level of a menu-bar document; expected one of: \(Self.menuBarTypes.joined(separator: ", "))"))
                }
            }
        default:
            issues.append(.init(severity: .error, path: rootPath, message: "root must be a JSON object (a view) or array (a menu bar)"))
        }
        // By path, then severity name (error, info, warning), as the Python verifier sorts them.
        return issues.sorted { ($0.path, $0.severity.rawValue) < ($1.path, $1.severity.rawValue) }
    }

    /// Groups keys by base name; keys with an unknown platform suffix are dropped with a warning.
    private func expandSuffixed(_ object: [String: JSONValue], path: String)
        -> (expanded: [String: Variants], warnings: [ValidationIssue]) {
        var expanded: [String: Variants] = [:]
        var warnings: [ValidationIssue] = []
        for key in object.keys.sorted() {
            let value = object[key]!
            let (base, suffix) = Platforms.split(key)
            if let suffix, !Platforms.all.contains(suffix) {
                warnings.append(.init(severity: .warning, path: path, message:
                    "unknown platform suffix in key '\(key)' (suffix='\(suffix)'); key will be dropped at runtime. Known platforms: \(Platforms.sortedList)"))
            } else {
                expanded[base, default: []].append((suffix, value))
            }
        }
        return (expanded, warnings)
    }

    private func validate(node: [String: JSONValue], path: String, seenIDs: inout Set<Int>, isRoot: Bool) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let separator = isRoot ? ": " : "."
        var (expanded, suffixWarnings) = expandSuffixed(node, path: path)
        issues += suffixWarnings

        // Deployed to one platform, only the variant of each node-level key (type, id, properties,
        // subview keys) that the runtime keeps is checked. Variants of keys inside a properties
        // block are handled in validateProperties.
        let hadType = expanded["type"] != nil
        if let target = targetPlatform {
            var selected: [String: Variants] = [:]
            for (base, variants) in expanded {
                if let winner = Platforms.select(variants, for: target) {
                    selected[base] = [winner]
                }
            }
            expanded = selected
        }

        // type, possibly per platform. Each variant must be a known element type.
        guard let typeVariants = expanded["type"], !typeVariants.isEmpty else {
            if hadType, let target = targetPlatform {
                issues.append(.init(severity: .error, path: path, message: "no 'type' variant applies to target platform '\(target)'"))
            } else {
                issues.append(.init(severity: .error, path: path, message: "missing or invalid 'type' field"))
            }
            return issues
        }
        var typeBySuffix: [String?: String] = [:]
        for (suffix, value) in typeVariants {
            let label = Platforms.label("type", suffix)
            guard case .string(let type) = value, !type.isEmpty else {
                issues.append(.init(severity: .error, path: path, message: "'\(label)' must be a non-empty string"))
                continue
            }
            guard schemas.knownTypes.contains(type) else {
                issues.append(.init(severity: .error, path: path, message: "unknown element type '\(type)' for '\(label)'; no schema found"))
                continue
            }
            typeBySuffix[suffix] = type
        }
        let variantTypes = Set(typeBySuffix.values).sorted()
        guard !variantTypes.isEmpty else {
            return issues  // no variant names a known type; nothing more can be checked
        }

        // The primary type pairs with the unsuffixed properties block: the unsuffixed type, or the
        // only type left (always the case when deployed). Platform variants naming different types
        // with no unsuffixed type leave no primary type: the unsuffixed properties then apply under
        // every variant and are checked against all of them.
        let primaryType = typeBySuffix[nil] ?? (variantTypes.count == 1 ? variantTypes[0] : nil)
        let typeLabel = primaryType ?? variantTypes.joined(separator: " or ")

        // id: optional; a positive integer unique in the tree. The same id on several platform
        // variants of one node counts once.
        var seenInNode: Set<Int> = []
        for (suffix, value) in expanded["id"] ?? [] {
            let label = Platforms.label("id", suffix)
            switch value {
            case .null:
                continue
            case .int(let id):
                if id == 0 {
                    issues.append(.init(severity: .error, path: path, message: "'\(label)' 0 is invalid — must be a positive non-zero integer"))
                } else if id < 0 {
                    issues.append(.init(severity: .error, path: path, message: "'\(label)' \(id) is negative — negative IDs are auto-generated; do not set them manually"))
                } else if seenInNode.contains(id) {
                    continue
                } else if seenIDs.contains(id) {
                    issues.append(.init(severity: .error, path: path, message: "duplicate '\(label)' \(id) — IDs must be unique across the entire view tree"))
                } else {
                    seenIDs.insert(id)
                    seenInNode.insert(id)
                }
            default:
                issues.append(.init(severity: .error, path: path, message: "'\(label)' must be an integer, got \(Self.pythonTypeName(value))"))
            }
        }

        // Top-level keys and subview keys: those of any type variant, plus the universal ones.
        let typeSchemas = variantTypes.compactMap { schemas.schema($0) }
        guard !typeSchemas.isEmpty else {
            return issues
        }
        var allowedTop = Self.structuralKeys.union(Self.universalSubviewKeys)
        var subviewKeys = Self.universalSubviewKeys
        for schema in typeSchemas {
            let keys = Set(schema["topLevelKeys"]?.stringArray ?? [])
            allowedTop.formUnion(keys)
            subviewKeys.formUnion(keys)
        }
        for base in expanded.keys.sorted() where !allowedTop.contains(base) {
            issues.append(.init(severity: .warning, path: path, message: "unexpected top-level key '\(base)' for \(typeLabel)"))
        }

        // properties: each properties:X pairs with type:X; any other block with the primary type,
        // or with every type variant when there is no primary type.
        for (suffix, value) in expanded["properties"] ?? [] {
            let labelPath = "\(path)\(separator)\(Platforms.label("properties", suffix))"
            guard let properties = value.object else {
                issues.append(.init(severity: .error, path: labelPath, message: "must be an object"))
                continue
            }
            if let pairedType = typeBySuffix[suffix] ?? primaryType {
                let ownProperties = schemas.schema(pairedType)?["ownProperties"]?.object ?? [:]
                issues += validateProperties(properties, own: ownProperties, elementType: pairedType, path: labelPath)
            } else {
                issues += validateProperties(properties, own: mergedOwnProperties(variantTypes), elementType: typeLabel, path: labelPath)
            }
        }

        // Children and subviews, recursively. Platform variants of one subview key (children and
        // children:ios) never survive together at runtime, so the same id may appear in each:
        // every variant is checked against the ids seen before the key, not against its sibling
        // variants, and then all their ids are recorded.
        for key in subviewKeys.sorted() {
            let variants = expanded[key] ?? []
            if variants.count <= 1 {
                for (suffix, value) in variants {
                    let childPath = "\(path)\(separator)\(Platforms.label(key, suffix))"
                    issues += validateSubview(value, path: childPath, seenIDs: &seenIDs)
                }
                continue
            }
            let idsBefore = seenIDs
            for (suffix, value) in variants {
                let childPath = "\(path)\(separator)\(Platforms.label(key, suffix))"
                var variantIDs = idsBefore
                issues += validateSubview(value, path: childPath, seenIDs: &variantIDs)
                seenIDs.formUnion(variantIDs)
            }
        }
        return issues
    }

    /// The ownProperties of `typeNames` merged, for a properties block that applies under several
    /// element types. On a key several types define, the first type's spec is used. A property is
    /// required only when every type requires it.
    private func mergedOwnProperties(_ typeNames: [String]) -> [String: JSONValue] {
        let ownPropertiesList = typeNames.map { schemas.schema($0)?["ownProperties"]?.object ?? [:] }
        var merged: [String: JSONValue] = [:]
        for ownProperties in ownPropertiesList {
            merged.merge(ownProperties) { first, _ in first }
        }
        for (key, spec) in merged where spec["required"]?.bool == true {
            let requiredByAll = ownPropertiesList.allSatisfy { $0[key]?["required"]?.bool == true }
            if !requiredByAll, var object = spec.object {
                object["required"] = .bool(false)
                merged[key] = .object(object)
            }
        }
        return merged
    }

    private func validateSubview(_ value: JSONValue, path: String, seenIDs: inout Set<Int>) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        switch value {
        case .array(let items):
            for (index, child) in items.enumerated() {
                let itemPath = "\(path)[\(index)]"
                switch child {
                case .object(let object):
                    issues += validate(node: object, path: itemPath, seenIDs: &seenIDs, isRoot: false)
                case .array(let cells):  // Grid rows: arrays of cells
                    for (cellIndex, cell) in cells.enumerated() {
                        let cellPath = "\(itemPath)[\(cellIndex)]"
                        if let object = cell.object {
                            issues += validate(node: object, path: cellPath, seenIDs: &seenIDs, isRoot: false)
                        } else {
                            issues.append(.init(severity: .error, path: cellPath, message: "cell must be an object"))
                        }
                    }
                default:
                    issues.append(.init(severity: .error, path: itemPath, message: "child must be an object"))
                }
            }
        case .object(let object):
            issues += validate(node: object, path: path, seenIDs: &seenIDs, isRoot: false)
        default:
            break
        }
        return issues
    }

    private func validateProperties(_ properties: [String: JSONValue], own: [String: JSONValue],
                                    elementType: String, path: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let (expanded, suffixWarnings) = expandSuffixed(properties, path: path)
        issues += suffixWarnings

        for base in expanded.keys.sorted() {
            let spec = (own[base] ?? viewProperties[base])?.object
            for (suffix, value) in expanded[base]! {
                let label = Platforms.label(base, suffix)
                // Deployed to one platform, a variant for another platform is dropped at runtime.
                if let target = targetPlatform, let suffix, !Platforms.matches(suffix, target) {
                    continue
                }
                if let spec {
                    issues += checkPropertyPlatform(base: base, suffix: suffix, spec: spec, label: label, path: path)
                    issues += Self.validateProperty(key: label, value: value, spec: spec, path: path)
                } else if Self.annotationKeys.contains(base) {
                    issues.append(.init(severity: .info, path: "\(path).\(label)",
                                        message: "'\(label)' is an annotation key used as a JSON comment; ignored at runtime"))
                } else {
                    let knownIn = viewProperties.isEmpty ? elementType : "\(elementType) or View base"
                    issues.append(.init(severity: .warning, path: "\(path).\(label)",
                                        message: "'\(label)' is not a known property for \(knownIn); possible typo"))
                }
            }
        }
        for key in own.keys.sorted() where own[key]?["required"]?.bool == true && expanded[key] == nil {
            issues.append(.init(severity: .error, path: "\(path).\(key)", message: "required property '\(key)' is missing"))
        }
        return issues
    }

    private func checkPropertyPlatform(base: String, suffix: String?, spec: [String: JSONValue], label: String,
                                       path: String) -> [ValidationIssue] {
        guard let platforms = spec["platforms"]?.stringArray else {
            return []
        }
        if let target = targetPlatform {
            if Platforms.include(platforms, target) {
                return []
            }
            return [.init(severity: .warning, path: "\(path).\(label)", message:
                "'\(label)': property '\(base)' is not available on target platform '\(target)' (available on: \(pyList(platforms)))")]
        }
        guard let suffix else {
            return [.init(severity: .warning, path: "\(path).\(label)", message:
                "'\(base)' is platform-specific (available on: \(pyList(platforms))); in a cross-platform document suffix it (e.g. '\(base):\(platforms.first ?? "")') so it is applied only where supported")]
        }
        if !Platforms.include(platforms, suffix) {
            return [.init(severity: .warning, path: "\(path).\(label)", message:
                "'\(label)': property '\(base)' is not available on '\(suffix)' (available on: \(pyList(platforms)))")]
        }
        return []
    }

    // MARK: Property values

    static func validateProperty(key: String, value: JSONValue, spec: [String: JSONValue], path: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let propertyPath = "\(path).\(key)"

        if let alternatives = spec["oneOf"]?.array?.compactMap(\.object) {
            guard let match = alternatives.first(where: { TypeCheck.matchesSpec(value, $0) }) else {
                return [.init(severity: .error, path: propertyPath, message:
                    "value type '\(TypeCheck.name(value))' (value: \(shortRepr(value))) does not match any allowed form")]
            }
            if (match["types"]?.stringArray ?? []).contains("object"), let object = value.object {
                issues += validateObject(object, spec: match, path: propertyPath)
            }
            return issues
        }

        let types = spec["types"]?.stringArray
        if let types, !TypeCheck.matches(value, types) {
            return [.init(severity: .error, path: propertyPath,
                          message: "expected \(types.joined(separator: " or ")), got \(TypeCheck.name(value))")]
        }
        // Unknown enum values warn, not fail: newer ActionUI versions may accept more.
        if let options = spec["enum"]?.stringArray, case .string(let text) = value, !options.contains(text) {
            issues.append(.init(severity: .warning, path: propertyPath,
                                message: "'\(text)' is not a known value; expected one of: \(pyList(options))"))
        }
        if (types ?? []).contains("object"), let object = value.object {
            issues += validateObject(object, spec: spec, path: propertyPath)
        }
        if (types ?? []).contains("array"), let items = value.array {
            if let itemTypes = spec["itemTypes"]?.stringArray, !itemTypes.isEmpty {
                let itemEnum = spec["itemEnum"]?.stringArray
                for (index, item) in items.enumerated() {
                    if !TypeCheck.matches(item, itemTypes) {
                        issues.append(.init(severity: .error, path: "\(propertyPath)[\(index)]",
                                            message: "expected \(itemTypes.joined(separator: " or ")), got \(TypeCheck.name(item))"))
                    } else if let itemEnum, !itemEnum.isEmpty, case .string(let text) = item, !itemEnum.contains(text) {
                        issues.append(.init(severity: .warning, path: "\(propertyPath)[\(index)]",
                                            message: "'\(text)' is not a known value; expected one of: \(pyList(itemEnum))"))
                    }
                }
            }
            // Items validated against the sub-schema named by a discriminator key (default "type").
            if let discriminated = spec["discriminatedItems"]?.object {
                let key = discriminated["discriminator"]?.string ?? "type"
                let itemSchemas = discriminated["schemas"]?.object ?? [:]
                for (index, item) in items.enumerated() {
                    let itemPath = "\(propertyPath)[\(index)]"
                    guard let object = item.object else {
                        issues.append(.init(severity: .error, path: itemPath, message: "expected object"))
                        continue
                    }
                    guard let itemType = object[key], itemType != .null else {
                        issues.append(.init(severity: .warning, path: "\(itemPath).\(key)", message: "missing required '\(key)' field"))
                        continue
                    }
                    // A discriminator that is not a string (a list, an object) is an unknown type.
                    guard let typeName = itemType.string, let itemSchema = itemSchemas[typeName] else {
                        issues.append(.init(severity: .warning, path: "\(itemPath).\(key)", message:
                            "'\(itemType.string ?? pyRepr(itemType))' is not a known type; known: \(pyList(itemSchemas.keys.sorted()))"))
                        continue
                    }
                    issues += validateObject(object, spec: ["properties": itemSchema], path: itemPath)
                }
            }
        }
        return issues
    }

    /// Sub-keys of an object value against the spec's "properties". Sub-keys may carry a platform
    /// suffix; required and mutually exclusive checks compare base names.
    private static func validateObject(_ object: [String: JSONValue], spec: [String: JSONValue], path: String) -> [ValidationIssue] {
        guard let subSpecs = spec["properties"]?.object else {
            return []  // open object
        }
        var issues: [ValidationIssue] = []
        let presentBases = Set(object.keys.map { Platforms.split($0).base })
        for key in subSpecs.keys.sorted() where subSpecs[key]?["required"]?.bool == true && !presentBases.contains(key) {
            issues.append(.init(severity: .error, path: "\(path).\(key)", message: "required key '\(key)' is missing"))
        }
        for key in object.keys.sorted() {
            let (base, suffix) = Platforms.split(key)
            if let suffix, !Platforms.all.contains(suffix) {
                issues.append(.init(severity: .warning, path: path, message:
                    "unknown platform suffix in key '\(key)' (suffix='\(suffix)'); key will be dropped at runtime. Known platforms: \(Platforms.sortedList)"))
                continue
            }
            let label = Platforms.label(base, suffix)
            if annotationKeys.contains(base) {
                continue
            }
            if let subSpec = subSpecs[base]?.object {
                issues += validateProperty(key: label, value: object[key]!, spec: subSpec, path: path)
            } else {
                issues.append(.init(severity: .warning, path: "\(path).\(label)", message: "unexpected key '\(label)' inside object"))
            }
        }
        if let groups = spec["mutuallyExclusiveGroups"]?.array?.compactMap(\.stringArray), groups.count == 2,
           groups[0].contains(where: presentBases.contains), groups[1].contains(where: presentBases.contains) {
            issues.append(.init(severity: .error, path: path, message:
                "mixes mutually exclusive keys: \(pyList(groups[0])) cannot be combined with \(pyList(groups[1]))"))
        }
        return issues
    }

    /// Python's type(value).__name__, for the id message.
    private static func pythonTypeName(_ value: JSONValue) -> String {
        switch value {
        case .bool: return "bool"
        case .int: return "int"
        case .double: return "float"
        case .string: return "str"
        case .array: return "list"
        case .object: return "dict"
        case .null: return "NoneType"
        }
    }
}

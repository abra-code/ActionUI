// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// actionui-verify - checks ActionUI JSON documents against the element schemas. Same options,
// output and exit codes as Tools/verifier/validate_actionui.py: errors go to stderr, warnings,
// notes and [OK] lines to stdout, then a summary line.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import ActionUIVerifier

let usage = """
ActionUI JSON Verifier

Usage:
    actionui-verify <file.json>            validate a single file
    actionui-verify <directory/>           validate all *.json files in directory
    actionui-verify -r <directory/>        recurse into subdirectories
    actionui-verify --strict <path>        treat warnings as errors
    actionui-verify --platform <p> <path>  validate as deployed to platform <p>
    actionui-verify --schema-dir <dir> ... add an add-on schema directory (repeatable)
    actionui-verify --schemas <dir> ...    use this core schemas directory

Without --platform, files are validated as cross-platform authoring documents:
platform-specific keys must carry a `:<platform>` suffix. With --platform, the
document is validated as if deployed to that one platform (other-platform
variants are dropped, just as they are at runtime).

--schema-dir extends the built-in element set with schemas shipped by optional
add-on libraries (e.g. Add-ons/ActionUIQuickLook/Schemas), so documents using an
add-on's element type validate. The built-in schemas take precedence on a name
collision. The option is repeatable.

Add-on schemas are also found without --schema-dir in:
  - Schemas/add-ons/<AddOn>/ in the verifier's resource bundle (placed there by a
    packaging step), and
  - Add-ons/<AddOn>/Schemas/ of the ActionUI checkout this tool was built from.
Explicit --schema-dir directories take precedence over those.

--schemas replaces the bundled core schemas with a directory of the same layout,
for a packaged copy that ships its schemas elsewhere (AppletBuilder.app points it
at the Python verifier's schemas/). Add-on schemas are then found only in its
add-ons/ and through --schema-dir, never in a checkout.

JSON is parsed as ActionUI's loader parses it: trailing commas are accepted,
comments are not.

Exit codes:
    0  no issues
    1  one or more errors found
    2  warnings only (elevated to 1 with --strict)

"""

// Each line is written whole and unbuffered, so stdout and stderr lines never split each other
// when both go to one file or pipe.
func printOutput(_ text: String) {
    writeLine(text, to: STDOUT_FILENO)
}

func printError(_ text: String) {
    writeLine(text, to: STDERR_FILENO)
}

func writeLine(_ text: String, to descriptor: Int32) {
    let bytes = Array((text + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written < 0 && errno == EINTR { continue }
        if written <= 0 { return }
        offset += written
    }
}

/// An error as a person reads it. Foundation's Error.localizedDescription is not in
/// FoundationEssentials.
func describe(_ error: Error) -> String {
    #if os(Linux)
    // A read failure is a CocoaError around the system's error.
    if let cause = (error as? CocoaError)?.userInfo["NSUnderlyingError"] as? POSIXError {
        return String(cString: strerror(cause.code.rawValue))
    }
    return String(describing: error)
    #else
    error.localizedDescription
    #endif
}

/// A path as Python's pathlib prints it: no empty or "." components, no trailing slash.
func normalizedPath(_ path: String) -> String {
    let components = path.split(separator: "/").filter { $0 != "." }
    let joined = components.joined(separator: "/")
    if path.hasPrefix("/") {
        return "/" + joined
    }
    return joined.isEmpty ? "." : joined
}

func isDirectory(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
}

/// Everything under `directory`, as paths relative to it. As with pathlib's rglob, a folder that
/// cannot be read is skipped and a link to a folder is not followed. (FileManager's
/// subpathsOfDirectory throws away the whole tree at the first folder it cannot read.)
func subpaths(of directory: String) -> [String] {
    var found: [String] = []
    for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
        found.append(name)
        var info = stat()
        if lstat(directory + "/" + name, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR {
            found += subpaths(of: directory + "/" + name).map { name + "/" + $0 }
        }
    }
    return found
}

/// `*.json` files in `directory`, sorted as pathlib sorts paths (component by component).
func jsonFiles(in directory: String, recursive: Bool) -> [String] {
    let relativePaths = recursive ? subpaths(of: directory)
                                  : (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    let files = relativePaths.filter { $0.hasSuffix(".json") && !isDirectory(directory + "/" + $0) }
    let sorted = files.map { $0.split(separator: "/").map(String.init) }.sorted { $0.lexicographicallyPrecedes($1) }
    // pathlib joins "." and "a.json" as "a.json", and "/" and "a.json" as "/a.json".
    let prefix: String
    if directory == "." {
        prefix = ""
    } else if directory == "/" {
        prefix = "/"
    } else {
        prefix = directory + "/"
    }
    return sorted.map { prefix + $0.joined(separator: "/") }
}

/// True for a regular file or a symbolic link to one, as pathlib's is_file: a device, a FIFO or
/// a socket is not a file to validate.
func isRegularFile(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
}

/// Prints the issues of one file; returns (errors, warnings).
func report(path: String, issues: [ValidationIssue]) -> (Int, Int) {
    for issue in issues {
        if issue.severity == .error {
            printError(issue.description)
        } else {
            printOutput(issue.description)
        }
    }
    if issues.isEmpty {
        printOutput("[OK] \(path)")
    }
    return (issues.filter { $0.severity == .error }.count, issues.filter { $0.severity == .warning }.count)
}

func validateFile(_ path: String, validator: DocumentValidator) -> (Int, Int) {
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        printError("[ERROR] \(path): cannot read file — \(describe(error))")
        return (1, 0)
    }
    let issues: [ValidationIssue]
    do {
        issues = try validator.validate(data: data, rootPath: path)
    } catch {
        #if os(Linux)
        let reason = describe(error)
        #else
        let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? describe(error)
        #endif
        printError("[ERROR] \(path): invalid JSON — \(reason)")
        return (1, 0)
    }
    return report(path: path, issues: issues)
}

func validatePath(_ argument: String, validator: DocumentValidator, recursive: Bool) -> (Int, Int) {
    let path = normalizedPath(argument)
    var errors = 0
    var warnings = 0
    if isDirectory(path) {
        let files = jsonFiles(in: path, recursive: recursive)
        if files.isEmpty {
            printError("No *.json files found in \(path)")
            return (0, 0)
        }
        for file in files {
            let (fileErrors, fileWarnings) = validateFile(file, validator: validator)
            errors += fileErrors
            warnings += fileWarnings
        }
    } else if isRegularFile(path) {
        (errors, warnings) = validateFile(path, validator: validator)
    } else {
        printError("[ERROR] Path not found: \(path)")
        errors = 1
    }
    return (errors, warnings)
}

// MARK: - Arguments

var strict = false
var recursive = false
var targetPlatform: String?
var explicitSchemaDirectories: [String] = []
var coreSchemasDirectory: String?
var paths: [String] = []

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    if argument == "--strict" {
        strict = true
    } else if argument == "--recursive" || argument == "-r" {
        recursive = true
    } else if argument == "-h" || argument == "--help" {
        printOutput(usage)
        exit(0)
    } else if argument == "--platform" || argument == "--schema-dir" || argument == "--schemas" {
        index += 1
        guard index < arguments.count else {
            printError("[ERROR] \(argument) requires a value")
            exit(2)
        }
        if argument == "--platform" {
            targetPlatform = arguments[index]
        } else if argument == "--schemas" {
            coreSchemasDirectory = arguments[index]
        } else {
            explicitSchemaDirectories.append(arguments[index])
        }
    } else if argument.hasPrefix("--platform=") {
        targetPlatform = String(argument.dropFirst("--platform=".count))
    } else if argument.hasPrefix("--schemas=") {
        coreSchemasDirectory = String(argument.dropFirst("--schemas=".count))
    } else if argument.hasPrefix("--schema-dir=") {
        explicitSchemaDirectories.append(String(argument.dropFirst("--schema-dir=".count)))
    } else if argument.hasPrefix("-") && argument != "-" {
        printError("[ERROR] unknown option: \(argument)")
        printError(usage)
        exit(2)
    } else {
        paths.append(argument)
    }
    index += 1
}

guard !paths.isEmpty else {
    printError(usage)
    exit(2)
}

if let targetPlatform, !DocumentValidator.knownPlatforms.contains(targetPlatform) {
    printError("[ERROR] unknown platform '\(targetPlatform)'. Known platforms: \(DocumentValidator.knownPlatforms.sorted().joined(separator: ", "))")
    exit(2)
}

// MARK: - Schemas

// With --schemas the built-in schemas are never looked for, so a copy of this tool that ships its
// schemas elsewhere does not need them beside it.
let schemasDirectory: URL
if let coreSchemasDirectory {
    guard isDirectory(coreSchemasDirectory) else {
        printError("[ERROR] --schemas not found or not a directory: \(coreSchemasDirectory)")
        exit(2)
    }
    schemasDirectory = URL(fileURLWithPath: coreSchemasDirectory)
} else if let bundled = SchemaSet.bundledSchemasDirectory {
    schemasDirectory = bundled
} else {
    #if os(Linux)
    printError("[ERROR] Schemas directory not found.\nEnsure share/actionui/schemas is next to the bin folder of this tool, or pass --schemas <dir>.")
    #else
    printError("[ERROR] Schemas directory not found in the verifier's resource bundle.\nEnsure ActionUI_ActionUIVerifier.bundle is next to this tool, or pass --schemas <dir>.")
    #endif
    exit(1)
}

var extraDirectories: [URL] = []
for directory in explicitSchemaDirectories {
    guard isDirectory(directory) else {
        printError("[ERROR] --schema-dir not found or not a directory: \(directory)")
        exit(2)
    }
    extraDirectories.append(URL(fileURLWithPath: directory))
}
// Found directories go after the explicit ones; each directory is listed once.
var seenDirectories = Set(extraDirectories.map { $0.resolvingSymlinksInPath().path })
for directory in SchemaSet.discoverAddOnDirectories(schemasDirectory: schemasDirectory, includeCheckout: coreSchemasDirectory == nil)
where !seenDirectories.contains(directory.resolvingSymlinksInPath().path) {
    extraDirectories.append(directory)
    seenDirectories.insert(directory.resolvingSymlinksInPath().path)
}

let schemas: SchemaSet
do {
    schemas = try SchemaSet(primary: schemasDirectory, extra: extraDirectories)
} catch {
    printError("[ERROR] could not load the schemas: \(describe(error))")
    exit(1)
}
let validator = DocumentValidator(schemas: schemas, targetPlatform: targetPlatform)

// MARK: - Run

var totalErrors = 0
var totalWarnings = 0
for path in paths {
    let (errors, warnings) = validatePath(path, validator: validator, recursive: recursive)
    totalErrors += errors
    totalWarnings += warnings
}

if totalErrors > 0 {
    printError("\n\(totalErrors) error(s), \(totalWarnings) warning(s).")
    exit(1)
} else if totalWarnings > 0 && strict {
    printError("\n0 errors, \(totalWarnings) warning(s) — failing due to --strict.")
    exit(1)
} else if totalWarnings > 0 {
    printOutput("\n0 errors, \(totalWarnings) warning(s).")
    exit(2)
} else {
    printOutput("\nAll files valid.")
    exit(0)
}

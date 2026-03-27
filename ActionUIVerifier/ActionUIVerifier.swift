import Foundation
import ActionUI

@MainActor
struct ActionUIVerifier {
    private let logger: VerifierLogger
    
    init() {
        // Use a custom logger to print errors to stderr and track failure
        self.logger = VerifierLogger()
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
    }
    
    var hadErrors: Bool {
        return logger.hadErrors
    }
    
    var hadWarnings: Bool {
        return logger.hadWarnings
    }

    func verify(jsonPath: String) -> Bool {
        do {
            fputs("Verifying JSON at: \(jsonPath)\n", stdout)
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
            var seenIDs = Set<Int>()
            return validateElement(element, path: jsonPath, seenIDs: &seenIDs)
        } catch {
            logger.log("Failed to load or decode JSON at \(jsonPath): \(error)", .error)
            return false
        }
        
    }
    
    func verifyDirectory(_ directoryPath: String) -> Bool {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: directoryPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            logger.log("Failed to read directory: \(directoryPath). Check path exists and is accessible.", .error)
            return false
        }
        
        var isValid = true
        for url in urls where url.pathExtension == "json" {
            if !verify(jsonPath: url.path) {
                isValid = false
            }
        }
        return isValid
    }
    
    // TODO: construct a better "path" with information regarding the element in the json being validated
    // so we can provide useful error information containing the problematic element location
    
    private func validateElement(_ element: any ActionUIElementBase, path: String, seenIDs: inout Set<Int>) -> Bool {
        var isValid = true

        // Validate ID:
        // - Negative IDs are auto-assigned by ActionUI for elements without explicit "id" in JSON — skip those.
        // - Zero is always invalid (id must be positive non-zero if set).
        // - Positive IDs must be unique across the entire view tree.
        let id = element.id
        if id == 0 {
            logger.log("\(path): Invalid id 0 — IDs must be positive non-zero integers", .error)
            isValid = false
        } else if id > 0 {
            if seenIDs.contains(id) {
                logger.log("\(path): Duplicate id \(id) — IDs must be unique across the entire view tree", .error)
                isValid = false
            }
            seenIDs.insert(id)
        }
        // id < 0: auto-assigned, skip

        // Validate properties
        let _ = ActionUIRegistry.shared.validateProperties(
            forElementType: element.type,
            properties: element.properties)

        // Recursively validate subviews
        // We could have arrays of children ("children", "sidebar", etc) or a single child ("content") or arrays of arrays ("rows")
        // "children", "rows", "content", "destination", "sidebar", "detail", "popover"
        if let subviews = element.subviews {
            for (key, value) in subviews {
                switch (value) {
                case (let children as [ActionUIElement]):
                    for (index, child) in children.enumerated() {
                        if !validateElement(child, path: "\(path)/\(key)[\(index)]", seenIDs: &seenIDs) {
                            isValid = false
                        }
                    }
                case (let rows as [[ActionUIElement]]):
                    for (rIndex, row) in rows.enumerated() {
                        for (cIndex, child) in row.enumerated() {
                            if !validateElement(child, path: "\(path)/\(key)[\(rIndex)][\(cIndex)]", seenIDs: &seenIDs) {
                                isValid = false
                            }
                        }
                    }
                case (let child as ActionUIElement):
                    if !validateElement(child, path: "\(path)/\(key)", seenIDs: &seenIDs) {
                        isValid = false
                    }
                default:
                    return false // Type mismatch or unsupported type
                }
            }
        }

        return isValid
    }
        
    // must ensure unique view ids in the whole view tree
    func verifyUniqueIDs(json: [String: Any], seenIDs: inout Set<Int>, logger: any ActionUILogger) throws {
		if let id = json["id"] as? Int {
			if seenIDs.contains(id) {
				throw NSError(domain: "ActionUIVerifier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Duplicate ID \(id) found"])
			}
			seenIDs.insert(id)
		}
		if let children = json["children"] as? [[String: Any]] {
			for child in children {
				try verifyUniqueIDs(json: child, seenIDs: &seenIDs, logger: logger)
			}
		}
		if let rows = (json["properties"] as? [String: Any])?["rows"] as? [[[String: Any]]] {
			for row in rows {
				for cell in row {
					try verifyUniqueIDs(json: cell, seenIDs: &seenIDs, logger: logger)
				}
			}
		}
	}
}

// Custom logger for verifier tool
private class VerifierLogger: ActionUILogger {
    private var hasErrors = false
    private var hasWarnings = false
    
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {

        if level == .warning {
            fputs("warning: \(message)\n", stderr)
            hasWarnings = true
        } else if level == .error {
            fputs("error: \(message)\n", stderr)
            hasErrors = true
        }
    }
    
    var hadErrors: Bool {
        return hasErrors
    }

    var hadWarnings: Bool {
        return hasWarnings
    }
}

// Command-line entry point
@main
struct ActionUIVerifierMain {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            fputs("Usage: ./ActionUIVerifier <json_path_or_directory>\n", stderr)
            exit(1)
        }
        
        let verifier = ActionUIVerifier()
        let path = arguments[1]
        let fileManager = FileManager.default
        let isDirectory: Bool
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        } catch {
            fputs("error: Cannot access path \(path): \(error)\n", stderr)
            exit(1)
        }

        let success = isDirectory ? verifier.verifyDirectory(path) : verifier.verify(jsonPath: path)
        if !success || verifier.hadErrors {
            fputs("error: Verification failed\n", stderr)
            exit(1)
        }
        
        var resultString: String = "OK"
        if(verifier.hadWarnings)
        {
            resultString = "OK-ish (had warnings, may not render as expected)"
        }
        
        fputs("\(resultString)\n", stdout)
        exit(0)
    }
}


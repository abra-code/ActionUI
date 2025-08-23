// Tools/ActionUIVerifier.swift
import Foundation
import ActionUI

@MainActor
struct ActionUIVerifier {
    private let logger: ActionUILogger
    
    init() {
        // Use a custom logger to print errors to stderr and track failure
        self.logger = VerifierLogger()
    }
    
    func verify(jsonPath: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            let element = try JSONDecoder().decode(StaticElement.self, from: data)
            return validateElement(element, path: jsonPath)
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
            logger.log("Failed to read directory: \(directoryPath)", .error)
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
    
    private func validateElement(_ element: any ActionUIElement, path: String) -> Bool {
        var isValid = true
        
        // Validate element type
        if !ActionUIRegistry.shared.isValidElementType(element.type) {
            logger.log("[\(path)] Invalid element type: \(element.type)", .error)
            isValid = false
        }
        
        // Validate properties
        let validatedProperties = ActionUIRegistry.shared.validateProperties(
            forElementType: element.type,
            properties: View.validateProperties(element.properties, logger: logger),
            logger: logger
        )
        
        // Check mandatory properties (example; customize as needed)
        let mandatoryProperties = mandatoryProperties(for: element.type)
        for property in mandatoryProperties {
            if validatedProperties[property] == nil {
                logger.log("[\(path)] Missing mandatory property '\(property)' for element type: \(element.type)", .error)
                isValid = false
            }
        }
        
        // Recursively validate children
        if let children = element.children {
            for (index, child) in children.enumerated() {
                if !validateElement(child, path: "\(path)/children[\(index)]") {
                    isValid = false
                }
            }
        }
        
        return isValid
    }
    
    // Define mandatory properties per element type
    private func mandatoryProperties(for type: String) -> [String] {
        // Example; customize based on your requirements
        switch type {
        case "Button":
            return ["label"]
        case "TextField":
            return ["placeholder"]
        case "Toggle":
            return ["label"]
        default:
            return []
        }
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
    
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        // Only print errors to stderr
        if level == .error {
            fputs("[ERROR] \(message)\n", stderr)
            hasErrors = true
        }
    }
    
    var hadErrors: Bool {
        return hasErrors
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
            fputs("Error: Cannot access path \(path): \(error)\n", stderr)
            exit(1)
        }
        
        let success = isDirectory ? verifier.verifyDirectory(path) : verifier.verify(jsonPath: path)
        exit(success ? 0 : 1)
    }
}


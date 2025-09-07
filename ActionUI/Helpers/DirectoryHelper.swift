// Common/DirectoryHelper.swift
/*
 DirectoryHelper.swift

 Helper for platform-specific file system operations, such as accessing the application support directory.
*/

import Foundation

@MainActor
public enum DirectoryHelper {
    // Returns a cache URL in Library/Application Support/ActionUI/[windowUUID]/[resourceName].[resourceExtension]
    public static func cacheURL(for windowUUID: String, resourceName: String, resourceExtension: String, logger: any ActionUILogger) -> URL? {
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.log("Unable to access application support directory", .error)
            return nil
        }
        let actionUIDir = appSupportDir.appendingPathComponent("ActionUI").appendingPathComponent(windowUUID)
        do {
            try fileManager.createDirectory(at: actionUIDir, withIntermediateDirectories: true)
            return actionUIDir.appendingPathComponent("\(resourceName).\(resourceExtension)")
        } catch {
            logger.log("Failed to create cache directory at \(actionUIDir): \(error)", .error)
            return nil
        }
    }
}

//
//  FileLoadableView.swift
//  ActionUI
//

import SwiftUI

// View for synchronous file-based loading (local file or bundle resource)
@MainActor
public struct FileLoadableView: SwiftUI.View {
    let fileURL: URL
    let windowUUID: String
    let isContentView: Bool
    let logger: any ActionUILogger
    
    private let element: ViewElement?
    private let error: Error?
    
    public init(fileURL: URL, windowUUID: String, isContentView: Bool, logger: any ActionUILogger) {
        self.fileURL = fileURL
        self.windowUUID = windowUUID
        self.isContentView = isContentView
        self.logger = logger
        
        // Perform synchronous loading in init
        do {
            let data = try Data(contentsOf: fileURL)
            let format = fileURL.pathExtension.lowercased() == "plist" ? "plist" : "json"
            logger.log("Determined format '\(format)' for file URL \(fileURL)", .debug)
            if isContentView {
                self.element = try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID)
            } else {
                self.element = try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID)
            }
            logger.log("Successfully loaded \(format) for LoadableView from file \(fileURL)", .debug)
            self.error = nil
        } catch {
            self.element = nil
            self.error = error
            logger.log("Failed to load description for LoadableView from file \(fileURL): \(error)", .error)
        }
    }
    
    public var body: some SwiftUI.View {
        if let error = error {
            SwiftUI.Text("Failed to load view: \(error.localizedDescription)")
                .foregroundStyle(.red)
        } else if let element = element,
                  let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                  let viewModel = windowModel.viewModels[element.id] {
            ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        } else {
            SwiftUI.Text("No content loaded")
        }
    }
}

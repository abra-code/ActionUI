// Common/ActionUIContentView.swift
/*
 ActionUIContentView.swift

 Default root view for an ActionUI window, responsible for loading a JSON description from the bundle or a URL
 and constructing an ActionUIView. Uses WindowModel from ActionUIModel for state management.
*/

import SwiftUI

@MainActor
public struct ActionUIContentView: SwiftUI.View {
    @StateObject internal var windowModel: WindowModel
    private let windowUUID: String
    private let resourceName: String
    private let resourceExtension: String
    private let url: URL?
    private let logger: any ActionUILogger

    // Designated initializer
    private init(windowModel: WindowModel, windowUUID: String, resourceName: String, resourceExtension: String, url: URL?, logger: any ActionUILogger) {
        self._windowModel = StateObject(wrappedValue: windowModel)
        self.windowUUID = windowUUID
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.url = url
        self.logger = logger
    }

    // Init for bundle resource
    public init(resourceName: String, resourceExtension: String = "json", bundle: Bundle = .main, windowUUID: String, logger: any ActionUILogger = ConsoleLogger(maxLevel: .verbose)) {
        if let bundleURL = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            // Reuse URL-based init for bundle resource
            self.init(url: bundleURL, windowUUID: windowUUID, logger: logger)
        } else {
            // Fallback if bundle resource is missing
            let windowModel = WindowModel(windowUUID: windowUUID, logger: logger)
            self.init(windowModel: windowModel, windowUUID: windowUUID, resourceName: resourceName, resourceExtension: resourceExtension, url: nil, logger: logger)
            logger.log("Failed to load \(resourceName).\(resourceExtension) from bundle", .error)
        }
    }

    // Init for file or network URL
    public init(url: URL, windowUUID: String, logger: any ActionUILogger = ConsoleLogger(maxLevel: .verbose)) {
        let actionUIModel = ActionUIModel.shared
        actionUIModel.setLogger(logger)

        // Handle file URL directly
        if url.isFileURL, let data = try? Data(contentsOf: url) {
            Self.loadDescriptionAndInitializeModel(data: data, format: url.pathExtension, windowUUID: windowUUID, logger: logger)
            let windowModel = actionUIModel.windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
            self.init(windowModel: windowModel, windowUUID: windowUUID, resourceName: url.deletingPathExtension().lastPathComponent, resourceExtension: url.pathExtension, url: url, logger: logger)
        } else {
            // Initialize empty WindowModel for network loading
            let windowModel = WindowModel(windowUUID: windowUUID, logger: logger)
            windowModel.isNetworkLoading = true // Set loading state for network URLs
            let resourceName = url.deletingPathExtension().lastPathComponent // Strip extension for network URLs
            let resourceExtension = url.pathExtension
            let cacheURL = DirectoryHelper.cacheURL(for: windowUUID, resourceName: resourceName, resourceExtension: "plist", logger: logger) ?? URL(fileURLWithPath: "")
            self.init(windowModel: windowModel, windowUUID: windowUUID, resourceName: resourceName, resourceExtension: resourceExtension, url: url, logger: logger)
            // Trigger network loading without capturing self
            Task {
                await Self.loadNetworkData(url: url, cacheURL: cacheURL, windowUUID: windowUUID, resourceExtension: resourceExtension, logger: logger)
                actionUIModel.windowModels[windowUUID]?.isNetworkLoading = false
            }
        }
    }

    // Shared helper to load description and update ActionUIModel
    private static func loadDescriptionAndInitializeModel(data: Data, format: String, windowUUID: String, logger: any ActionUILogger) {
        let actionUIModel = ActionUIModel.shared
        if actionUIModel.windowModels[windowUUID] == nil {
            do {
                _ = try actionUIModel.loadDescription(from: data, format: format, windowUUID: windowUUID)
            } catch {
                logger.log("Failed to parse data for windowUUID: \(windowUUID): \(error)", .error)
            }
        }
    }

    // Static helper to load network data and cache it
    private static func loadNetworkData(url: URL, cacheURL: URL, windowUUID: String, resourceExtension: String, logger: any ActionUILogger) async {
        let actionUIModel = ActionUIModel.shared
        // Try cached plist first
        if let data = try? Data(contentsOf: cacheURL) {
            loadDescriptionAndInitializeModel(data: data, format: "plist", windowUUID: windowUUID, logger: logger)
            actionUIModel.windowModels[windowUUID]?.isNetworkLoading = false
            return
        }
        // Fetch from network and cache as plist
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try actionUIModel.cacheAsBinaryPlist(data, format: resourceExtension, to: cacheURL, windowUUID: windowUUID)
            loadDescriptionAndInitializeModel(data: data, format: resourceExtension, windowUUID: windowUUID, logger: logger)
            actionUIModel.windowModels[windowUUID]?.isNetworkLoading = false
        } catch {
            logger.log("Failed to fetch or cache \(url): \(error)", .error)
            actionUIModel.windowModels[windowUUID]?.isNetworkLoading = false
        }
    }

    public var body: some SwiftUI.View {
        SwiftUI.Group {
            if let element = windowModel.element,
               let model = windowModel.viewModels[element.id] {
                ActionUIView(element: element, model: model, windowUUID: windowUUID)
            } else if windowModel.isNetworkLoading {
                SwiftUI.ProgressView()
            } else {
                SwiftUI.Text("Failed to load \(resourceName)")
            }
        }
    }
}

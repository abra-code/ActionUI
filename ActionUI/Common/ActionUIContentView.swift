// Common/ActionUIContentView.swift
/*
 ActionUIContentView.swift

 Default root view for an ActionUI window, responsible for loading a JSON description from the bundle or network
 and constructing an ActionUIView. Uses WindowModel from ActionUIModel for state management.
*/

import SwiftUI

@MainActor
public struct ActionUIContentView: SwiftUI.View {
    @StateObject private var windowModel: WindowModel
    private let windowUUID: String
    private let resourceName: String
    private let resourceExtension: String
    private let networkURL: URL?
    private let logger: any ActionUILogger
    @State private var isNetworkLoading = false

    // Init for bundle resource
    public init(resourceName: String, resourceExtension: String = "json", windowUUID: String = UUID().uuidString, logger: any ActionUILogger = ConsoleLogger(maxLevel: .verbose)) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.networkURL = nil
        self.windowUUID = windowUUID
        self.logger = logger
        self._isNetworkLoading = State(wrappedValue: false)

        // Initialize ActionUIModel and set logger
        let actionUIModel = ActionUIModel.shared
        actionUIModel.setLogger(logger)

        // Load element from bundle (creates WindowModel if needed)
        if actionUIModel.windowModels[windowUUID] == nil {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
               let data = try? Data(contentsOf: url) {
                do {
                    _ = try actionUIModel.loadDescription(from: data, format: resourceExtension, windowUUID: windowUUID)
                } catch {
                    logger.log("Failed to parse \(resourceName).\(resourceExtension) from bundle: \(error)", .error)
                }
            } else {
                logger.log("Failed to load \(resourceName).\(resourceExtension) from bundle", .error)
            }
        }

        // Retrieve WindowModel after loading
        let loadedModel = actionUIModel.windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        self._windowModel = StateObject(wrappedValue: loadedModel)
    }

    // Init for network URL
    public init(networkURL: URL, windowUUID: String = UUID().uuidString, logger: any ActionUILogger = ConsoleLogger(maxLevel: .verbose)) {
        self.resourceName = networkURL.lastPathComponent
        self.resourceExtension = networkURL.pathExtension
        self.networkURL = networkURL
        self.windowUUID = windowUUID
        self.logger = logger
        self._isNetworkLoading = State(wrappedValue: true)

        // Initialize ActionUIModel and set logger
        let actionUIModel = ActionUIModel.shared
        actionUIModel.setLogger(logger)

        // Initialize with empty WindowModel (network load in .task)
        self._windowModel = StateObject(wrappedValue: WindowModel(windowUUID: windowUUID, logger: logger))
    }

    public var body: some SwiftUI.View {
        SwiftUI.Group {
            if let element = windowModel.element,
               let viewModel = windowModel.viewModels[element.id] {
                ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            } else if isNetworkLoading {
                SwiftUI.ProgressView()
            } else {
                SwiftUI.Text("Failed to load \(resourceName)")
            }
        }
        .task {
            guard let networkURL else { return }
            isNetworkLoading = true
            // Get cache path
            let cacheURL = DirectoryHelper.cacheURL(for: windowUUID, resourceName: resourceName, resourceExtension: "plist", logger: logger) ?? URL(fileURLWithPath: "")
            // Try cached plist first
            if let data = try? Data(contentsOf: cacheURL) {
                do {
                    _ = try ActionUIModel.shared.loadDescription(from: data, format: "plist", windowUUID: windowUUID)
                    isNetworkLoading = false
                    return
                } catch {
                    logger.log("Failed to parse cached plist at \(cacheURL): \(error)", .error)
                }
            }
            // Fetch from network and cache as plist
            do {
                let (data, _) = try await URLSession.shared.data(from: networkURL)
                try ActionUIModel.shared.cacheAsBinaryPlist(data, format: resourceExtension, to: cacheURL, windowUUID: windowUUID)
                _ = try ActionUIModel.shared.loadDescription(from: data, format: resourceExtension, windowUUID: windowUUID)
                isNetworkLoading = false
            } catch {
                logger.log("Failed to fetch or cache \(networkURL): \(error)", .error)
                isNetworkLoading = false
            }
        }
    }
}

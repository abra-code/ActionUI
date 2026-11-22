// Core/ActionUIModel+Test.swift
@testable import ActionUI

extension ActionUIModel {
    static func resetForTesting() {
        shared.windowModels.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
        shared.trustPolicy = DefaultTrustPolicy()
        // The defaults, keeping the resource folder, which tests set and restore themselves.
        let folder = ActionUIConfiguration.current.resourceFolder
        var configuration = ActionUIConfiguration()
        configuration.resourceFolder = folder
        ActionUIConfiguration.replaceForTesting(configuration)
    }
}

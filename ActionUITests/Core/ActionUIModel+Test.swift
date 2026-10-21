// Core/ActionUIModel+Test.swift
@testable import ActionUI

extension ActionUIModel {
    static func resetForTesting() {
        shared.windowModels.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
    }
}

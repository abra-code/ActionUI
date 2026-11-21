// Core/ActionUIModel+Test.swift
@testable import ActionUI

extension ActionUIModel {
    static func resetForTesting() {
        shared.windowModels.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
        shared.trustPolicy = DefaultTrustPolicy()
        shared.loadBudget = ActionUILoadBudget(loads: 256, seconds: 60)
    }
}

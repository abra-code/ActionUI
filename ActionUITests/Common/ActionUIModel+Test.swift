// ActionUIModel+Test.swift (in Tests/Common/)
import SwiftUI
@testable import ActionUI

extension ActionUIModel {
    static func resetForTesting() {
        shared.windowModels.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
    }
}

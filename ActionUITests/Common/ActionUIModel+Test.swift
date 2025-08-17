// ActionUIModel+Test.swift (in Tests/Common/)
import SwiftUI
@testable import ActionUI

extension ActionUIModel {
    static func resetForTesting() {
        shared.descriptions.removeAll()
        shared.states.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
    }
}

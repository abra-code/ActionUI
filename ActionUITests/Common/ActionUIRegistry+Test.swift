// ActionUIRegistry+Test.swift (in Tests/Common/)
import SwiftUI
@testable import ActionUI

extension ActionUIRegistry {
    func resetForTesting() {
        registrations.removeAll()
        registerAllViews()
    }
}

// Helpers/PropertyListDecoder+Logger.swift

import Foundation

extension PropertyListDecoder {
    convenience init(logger: any ActionUILogger) {
        self.init()
        
        if let key = CodingUserInfoKey(rawValue: "logger") {
            self.userInfo[key] = logger
        }
    }
}

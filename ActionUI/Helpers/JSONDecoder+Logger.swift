// Helpers/JSONDecoder+Logger.swift

import Foundation

extension JSONDecoder {
    convenience init(logger: any ActionUILogger) {
        self.init()
        
        if let key = CodingUserInfoKey(rawValue: "logger") {
            self.userInfo[key] = logger
        }
    }
}

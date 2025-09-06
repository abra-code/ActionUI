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

extension Decoder {
    public var logger: ActionUILogger? {
        let key = CodingUserInfoKey(rawValue: "logger")
        return key.flatMap { self.userInfo[$0] as? ActionUILogger }
    }
}

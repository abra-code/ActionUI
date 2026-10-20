// Core/Helpers/JSONEncoder+Logger.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension JSONEncoder {
    convenience init(logger: any ActionUILogger) {
        self.init()
        
        if let key = CodingUserInfoKey(rawValue: "logger") {
            self.userInfo[key] = logger
        }
    }
}

extension Encoder {
    public var logger: ActionUILogger? {
        let key = CodingUserInfoKey(rawValue: "logger")
        return key.flatMap { self.userInfo[$0] as? ActionUILogger }
    }
}

// Core/Helpers/PropertyListDecoder+Logger.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension PropertyListDecoder {
    convenience init(logger: any ActionUILogger) {
        self.init()
        
        if let key = CodingUserInfoKey(rawValue: "logger") {
            self.userInfo[key] = logger
        }
    }
}

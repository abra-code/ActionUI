/*
 PropertyComparison.swift

 Helper functions for comparing properties in the ActionUI component library.
 Provides equality checks for [String: Any] dictionaries, supporting nested structures.
*/

import Foundation

// Utility for comparing properties in ActionUI elements
enum PropertyComparison {
    // Compares two [String: Any] dictionaries for equality
    static func arePropertiesEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        guard lhs.keys == rhs.keys else { return false }
        for (key, lhsValue) in lhs {
            guard let rhsValue = rhs[key] else { return false }
            switch (lhsValue, rhsValue) {
            case let (lhsString as String, rhsString as String):
                if lhsString != rhsString { return false }
            case let (lhsInt as Int, rhsInt as Int):
                if lhsInt != rhsInt { return false }
            case let (lhsBool as Bool, rhsBool as Bool):
                if lhsBool != rhsBool { return false }
            case let (lhsDouble as Double, rhsDouble as Double):
                if lhsDouble != rhsDouble { return false }
            case let (lhsDict as [String: Any], rhsDict as [String: Any]):
                if !arePropertiesEqual(lhsDict, rhsDict) { return false }
            case let (lhsArray as [Any], rhsArray as [Any]) where lhsArray.count == rhsArray.count:
                for (lhsItem, rhsItem) in zip(lhsArray, rhsArray) {
                    switch (lhsItem, rhsItem) {
                    case let (lhsStr as String, rhsStr as String):
                        if lhsStr != rhsStr { return false }
                    case let (lhsInt as Int, rhsInt as Int):
                        if lhsInt != rhsInt { return false }
                    case let (lhsBool as Bool, rhsBool as Bool):
                        if lhsBool != rhsBool { return false }
                    case let (lhsDouble as Double, rhsDouble as Double):
                        if lhsDouble != rhsDouble { return false }
                    case let (lhsDict as [String: Any], rhsDict as [String: Any]):
                        if !arePropertiesEqual(lhsDict, rhsDict) { return false }
                    case let (lhsArr as [Any], rhsArr as [Any]):
                        if !arePropertiesEqual(["array": lhsArr], ["array": rhsArr]) { return false }
                    case let (lhsElem as StaticElement, rhsElem as StaticElement):
                        if lhsElem != rhsElem { return false }
                    default:
                        return false
                    }
                }
            case let (lhsElem as StaticElement, rhsElem as StaticElement):
                if lhsElem != rhsElem { return false }
            default:
                return false
            }
        }
        return true
    }
}

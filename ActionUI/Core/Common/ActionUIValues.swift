// Core/Common/ActionUIValues.swift
/*
 Element values that every renderer shares, in place of a platform type: a Map's value is an
 ActionUICoordinate, not MapKit's CLLocationCoordinate2D. Each renderer converts to its own type
 where it draws.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A map coordinate in degrees: the value of a Map element (its center).
public struct ActionUICoordinate: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

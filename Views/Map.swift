/*
 Sample JSON for Map:
 {
   "type": "Map",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "coordinate": { "latitude": 37.33233141, "longitude": -122.0312186 }, // Optional: Dictionary with latitude/longitude, defaults to nil
     "showsUserLocation": true // Optional: Boolean for user location, defaults to false
   }
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import MapKit

struct Map: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let coordinate = validatedProperties["coordinate"] as? [String: Double] {
            let latitude = coordinate["latitude"] ?? 0.0
            let longitude = coordinate["longitude"] ?? 0.0
            validatedProperties["coordinate"] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        if validatedProperties["showsUserLocation"] == nil {
            validatedProperties["showsUserLocation"] = false
        } else if let showsUserLocation = validatedProperties["showsUserLocation"] as? Bool {
            validatedProperties["showsUserLocation"] = showsUserLocation
        } else {
            print("Warning: Map showsUserLocation must be a Boolean; defaulting to false")
            validatedProperties["showsUserLocation"] = false
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if canImport(MapKit)
        registry.register("Map") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let coordinate = properties["coordinate"] as? CLLocationCoordinate2D
            let showsUserLocation = properties["showsUserLocation"] as? Bool ?? false
            return AnyView(
                Map(coordinateRegion: .constant(coordinate.map { MKCoordinateRegion(center: $0, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)) } ?? MKCoordinateRegion()))
            )
        }
        #else
        registry.register("Map") { _, _, _ in
            print("Warning: Map requires MapKit")
            return AnyView(EmptyView())
        }
        #endif
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        #if canImport(MapKit)
        registry.register("coordinate") { view, properties in
            guard let coordinate = properties["coordinate"] as? CLLocationCoordinate2D else { return view }
            return AnyView(view.mapStyle(.standard).overlay(
                Map(coordinateRegion: .constant(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))),
                alignment: .center
            ))
        }
        registry.register("showsUserLocation") { view, properties in
            guard let showsUserLocation = properties["showsUserLocation"] as? Bool else { return view }
            return AnyView(view.mapStyle(.standard).showsUserLocation(showsUserLocation))
        }
        #endif
    }
}

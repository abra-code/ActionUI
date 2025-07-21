/*
 Sample JSON for Map:
 {
   "type": "Map",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "coordinate": { "latitude": 37.33233141, "longitude": -122.0312186 }, // Optional: Dictionary with latitude/longitude, defaults to nil
     "showsUserLocation": true // Optional: Boolean for user location, defaults to false
   }
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import MapKit

struct Map: ActionUIViewConstruction {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        #if canImport(MapKit)
        let coordinate = validatedProperties["coordinate"] as? CLLocationCoordinate2D
        return AnyView(
            SwiftUI.Map(coordinateRegion: .constant(coordinate.map { MKCoordinateRegion(center: $0, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)) } ?? MKCoordinateRegion()))
        )
        #else
        print("Warning: Map requires MapKit")
        return AnyView(SwiftUI.EmptyView())
        #endif
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        #if canImport(MapKit)
        var modifiedView = view
        if let coordinate = properties["coordinate"] as? CLLocationCoordinate2D {
            modifiedView = AnyView(modifiedView.mapStyle(.standard).overlay(
                Map(coordinateRegion: .constant(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))),
                alignment: .center
            ))
        }
        if let showsUserLocation = properties["showsUserLocation"] as? Bool {
            modifiedView = AnyView(modifiedView.mapStyle(.standard).showsUserLocation(showsUserLocation))
        }
        return modifiedView
        #else
        return view
        #endif
    }
}

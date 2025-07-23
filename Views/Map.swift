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
    // Design decision: Defines valueType as CLLocationCoordinate2D to reflect map's center coordinate for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { CLLocationCoordinate2D.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
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
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        #if canImport(MapKit)
        let initialCoordinate = (validatedProperties["coordinate"] as? CLLocationCoordinate2D) ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let showsUserLocation = validatedProperties["showsUserLocation"] as? Bool ?? false
        
        let regionBinding = Binding(
            get: {
                if let coord = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? CLLocationCoordinate2D {
                    return MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
                }
                return MKCoordinateRegion(center: initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            },
            set: { newRegion in
                state.wrappedValue[element.id] = ["value": newRegion.center]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Map(coordinateRegion: regionBinding, showsUserLocation: showsUserLocation)
        )
        #else
        print("Warning: Map requires MapKit")
        return AnyView(SwiftUI.EmptyView())
        #endif
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        #if canImport(MapKit)
        var modifiedView = view
        if let showsUserLocation = properties["showsUserLocation"] as? Bool {
            modifiedView = AnyView(modifiedView.mapStyle(.standard).showsUserLocation(showsUserLocation))
        }
        return modifiedView
        #else
        return view
        #endif
    }
}

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
    static var valueType: Any.Type { CLLocationCoordinate2D.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate coordinate
        if let coordinate = validatedProperties["coordinate"] as? [String: Double] {
            let latitude = coordinate["latitude"] ?? 0.0
            let longitude = coordinate["longitude"] ?? 0.0
            validatedProperties["coordinate"] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else if validatedProperties["coordinate"] != nil {
            logger.log("Map coordinate must be a dictionary with latitude/longitude Doubles; defaulting to (0.0, 0.0)", .warning)
            validatedProperties["coordinate"] = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        }
        
        // Validate showsUserLocation
        if validatedProperties["showsUserLocation"] == nil {
            validatedProperties["showsUserLocation"] = false
        } else if let showsUserLocation = validatedProperties["showsUserLocation"] as? Bool {
            validatedProperties["showsUserLocation"] = showsUserLocation
        } else {
            logger.log("Map showsUserLocation must be a Boolean; defaulting to false", .warning)
            validatedProperties["showsUserLocation"] = false
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if canImport(MapKit)
        let initialCoordinate = (properties["coordinate"] as? CLLocationCoordinate2D) ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let showsUserLocation = properties["showsUserLocation"] as? Bool ?? false
        
        // Initialize Map-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = initialCoordinate
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let regionBinding = Binding<MKCoordinateRegion>(
            get: {
                if let coord = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? CLLocationCoordinate2D {
                    return MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
                }
                return MKCoordinateRegion(center: initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            },
            set: { newRegion in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newRegion.center
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return MapKit.Map(coordinateRegion: regionBinding, showsUserLocation: showsUserLocation)
        #else
        logger.log("Map requires MapKit", .warning)
        return SwiftUI.EmptyView()
        #endif
    }
}

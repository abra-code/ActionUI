/*
 Sample JSON for Map:
 {
   "type": "Map",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "coordinate": { "latitude": 37.33233141, "longitude": -122.0312186 }, // Optional: Dictionary with latitude/longitude, defaults to nil
     "showsUserLocation": true, // Optional: Boolean for user location, defaults to false
     "interactionModes": ["pan", "zoom"], // Optional: Array of "pan", "zoom", "rotate", defaults to ["pan", "zoom", "rotate"]
     "annotations": [ // Optional: Array of annotations
       {
         "coordinate": { "latitude": 37.332, "longitude": -122.031 },
         "title": String?, // Optional
         "subtitle": String? // Optional
       }
     ]
   }
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Design decision: Uses modern Map initializer with MapCameraPosition and MapContentBuilder (macOS 14.0+, iOS 17.0+). Annotations use Annotation for title/subtitle support.
 }
*/

import SwiftUI
import MapKit

private extension CLLocationCoordinate2D {
    func isDifferent(from other: CLLocationCoordinate2D?) -> Bool {
        guard let other else { return true }
        return latitude != other.latitude || longitude != other.longitude
    }
}

struct Map: ActionUIViewConstruction {
    // Design decision: Defines valueType as CLLocationCoordinate2D to reflect map's center coordinate for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { CLLocationCoordinate2D.self }
    
    // Struct for annotation items
    private struct MapAnnotationItem: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let subtitle: String?
    }
    
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
        
        // Validate interactionModes
        let validModes = ["pan", "zoom", "rotate"]
        if let modes = validatedProperties["interactionModes"] as? [String] {
            let valid = modes.allSatisfy { validModes.contains($0) }
            if valid {
                validatedProperties["interactionModes"] = modes
            } else {
                logger.log("Map interactionModes must be an array of 'pan', 'zoom', 'rotate'; defaulting to all", .warning)
                validatedProperties["interactionModes"] = validModes
            }
        } else if validatedProperties["interactionModes"] != nil {
            logger.log("Map interactionModes must be an array; defaulting to all", .warning)
            validatedProperties["interactionModes"] = validModes
        } else {
            validatedProperties["interactionModes"] = validModes
        }
        
        // Validate annotations
        if let annotations = validatedProperties["annotations"] as? [[String: Any]] {
            let validatedAnnotations = annotations.compactMap { dict -> [String: Any]? in
                var validatedAnnotation: [String: Any] = [:]
                if let coord = dict["coordinate"] as? [String: Double] {
                    let latitude = coord["latitude"] ?? 0.0
                    let longitude = coord["longitude"] ?? 0.0
                    validatedAnnotation["coordinate"] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                } else {
                    logger.log("Map annotation coordinate invalid; skipping annotation", .warning)
                    return nil
                }
                if let title = dict["title"] as? String? {
                    validatedAnnotation["title"] = title
                } else if dict["title"] != nil {
                    logger.log("Map annotation title must be a String; defaulting to nil", .warning)
                }
                if let subtitle = dict["subtitle"] as? String? {
                    validatedAnnotation["subtitle"] = subtitle
                } else if dict["subtitle"] != nil {
                    logger.log("Map annotation subtitle must be a String; defaulting to nil", .warning)
                }
                return validatedAnnotation
            }
            validatedProperties["annotations"] = validatedAnnotations
        } else if validatedProperties["annotations"] != nil {
            logger.log("Map annotations must be an array of dictionaries; defaulting to empty", .warning)
            validatedProperties["annotations"] = []
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if canImport(MapKit)
        let initialCoordinate = (properties["coordinate"] as? CLLocationCoordinate2D) ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let showsUserLocation = properties["showsUserLocation"] as? Bool ?? false
        let interactionModes = (properties["interactionModes"] as? [String])?.reduce(MapInteractionModes()) { modes, mode in
            switch mode {
            case "pan": return modes.union(.pan)
            case "zoom": return modes.union(.zoom)
            case "rotate": return modes.union(.rotate)
            default: return modes
            }
        } ?? .all

        let annotations: [MapAnnotationItem] = (properties["annotations"] as? [[String: Any]])?.compactMap { dict in
            guard let coord = dict["coordinate"] as? CLLocationCoordinate2D else { return nil }
            return MapAnnotationItem(
                coordinate: coord,
                title: dict["title"] as? String,
                subtitle: dict["subtitle"] as? String
            )
        } ?? []

        var currentState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if currentState["value"] == nil {
            viewSpecificState["value"] = initialCoordinate
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = currentState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }

        func extractRegion(from pos: MapKit.MapCameraPosition) -> MKCoordinateRegion? {
            let children = Mirror(reflecting: pos).children
            for child in children {
                if let r = child.value as? MKCoordinateRegion { return r }
            }
            return nil
        }

        let positionBinding = Binding<MapKit.MapCameraPosition>(
            get: {
                if let coord = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? CLLocationCoordinate2D {
                    return .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
                }
                return .region(MKCoordinateRegion(center: initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
            },
            set: { newPosition in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                if let region = extractRegion(from: newPosition) {
                    let coord = region.center
                    newState["value"] = coord
                    newState["validatedProperties"] = properties
                    state.wrappedValue[element.id] = newState
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        Task { @MainActor in
                            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                }
            }
        )

        let actionID = properties["actionID"] as? String

        return MapKit.Map(
            position: positionBinding,
            bounds: nil,
            interactionModes: interactionModes,
            selection: Binding<Never?>(get: { nil }, set: { _ in })
        ) {
            if showsUserLocation {
                MapKit.UserAnnotation()
            }
            ForEach(annotations, id: \.id) { item in
                Annotation(item.title ?? "", coordinate: item.coordinate) {
                    SwiftUI.VStack(alignment: .leading, spacing: 2) {
                        if let title = item.title { SwiftUI.Text(title).font(.caption).bold() }
                        if let subtitle = item.subtitle { SwiftUI.Text(subtitle).font(.caption2) }
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            if let actionID = actionID {
                Task { @MainActor in
                    logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        }
        #else
        logger.log("Map requires MapKit", .warning)
        return SwiftUI.EmptyView()
        #endif
    }
}

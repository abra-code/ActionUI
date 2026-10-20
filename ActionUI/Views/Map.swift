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
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Design decision: Uses modern Map initializer with MapCameraPosition and MapContentBuilder. Annotations use Annotation for title/subtitle support.
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

extension [String: Any] {
    func coordinate(forKey key: String) -> CLLocationCoordinate2D? {
        if let coordinate = self[key] as? [String: Any],
           let latitude = coordinate.double(forKey: "latitude"),
           let longitude = coordinate.double(forKey: "longitude") {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return nil
    }
}

extension Map {
    /// Map's properties, parsed from the raw dictionary. Built at the start of every render.
    /// The map's value (the center coordinate) is not a property.
    struct Props: Sendable {
        struct Coordinate: Equatable, Sendable {
            var latitude: Double
            var longitude: Double

            init(latitude: Double, longitude: Double) {
                self.latitude = latitude
                self.longitude = longitude
            }

            /// nil unless the dictionary at `key` has numeric latitude and longitude.
            init?(_ properties: [String: Any], key: String) {
                guard let coordinate = properties[key] as? [String: Any],
                      let latitude = coordinate.double(forKey: "latitude"),
                      let longitude = coordinate.double(forKey: "longitude") else {
                    return nil
                }
                self.init(latitude: latitude, longitude: longitude)
            }
        }

        struct Annotation: Equatable, Sendable {
            var coordinate: Coordinate
            var title: String?
            var subtitle: String?
        }

        enum InteractionMode: String, Sendable, CaseIterable {
            case pan, zoom, rotate
        }

        var coordinate: Coordinate?
        var showsUserLocation = false
        /// The modes in the order given. All three when absent or when any entry is not a mode name.
        var interactionModes: [InteractionMode] = InteractionMode.allCases
        /// The annotations with a valid coordinate; one without is skipped.
        var annotations: [Annotation] = []
        var valueChangeActionID: String?
        var actionID: String?

        init(_ properties: [String: Any]) {
            coordinate = Coordinate(properties, key: "coordinate")
            showsUserLocation = properties["showsUserLocation"] as? Bool ?? false
            if let names = properties["interactionModes"] as? [String] {
                let modes = names.compactMap(InteractionMode.init(rawValue:))
                if modes.count == names.count {
                    interactionModes = modes
                }
            }
            annotations = (properties["annotations"] as? [[String: Any]] ?? []).compactMap { dictionary in
                guard let coordinate = Coordinate(dictionary, key: "coordinate") else { return nil }
                return Annotation(
                    coordinate: coordinate,
                    title: dictionary["title"] as? String,
                    subtitle: dictionary["subtitle"] as? String
                )
            }
            valueChangeActionID = properties["valueChangeActionID"] as? String
            actionID = properties["actionID"] as? String
        }
    }
}

struct Map: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    // Parses a JSON coordinate string {"latitude":…,"longitude":…} into CLLocationCoordinate2D.
    // Only invoked when contentType is non-nil (e.g. "json"); nil contentType falls through to generic path.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = { value, _, logger in
        guard let data = value.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = (dict["latitude"] as? NSNumber).map({ $0.doubleValue }),
              let lon = (dict["longitude"] as? NSNumber).map({ $0.doubleValue }) else {
            logger.log("Map: failed to parse coordinate JSON string", .warning)
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = { value, _, logger in
        guard let coord = value as? CLLocationCoordinate2D,
              let data = try? JSONSerialization.data(
                  withJSONObject: ["latitude": coord.latitude, "longitude": coord.longitude],
                  options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
    static var insertableContainers: [String: ContainerShape]? = nil

    // Design decision: Defines valueType as CLLocationCoordinate2D to reflect map's center coordinate for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type = CLLocationCoordinate2D.self
    
    // Struct for annotation items
    private struct MapAnnotationItem: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let subtitle: String?
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(MapKit)
        let props = Props(properties)
        let initialCoordinate = Self.initialValue(model) as? CLLocationCoordinate2D ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let showsUserLocation = props.showsUserLocation
        let interactionModes = props.interactionModes.reduce(MapInteractionModes()) { modes, mode in
            switch mode {
            case .pan: return modes.union(.pan)
            case .zoom: return modes.union(.zoom)
            case .rotate: return modes.union(.rotate)
            }
        }

        let annotations: [MapAnnotationItem] = props.annotations.map { annotation in
            MapAnnotationItem(
                coordinate: CLLocationCoordinate2D(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude),
                title: annotation.title,
                subtitle: annotation.subtitle
            )
        }
        
        @Sendable func extractRegion(from pos: MapKit.MapCameraPosition) -> MKCoordinateRegion? {
            let children = Mirror(reflecting: pos).children
            for child in children {
                if let r = child.value as? MKCoordinateRegion { return r }
            }
            return nil
        }

        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let valueChangeActionID = props.valueChangeActionID
        let positionBinding: Binding<MapKit.MapCameraPosition> = mainActorBinding(
            get: {
                if let coord = model.value as? CLLocationCoordinate2D {
                    return .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
                }
                return .region(MKCoordinateRegion(center: initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
            },
            set: { newPosition in
                if let region = extractRegion(from: newPosition) {
                    let coord = region.center
                    if let prevCoord = model.value as? CLLocationCoordinate2D,
                          prevCoord.latitude == coord.latitude,
                          prevCoord.longitude == coord.longitude {
                        return
                    }
                    // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                    // "publishing changes from within view updates" warning
                    DispatchQueue.main.async {
                        model.value = coord
                        if let valueChangeActionID {
                            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                }
            }
        )

        let actionID = props.actionID

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
                logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }
        #else
        logger.log("Map requires MapKit", .warning)
        return SwiftUI.EmptyView()
        #endif
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initalValue = model.value as? CLLocationCoordinate2D {
            return initalValue
        }
        let coordinate = Props(model.properties).coordinate
        return CLLocationCoordinate2D(latitude: coordinate?.latitude ?? 0.0, longitude: coordinate?.longitude ?? 0.0)
    }
}

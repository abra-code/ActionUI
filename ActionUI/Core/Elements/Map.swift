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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

struct Map: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    // Parses a JSON coordinate string {"latitude":...,"longitude":...} into an ActionUICoordinate.
    // Only invoked when contentType is non-nil (e.g. "json"); nil contentType falls through to generic path.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = { value, _, logger in
        guard let data = value.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = (dict["latitude"] as? NSNumber).map({ $0.doubleValue }),
              let lon = (dict["longitude"] as? NSNumber).map({ $0.doubleValue }) else {
            logger.log("Map: failed to parse coordinate JSON string", .warning)
            return nil
        }
        return ActionUICoordinate(latitude: lat, longitude: lon)
    }

    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = { value, _, logger in
        guard let coord = value as? ActionUICoordinate,
              let data = try? JSONSerialization.data(
                  withJSONObject: ["latitude": coord.latitude, "longitude": coord.longitude],
                  options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static var insertableContainers: [String: ContainerShape]? = nil

    // The map's center coordinate. A portable type, so every renderer shares it; the SwiftUI renderer
    // converts to and from CLLocationCoordinate2D.
    static var valueType: Any.Type = ActionUICoordinate.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initalValue = model.value as? ActionUICoordinate {
            return initalValue
        }
        let coordinate = Props(model.properties).coordinate
        return ActionUICoordinate(latitude: coordinate?.latitude ?? 0.0, longitude: coordinate?.longitude ?? 0.0)
    }
}

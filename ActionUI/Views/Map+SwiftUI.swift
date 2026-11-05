// SwiftUI rendering of Map; its portable part is in Core/Elements/Map.swift.

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

extension Map: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    /// The stored center in MapKit's type: the ActionUICoordinate the element stores, or a
    /// CLLocationCoordinate2D that a Swift host set with setElementValue.
    private static func storedCenter(_ value: Any?) -> CLLocationCoordinate2D? {
        if let center = value as? ActionUICoordinate {
            return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        }
        return value as? CLLocationCoordinate2D
    }

    // Struct for annotation items
    private struct MapAnnotationItem: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let label: String
    }

    /// An annotation's pin: a white map pin in a red circle, the look Android and the Web draw.
    private struct MapAnnotationPin: SwiftUI.View {
        var body: some SwiftUI.View {
            SwiftUI.Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(.white, .red)
        }
    }

    /// The text MapKit draws under an annotation's pin: the title and the subtitle on separate
    /// lines, or "" for neither. One Text, because MapKit uses only the first Text of a label.
    /// An empty title or subtitle is left out, as on Linux, so it adds no blank line.
    static func annotationLabel(title: String?, subtitle: String?) -> String {
        [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(MapKit)
        let props = Props(properties)
        let initialCoordinate = Self.storedCenter(Self.initialValue(model)) ?? CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
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
                label: Self.annotationLabel(title: annotation.title, subtitle: annotation.subtitle)
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
                if let coord = Self.storedCenter(model.value) {
                    return .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
                }
                return .region(MKCoordinateRegion(center: initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
            },
            set: { newPosition in
                if let region = extractRegion(from: newPosition) {
                    let coord = region.center
                    if let prevCoord = Self.storedCenter(model.value),
                          prevCoord.latitude == coord.latitude,
                          prevCoord.longitude == coord.longitude {
                        return
                    }
                    // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                    // "publishing changes from within view updates" warning
                    DispatchQueue.main.async {
                        model.value = ActionUICoordinate(latitude: coord.latitude, longitude: coord.longitude)
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
            // Each annotation is a red pin standing on its coordinate, with the title and subtitle
            // drawn by MapKit under it in its own label style (a halo, wrapping). The text is the
            // label, not the content: MapKit draws the label in any case, so text in the content
            // showed the title twice, and an annotation without text showed nothing.
            ForEach(annotations, id: \.id) { item in
                Annotation(coordinate: item.coordinate, anchor: .bottom) {
                    MapAnnotationPin()
                } label: {
                    SwiftUI.Text(item.label)
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
}

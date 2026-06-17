// MapContract.js — the provider-independent half of the `Map` element.
// Web port of ActionUIAndroid Helpers/MapContract.kt (+ CoordinateHelper.kt) and
// the shared contract Apple validates inline in ActionUI/Views/Map.swift. Canonical
// schema: Documentation/Schemas/Map.md.
//
// `Map` is provider-pluggable, the Android "link exactly one provider module"
// model: a provider self-registers as the "Map" element (register("Map", ...)) and
// owns the rendering, while THIS file owns the provider-independent contract that
// every provider must honor identically — the JSON validation and the coordinate
// value bridge. It registers nothing.
//
// Value bridge (valueType "string", Apple's contract): the value is the map's
// current center as a JSON coordinate string {"latitude":..,"longitude":..} (keys
// sorted, matching Apple's serializeValueToString .sortedKeys). A host
// setString re-centers; a user pan reports the new center back (a JS provider) and
// fires valueChangeActionID.
//
// Validation lives here and runs ONCE, at build time, inside each provider's
// buildView (resolveMapConfig) — the "validate where you read" discipline, so the
// warnings fire exactly once and a provider author calls one function. The web
// `validateProperties` for a Map provider is therefore a pass-through; baseline
// View modifiers (frame, cornerRadius, ...) still flow through it untouched.

// Parses a {latitude, longitude} dictionary into a coordinate, or null. Both
// fields must be finite numbers (Apple's double(forKey:) rejects strings). Mirrors
// Map.swift's coordinate(forKey:) and MapContract.kt's coordinateProperty.
export function parseCoordinate(dict) {
    if (dict === null || typeof dict !== "object" || Array.isArray(dict)) return null;
    const { latitude, longitude } = dict;
    if (typeof latitude !== "number" || !Number.isFinite(latitude)) return null;
    if (typeof longitude !== "number" || !Number.isFinite(longitude)) return null;
    return { latitude, longitude };
}

// Serializes a coordinate to the value-bridge string, keys sorted so `latitude`
// precedes `longitude` (Apple's .sortedKeys). The web's element value IS this
// string (valueType "string").
export function coordinateToValueString(coordinate) {
    return JSON.stringify({ latitude: coordinate.latitude, longitude: coordinate.longitude });
}

// Parses a value-bridge string back into a coordinate, or null on malformed input
// (bad JSON, missing/non-numeric fields, a non-object). Mirrors Map.swift's
// parseStringValue. Does not log — callers decide whether a bad host write warns.
export function parseCoordinateValueString(value) {
    if (typeof value !== "string") return null;
    let parsed;
    try {
        parsed = JSON.parse(value);
    } catch {
        return null;
    }
    return parseCoordinate(parsed);
}

// Coordinate equality (the value-bridge echo guard: tell a host write apart from
// the element's own report-back, the lastTracked pattern).
export function coordinatesEqual(a, b) {
    if (!a || !b) return a === b;
    return a.latitude === b.latitude && a.longitude === b.longitude;
}

// The seed for a Map's value: the `coordinate` property, or the zero coordinate.
// Mirrors mapInitialCoordinate (Kotlin) / Map.initialValue (Swift). Does not log.
export function mapInitialCoordinate(properties) {
    return parseCoordinate(properties?.coordinate) ?? { latitude: 0.0, longitude: 0.0 };
}

export const VALID_INTERACTION_MODES = ["pan", "zoom", "rotate"];

// Resolves and validates the Map properties into a typed config, mirroring
// Map.swift's validateProperties / MapContract.kt's resolveMapConfig warnings
// verbatim: an invalid coordinate is dropped, a non-Boolean showsUserLocation
// defaults to false, malformed interactionModes default to all, and annotations
// are validated per-entry (an invalid coordinate skips the annotation; a
// non-String title/subtitle is dropped). Pure aside from logging.
export function resolveMapConfig(properties, logger) {
    const config = {
        coordinate: null,
        showsUserLocation: false,
        interactionModes: VALID_INTERACTION_MODES.slice(),
        annotations: [],
        actionID: typeof properties?.actionID === "string" ? properties.actionID : null,
        valueChangeActionID: typeof properties?.valueChangeActionID === "string" ? properties.valueChangeActionID : null,
    };
    if (!properties || typeof properties !== "object") return config;

    if (properties.coordinate !== undefined) {
        const coordinate = parseCoordinate(properties.coordinate);
        if (coordinate) {
            config.coordinate = coordinate;
        } else {
            logger?.log("Map coordinate must be a dictionary with latitude/longitude numeric values", "warning");
        }
    }

    if (properties.showsUserLocation !== undefined) {
        if (typeof properties.showsUserLocation === "boolean") {
            config.showsUserLocation = properties.showsUserLocation;
        } else {
            logger?.log("Map showsUserLocation must be a Boolean; defaulting to false", "warning");
        }
    }

    if (properties.interactionModes !== undefined) {
        const modes = properties.interactionModes;
        if (Array.isArray(modes)) {
            if (modes.every((mode) => VALID_INTERACTION_MODES.includes(mode))) {
                config.interactionModes = modes.slice();
            } else {
                logger?.log("Map interactionModes must be an array of 'pan', 'zoom', 'rotate'; defaulting to all", "warning");
            }
        } else {
            logger?.log("Map interactionModes must be an array; defaulting to all", "warning");
        }
    }

    if (properties.annotations !== undefined) {
        if (Array.isArray(properties.annotations)) {
            for (const entry of properties.annotations) {
                const coordinate = parseCoordinate(entry && typeof entry === "object" ? entry.coordinate : undefined);
                if (!coordinate) {
                    logger?.log("Map annotation coordinate invalid; skipping annotation", "warning");
                    continue;
                }
                let title = null;
                if (entry.title !== undefined) {
                    if (typeof entry.title === "string") title = entry.title;
                    else logger?.log("Map annotation title must be a String; defaulting to nil", "warning");
                }
                let subtitle = null;
                if (entry.subtitle !== undefined) {
                    if (typeof entry.subtitle === "string") subtitle = entry.subtitle;
                    else logger?.log("Map annotation subtitle must be a String; defaulting to nil", "warning");
                }
                config.annotations.push({ coordinate, title, subtitle });
            }
        } else {
            logger?.log("Map annotations must be an array of dictionaries; defaulting to empty", "warning");
        }
    }

    return config;
}

// Sources/Interop/ShumateLibrary.swift
/*
 libshumate 1.x (GNOME's map widget for GTK 4, the one GNOME Maps uses), found and loaded at run time
 for Map, so ActionUI has no build or package dependency on it: an app that shows a map names
 libshumate-1.0-1 among its own package dependencies, and without the library a Map shows a
 placeholder naming that package. It is loaded the first time a Map is made and stays loaded for the
 life of the process. Its license (LGPL 2.1 or later) allows loading it so.

 The library's name carries its API version (1.0) and its ABI version (.so.1, the same from libshumate
 1.0 to 1.4 and later), and its functions carry no version, so a newer release keeps working with no
 change here. A later ABI version would mean a change in the C interface; the next few are tried in
 case these functions came through it unchanged. A new API version may change a function's
 arguments, which looking it up cannot tell, so only the API versions in apiVersions are loaded. Every
 function used is looked up, and a missing one disables Map as a whole, as a missing library does.

 No libshumate header is used: the C signatures are declared here, from libshumate 1.4's headers.
 The maps are GtkWidgets; libshumate's other objects (map sources, the viewport) are passed as
 opaque pointers.

 Tiles: OpenStreetMap's standard tiles (libshumate's "osm-mapnik" source), as Android's map-osm
 module shows, with the attribution OpenStreetMap requires drawn on the map. Their usage policy asks
 every app to identify itself in its requests' User-Agent, so loading sets libshumate's (one for the
 process) to the application's ID with ActionUI's version. libshumate keeps downloaded tiles in the
 user's cache folder ($XDG_CACHE_HOME/shumate) and honors the server's cache headers, as the policy
 also asks.
*/

import Glibc
import CAdwaita

@MainActor
final class ShumateLibrary {
    typealias SetText = @convention(c) (UnsafePointer<CChar>?) -> Void
    typealias NewObject = @convention(c) () -> OpaquePointer?
    typealias LookUp = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias NewWidget = @convention(c) () -> WidgetPointer?
    typealias SetObject = @convention(c) (WidgetPointer?, OpaquePointer?) -> Void
    typealias GetWidget = @convention(c) (WidgetPointer?) -> WidgetPointer?
    typealias GetObject = @convention(c) (WidgetPointer?) -> OpaquePointer?
    typealias SetFlag = @convention(c) (WidgetPointer?, gboolean) -> Void
    typealias CenterOn = @convention(c) (WidgetPointer?, gdouble, gdouble) -> Void
    typealias SetNumber = @convention(c) (OpaquePointer?, gdouble) -> Void
    typealias GetNumber = @convention(c) (OpaquePointer?) -> gdouble
    typealias GetCount = @convention(c) (OpaquePointer?) -> guint

    /// The API versions whose headers the C signatures here were checked against, newest first, each
    /// with the ABI version its library had then (1.0: libshumate 1.4, libshumate-1.0.so.1).
    static let apiVersions: [(api: String, abi: Int)] = [("1.0", 1)]

    /// The package that holds the library on Debian and Ubuntu, named to the user when it is missing.
    static let packageName = "libshumate-1.0-1"

    /// The map source every Map shows: OpenStreetMap's standard tiles.
    static let mapSourceID = "osm-mapnik"

    /// The loaded libshumate, or nil when none was found (or a test disabled it).
    static var shared: ShumateLibrary? {
        if disabledForTesting { return nil }
        if !searched {
            searched = true
            loaded = load()
        }
        return loaded
    }

    /// Tests run Map without libshumate with this set.
    static var disabledForTesting = false

    private static var searched = false
    private static var loaded: ShumateLibrary?

    /// shumate_set_user_agent (for the whole process)
    let setUserAgent: SetText
    /// shumate_map_source_registry_new_with_defaults, shumate_map_source_registry_get_by_id (owned by
    /// the registry)
    let newRegistry: NewObject
    let mapSource: LookUp
    /// shumate_simple_map_new: a map with its attribution, scale, zoom buttons and compass
    let newSimpleMap: NewWidget
    /// shumate_simple_map_set_map_source, _get_map (the ShumateMap inside, owned by the simple map),
    /// _get_viewport (owned by the simple map), _set_show_zoom_buttons
    let setMapSource: SetObject
    let map: GetWidget
    let viewport: GetObject
    let setShowZoomButtons: SetFlag
    /// shumate_map_center_on (no animation), shumate_map_set_zoom_on_double_click
    let centerOn: CenterOn
    let setZoomOnDoubleClick: SetFlag
    /// shumate_viewport_set_zoom_level, _get_zoom_level
    let setZoomLevel: SetNumber
    let zoomLevel: GetNumber
    /// shumate_location_get_latitude, _get_longitude (the viewport is a ShumateLocation: its center)
    let latitude: GetNumber
    let longitude: GetNumber
    /// shumate_map_source_get_tile_size, _get_min_zoom_level, _get_max_zoom_level
    let tileSize: GetCount
    let minZoomLevel: GetCount
    let maxZoomLevel: GetCount

    /// The registry that owns the map source; kept for the life of the process, as the library is.
    private var registry: OpaquePointer?

    private init?(_ library: UnsafeMutableRawPointer) {
        func function<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: type) }
        }
        guard let setUserAgent = function("shumate_set_user_agent", as: SetText.self),
              let newRegistry = function("shumate_map_source_registry_new_with_defaults", as: NewObject.self),
              let mapSource = function("shumate_map_source_registry_get_by_id", as: LookUp.self),
              let newSimpleMap = function("shumate_simple_map_new", as: NewWidget.self),
              let setMapSource = function("shumate_simple_map_set_map_source", as: SetObject.self),
              let map = function("shumate_simple_map_get_map", as: GetWidget.self),
              let viewport = function("shumate_simple_map_get_viewport", as: GetObject.self),
              let setShowZoomButtons = function("shumate_simple_map_set_show_zoom_buttons", as: SetFlag.self),
              let centerOn = function("shumate_map_center_on", as: CenterOn.self),
              let setZoomOnDoubleClick = function("shumate_map_set_zoom_on_double_click", as: SetFlag.self),
              let setZoomLevel = function("shumate_viewport_set_zoom_level", as: SetNumber.self),
              let zoomLevel = function("shumate_viewport_get_zoom_level", as: GetNumber.self),
              let latitude = function("shumate_location_get_latitude", as: GetNumber.self),
              let longitude = function("shumate_location_get_longitude", as: GetNumber.self),
              let tileSize = function("shumate_map_source_get_tile_size", as: GetCount.self),
              let minZoomLevel = function("shumate_map_source_get_min_zoom_level", as: GetCount.self),
              let maxZoomLevel = function("shumate_map_source_get_max_zoom_level", as: GetCount.self) else { return nil }
        self.setUserAgent = setUserAgent
        self.newRegistry = newRegistry
        self.mapSource = mapSource
        self.newSimpleMap = newSimpleMap
        self.setMapSource = setMapSource
        self.map = map
        self.viewport = viewport
        self.setShowZoomButtons = setShowZoomButtons
        self.centerOn = centerOn
        self.setZoomOnDoubleClick = setZoomOnDoubleClick
        self.setZoomLevel = setZoomLevel
        self.zoomLevel = zoomLevel
        self.latitude = latitude
        self.longitude = longitude
        self.tileSize = tileSize
        self.minZoomLevel = minZoomLevel
        self.maxZoomLevel = maxZoomLevel
    }

    /// The map source every Map shows (mapSourceID), owned by the library; nil, logged once, when the
    /// library has no source of that name.
    private(set) lazy var standardMapSource: OpaquePointer? = {
        if registry == nil {
            registry = newRegistry()
        }
        guard let source = mapSource(registry, Self.mapSourceID) else {
            ActionUIModel.shared.logger.log("libshumate has no map source '\(Self.mapSourceID)'; maps show no tiles", .warning)
            return nil
        }
        return source
    }()

    /// The User-Agent tile requests carry: the application's ID (else the program's name), then
    /// ActionUI's version, as OpenStreetMap's tile usage policy asks.
    static func userAgent(applicationID: String?, programName: String?) -> String {
        let name = [applicationID, programName].compactMap { $0 }.first { !$0.isEmpty } ?? "ActionUI-app"
        return "\(name) ActionUI/\(ActionUIVersion.string) libshumate"
    }

    /// The first library found, by API version (apiVersions) and then ABI version (the one checked, then
    /// the next few), when it carries every function used; nil otherwise.
    private static func load() -> ShumateLibrary? {
        for (api, checked) in apiVersions {
            for abi in checked...(checked + 3) {
                let name = "libshumate-\(api).so.\(abi)"
                guard let handle = dlopen(name, RTLD_NOW | RTLD_LOCAL) else { continue }
                if let library = ShumateLibrary(handle) {
                    let application = g_application_get_default()
                    let applicationID = application.flatMap { swiftString(g_application_get_application_id($0)) }
                    library.setUserAgent(userAgent(applicationID: applicationID, programName: swiftString(g_get_prgname())))
                    ActionUIModel.shared.logger.log("libshumate \(api) (\(name)) shows maps", .verbose)
                    return library
                }
                // Left loaded, and no other tried, as for WebKitGTK: its types are registered with
                // GObject once loaded.
                ActionUIModel.shared.logger.log("\(name) lacks a function ActionUI uses; Map shows a placeholder", .warning)
                return nil
            }
        }
        ActionUIModel.shared.logger.log("libshumate \(apiVersions.map(\.api).joined(separator: " or ")) is not installed (package \(packageName)); Map shows a placeholder", .warning)
        return nil
    }
}

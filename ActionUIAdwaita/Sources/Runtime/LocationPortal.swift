// Sources/Runtime/LocationPortal.swift
/*
 The user's location for Map's showsUserLocation, from the desktop's location portal
 (org.freedesktop.portal.Location on the session bus; xdg-desktop-portal serves it from GeoClue, the
 system's location service). GIO's D-Bus calls only: no library beyond GTK's own.

 One portal session for the process, shared by every map that shows the location: it is opened when
 the first map starts listening and closed when the last one stops, so the desktop's location
 indicator (GNOME shows one in its top bar) is on only while a map shows the location. A map that
 starts listening while a location is known gets it at once.

 What the portal does, measured with xdg-desktop-portal 1.20 and GeoClue 2.7 on GNOME 48:
 - An app that is not sandboxed gets the location at once, with no dialog, whatever the user chose
   for it in the desktop's privacy settings; the first location comes within a fraction of a second.
 - With GNOME's Location Services off (its default) the session is refused; without GeoClue the
   portal answers that it failed. Either way there is no location, logged once per session.
 - Turning Location Services off during a session sends nothing: no update, no end. Updates resume
   when it is turned back on. A refused session is not tried again until a map starts listening
   after every map stopped. The portal's own end of a session (Session.Closed) is not listened to
   either.
*/

import CAdwaita

/// Where a map gets the user's location from: the portal, or a test's stand-in.
@MainActor protocol UserLocationSource: AnyObject {
    /// Sends each location to `update` until `stopUpdates` gets the token returned.
    func startUpdates(_ update: @escaping @MainActor (ActionUICoordinate) -> Void) -> Int
    func stopUpdates(_ token: Int)
}

@MainActor
final class LocationPortal: UserLocationSource {
    /// The source maps use; tests put a stand-in here.
    static var shared: any UserLocationSource = LocationPortal()

    private static let service = "org.freedesktop.portal.Desktop"
    private static let path = "/org/freedesktop/portal/desktop"
    private static let interface = "org.freedesktop.portal.Location"
    /// The portal's accuracy levels go from 0 (none) to 5 (exact).
    private static let exactAccuracy: guint32 = 5

    private var listeners: [Int: @MainActor (ActionUICoordinate) -> Void] = [:]
    private var nextToken = 1
    /// The latest location of the open session.
    private var latest: ActionUICoordinate?
    /// The open session: its bus, its object path once the portal made it, and the signals listened to.
    private var bus: OpaquePointer?
    private var session: String?
    private var subscriptions: [guint] = []
    /// Counts the sessions opened; an answer for one already closed finds a newer count.
    private var generation = 0

    func startUpdates(_ update: @escaping @MainActor (ActionUICoordinate) -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        listeners[token] = update
        if listeners.count == 1 {
            open()
        } else if let latest {
            update(latest)
        }
        return token
    }

    func stopUpdates(_ token: Int) {
        guard listeners.removeValue(forKey: token) != nil, listeners.isEmpty else { return }
        close()
    }

    // MARK: The session

    /// CreateSession, then Start; LocationUpdated then brings each location.
    private func open() {
        generation += 1
        let current = generation
        guard let bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, nil) else {
            ActionUIModel.shared.logger.log("Map: no desktop session bus, so no user location", .info)
            return
        }
        self.bus = bus
        let sessionToken = "actionui\(UInt32.random(in: 0...UInt32.max))"
        let requestToken = "actionui\(UInt32.random(in: 0...UInt32.max))"
        let sender = (swiftString(g_dbus_connection_get_unique_name(bus)) ?? "").dropFirst().replacing(".", with: "_")
        let requestPath = "\(Self.path)/request/\(sender)/\(requestToken)"

        subscriptions.append(subscribe(bus, interface: Self.interface, signal: "LocationUpdated", path: Self.path) { [weak self] parameters in
            guard let self, current == self.generation, let parameters else { return }
            self.received(parameters)
        })
        // Subscribed before Start, so the answer cannot come first.
        subscriptions.append(subscribe(bus, interface: "org.freedesktop.portal.Request", signal: "Response", path: requestPath) { [weak self] parameters in
            guard let self, current == self.generation else { return }
            let code = parameters.flatMap { Self.uint32(child: 0, of: $0) }
            if code != 0 {
                ActionUIModel.shared.logger.log("Map: the location portal gave no user location (answer \(code.map(String.init) ?? "unknown"))", .info)
            }
        })

        let options = Self.dictionary([
            ("session_handle_token", g_variant_new_string(sessionToken)),
            ("distance-threshold", g_variant_new_uint32(0)),
            ("time-threshold", g_variant_new_uint32(0)),
            ("accuracy", g_variant_new_uint32(Self.exactAccuracy)),
        ])
        var arguments: [OpaquePointer?] = [options]
        call(bus, Self.interface, "CreateSession", g_variant_new_tuple(&arguments, 1)) { [weak self] reply, error in
            let created = reply.flatMap { Self.objectPath(child: 0, of: $0) }
            if let reply { g_variant_unref(reply) }
            guard let self, current == self.generation else {
                // Closed while the portal made it: close it now.
                if let created { Self.closeSession(bus, created) }
                return
            }
            guard let created else {
                ActionUIModel.shared.logger.log("Map: the location portal refused a session (\(error ?? "no answer")), so no user location", .info)
                return
            }
            self.session = created
            let startOptions = Self.dictionary([("handle_token", g_variant_new_string(requestToken))])
            // No parent window: the portal asks nothing of an app that is not sandboxed.
            var startArguments: [OpaquePointer?] = [g_variant_new_object_path(created), g_variant_new_string(""), startOptions]
            self.call(bus, Self.interface, "Start", g_variant_new_tuple(&startArguments, 3)) { reply, error in
                if let reply { g_variant_unref(reply) }
                if let error, current == self.generation {
                    ActionUIModel.shared.logger.log("Map: the location portal did not start (\(error)), so no user location", .info)
                }
            }
        }
    }

    /// Stops listening, closes the session and forgets its location.
    private func close() {
        generation += 1
        latest = nil
        guard let bus else { return }
        for subscription in subscriptions {
            g_dbus_connection_signal_unsubscribe(bus, subscription)
        }
        subscriptions = []
        if let session {
            Self.closeSession(bus, session)
        }
        session = nil
        g_object_unref(UnsafeMutableRawPointer(bus))
        self.bus = nil
    }

    /// LocationUpdated(o session_handle, a{sv} location): for this session, sends Latitude and
    /// Longitude on to every listener.
    private func received(_ parameters: OpaquePointer) {
        let signalType = g_variant_type_new("(oa{sv})")!
        defer { g_variant_type_free(signalType) }
        guard let session, g_variant_is_of_type(parameters, signalType) != 0, Self.objectPath(child: 0, of: parameters) == session,
              let location = g_variant_get_child_value(parameters, 1) else { return }
        defer { g_variant_unref(location) }
        let doubleType = g_variant_type_new("d")!
        defer { g_variant_type_free(doubleType) }
        func number(_ key: String) -> Double? {
            guard let value = g_variant_lookup_value(location, key, doubleType) else { return nil }
            defer { g_variant_unref(value) }
            return g_variant_get_double(value)
        }
        guard let latitude = number("Latitude"), let longitude = number("Longitude"),
              latitude.isFinite, longitude.isFinite else { return }
        let coordinate = ActionUICoordinate(latitude: latitude, longitude: longitude)
        latest = coordinate
        for update in listeners.values {
            update(coordinate)
        }
    }

    // MARK: D-Bus

    private static func closeSession(_ bus: OpaquePointer, _ session: String) {
        g_dbus_connection_call(bus, service, session, "org.freedesktop.portal.Session", "Close", nil, nil,
                               G_DBUS_CALL_FLAGS_NONE, -1, nil, nil, nil)
    }

    /// Calls `method` on the portal; `completion` gets the reply (the caller owns it) or the error's
    /// message. The bus is kept until the answer.
    private func call(_ bus: OpaquePointer, _ interface: String, _ method: String, _ parameters: OpaquePointer?,
                      completion: @escaping @MainActor (OpaquePointer?, String?) -> Void) {
        g_object_ref(UnsafeMutableRawPointer(bus))
        let run: ReadyRun = { result in
            var error: UnsafeMutablePointer<GError>?
            let reply = g_dbus_connection_call_finish(bus, result, &error)
            var message: String?
            if let error {
                message = swiftString(error.pointee.message) ?? "unknown error"
                g_error_free(error)
            }
            completion(reply, message)
            g_object_unref(UnsafeMutableRawPointer(bus))
        }
        g_dbus_connection_call(bus, Self.service, Self.path, interface, method, parameters, nil, G_DBUS_CALL_FLAGS_NONE,
                               -1, nil, readyTrampoline, Unmanaged.passRetained(CallbackBox(run)).toOpaque())
    }

    /// Listens to the portal's `signal` on `path`; `run` gets its parameters.
    private func subscribe(_ bus: OpaquePointer, interface: String, signal: String, path: String,
                           _ run: @escaping BusSignalRun) -> guint {
        g_dbus_connection_signal_subscribe(bus, Self.service, interface, signal, path, nil, G_DBUS_SIGNAL_FLAGS_NONE,
                                           signalTrampoline, Unmanaged.passRetained(CallbackBox(run)).toOpaque(), releaseSignalBox)
    }

    /// An a{sv} of `entries`.
    private static func dictionary(_ entries: [(String, OpaquePointer?)]) -> OpaquePointer? {
        let entryType = g_variant_type_new("{sv}")!
        defer { g_variant_type_free(entryType) }
        var items: [OpaquePointer?] = entries.map { key, value in
            g_variant_new_dict_entry(g_variant_new_string(key), g_variant_new_variant(value))
        }
        return g_variant_new_array(entryType, &items, gsize(items.count))
    }

    private static func objectPath(child index: gsize, of tuple: OpaquePointer) -> String? {
        guard g_variant_n_children(tuple) > index, let value = g_variant_get_child_value(tuple, index) else { return nil }
        defer { g_variant_unref(value) }
        guard g_variant_classify(value) == G_VARIANT_CLASS_OBJECT_PATH else { return nil }
        return swiftString(g_variant_get_string(value, nil))
    }

    private static func uint32(child index: gsize, of tuple: OpaquePointer) -> guint32? {
        guard g_variant_n_children(tuple) > index, let value = g_variant_get_child_value(tuple, index) else { return nil }
        defer { g_variant_unref(value) }
        guard g_variant_classify(value) == G_VARIANT_CLASS_UINT32 else { return nil }
        return g_variant_get_uint32(value)
    }
}

/// A D-Bus signal's handler: runs with the signal's parameters.
private typealias BusSignalRun = @MainActor (OpaquePointer?) -> Void

/// GDBus's signal callback; its user data is a CallbackBox<BusSignalRun>, released by releaseSignalBox.
private let signalTrampoline: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                              UnsafePointer<CChar>?, OpaquePointer?, gpointer?) -> Void = { _, _, _, _, _, parameters, data in
    guard let data else { return }
    // Pointers are not Sendable; their addresses are. GDBus calls back on the main thread.
    let boxAddress = Int(bitPattern: data)
    let address = parameters.map { Int(bitPattern: UnsafeRawPointer($0)) }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: boxAddress) else { return }
        let box = Unmanaged<CallbackBox<BusSignalRun>>.fromOpaque(pointer).takeUnretainedValue()
        box.run(address.flatMap { OpaquePointer(bitPattern: $0) })
    }
}

/// GDBus's destroy notification for a signal subscription's box.
private let releaseSignalBox: @convention(c) (gpointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

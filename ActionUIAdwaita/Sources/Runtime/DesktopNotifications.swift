// Sources/Runtime/DesktopNotifications.swift
/*
 A desktop notification through org.freedesktop.Notifications on the session bus. GNOME, KDE and
 xfce4-notifyd answer it, and a process needs no .desktop file for it (unlike GNotification, which
 needs an application ID the desktop knows).

 - The body is markdown, kept to what the specification's body markup has and what a short notice
   needs: bold and italic. Code, strikethrough and links show as their text: a link in a
   notification opens without the window it came from. A server that does not list "body-markup"
   gets plain text, as the specification asks.
 - An optional heading goes first in the body, in bold, plain text, on a line of its own. A
   collapsed banner (GNOME) shows the summary and the start of the body on one line, so what must
   stay in view belongs in the summary.
 - A desktop entry's application ID ("desktop-entry" hint) lets the desktop show that entry's icon
   and name on the notification.
 - It is transient (not kept in the desktop's list of notifications), and is closed after its
   duration, whatever the server does with expire_timeout: GNOME ignores it, and keeps a banner up
   while the user is away, queuing the next ones behind it. `closeAll` closes the ones still open,
   for a program that ends before their time is up; otherwise GNOME would show them later.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
public enum DesktopNotifications {
    private static let service = "org.freedesktop.Notifications"
    private static let path = "/org/freedesktop/Notifications"
    /// How long a call waits for the notification server, in milliseconds. One that is not
    /// running fails at once; this bounds one that hangs.
    private static let callTimeout: gint = 5000
    /// The notifications shown and not closed yet, by the server's id.
    private static var openIDs: Set<guint32> = []

    /// Shows a notification from `appName`: `summary` first, then `heading` on a line of its own
    /// and `markdown`. Closes it after `seconds`. `desktopEntry`, the application ID of the
    /// program's desktop entry, lets the desktop show that entry's icon and name. `completion` runs
    /// once: nil when the desktop took the notification, otherwise why not.
    public static func show(appName: String, desktopEntry: String? = nil, summary: String, heading: String?, markdown: String,
                            seconds: Double, completion: @escaping @MainActor (String?) -> Void) {
        guard let bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, nil) else {
            completion("there is no desktop session bus to send a notification on")
            return
        }
        call(bus, "GetCapabilities", nil) { reply, error in
            guard let reply else {
                g_object_unref(UnsafeMutableRawPointer(bus))
                completion(error)
                return
            }
            let markup = capabilities(reply).contains("body-markup")
            g_variant_unref(reply)
            let text = body(heading: heading, markdown: markdown, markup: markup)
            notify(bus, appName: appName, desktopEntry: desktopEntry, summary: summary, body: text, seconds: seconds) { error in
                g_object_unref(UnsafeMutableRawPointer(bus))
                completion(error)
            }
        }
    }

    /// The body as the server shows it: with `markup`, the specification's markup with bold and
    /// italic only, escaped; without, plain text.
    static func body(heading: String?, markdown: String, markup: Bool) -> String {
        let attributed = MarkdownText.attributedString(markdown: markdown)
        var text = ""
        if let heading, !heading.isEmpty {
            text = (markup ? "<b>" + escaped(heading) + "</b>" : heading) + "\n"
        }
        for run in attributed.runs {
            let piece = String(attributed[run.range].characters)
            guard markup else {
                text += piece
                continue
            }
            var marked = escaped(piece)
            let style = run[MarkdownStyleAttribute.self] ?? []
            if style.contains(.italic) {
                marked = "<i>" + marked + "</i>"
            }
            if style.contains(.bold) {
                marked = "<b>" + marked + "</b>"
            }
            text += marked
        }
        return text
    }

    /// The text escaped for the specification's body markup. Only the entities GNOME Shell keeps
    /// (amp, lt, gt, quot, apos): it turns any other "&", a character reference such as "&#39;"
    /// included, into "&amp;", so the reference would show as typed. The control characters
    /// markup cannot hold are left out (a raw one fails Pango's parse, and GNOME then shows the
    /// whole body as escaped markup, tags and all).
    private static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                let value = scalar.value
                if value <= 0x8 || value == 0xB || value == 0xC || (value >= 0xE && value <= 0x1F)
                    || (value >= 0x7F && value <= 0x84) || (value >= 0x86 && value <= 0x9F) {
                    continue
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Notify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout),
    /// then CloseNotification with the id it returns, after `seconds`.
    private static func notify(_ bus: OpaquePointer, appName: String, desktopEntry: String?, summary: String, body: String,
                               seconds: Double, completion: @escaping @MainActor (String?) -> Void) {
        let hintType = g_variant_type_new("{sv}")!
        var hints: [OpaquePointer?] = [
            g_variant_new_dict_entry(g_variant_new_string("transient"), g_variant_new_variant(g_variant_new_boolean(1))),
        ]
        if let desktopEntry {
            hints.append(g_variant_new_dict_entry(g_variant_new_string("desktop-entry"),
                                                  g_variant_new_variant(g_variant_new_string(desktopEntry))))
        }
        let hintArray = g_variant_new_array(hintType, &hints, gsize(hints.count))
        g_variant_type_free(hintType)
        let stringType = g_variant_type_new("s")!
        let actions = g_variant_new_array(stringType, nil, 0)
        g_variant_type_free(stringType)
        var arguments: [OpaquePointer?] = [
            g_variant_new_string(appName), g_variant_new_uint32(0), g_variant_new_string(""),
            g_variant_new_string(summary), g_variant_new_string(body), actions, hintArray,
            g_variant_new_int32(gint32(min(seconds, 3600) * 1000)),
        ]
        let parameters = g_variant_new_tuple(&arguments, gsize(arguments.count))
        call(bus, "Notify", parameters) { reply, error in
            guard let reply else {
                completion(error)
                return
            }
            var id: guint32 = 0
            if let value = g_variant_get_child_value(reply, 0) {
                if g_variant_classify(value) == G_VARIANT_CLASS_UINT32 {
                    id = g_variant_get_uint32(value)
                }
                g_variant_unref(value)
            }
            g_variant_unref(reply)
            guard id != 0 else { return completion(nil) }
            openIDs.insert(id)
            completion(nil)
            g_object_ref(UnsafeMutableRawPointer(bus))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard openIDs.remove(id) != nil else {
                    g_object_unref(UnsafeMutableRawPointer(bus))
                    return
                }
                call(bus, "CloseNotification", closeParameters(id)) { reply, _ in
                    // Closed already, by the user or by the server, is an error here: nothing to do.
                    if let reply { g_variant_unref(reply) }
                    g_object_unref(UnsafeMutableRawPointer(bus))
                }
            }
        }
    }

    /// Closes every notification still open, and returns once the requests are sent, without
    /// waiting for answers: for a program about to end.
    public static func closeAll() {
        guard !openIDs.isEmpty, let bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, nil) else { return }
        for id in openIDs {
            g_dbus_connection_call(bus, service, path, service, "CloseNotification", closeParameters(id), nil,
                                   G_DBUS_CALL_FLAGS_NONE, callTimeout, nil, nil, nil)
        }
        openIDs.removeAll()
        g_dbus_connection_flush_sync(bus, nil, nil)
        g_object_unref(UnsafeMutableRawPointer(bus))
    }

    private static func closeParameters(_ id: guint32) -> OpaquePointer? {
        var arguments: [OpaquePointer?] = [g_variant_new_uint32(id)]
        return g_variant_new_tuple(&arguments, 1)
    }

    /// Calls `method` on the notification server; `completion` gets the reply (the caller owns it)
    /// or the error's message.
    private static func call(_ bus: OpaquePointer, _ method: String, _ parameters: OpaquePointer?,
                             completion: @escaping @MainActor (OpaquePointer?, String?) -> Void) {
        let run: ReadyRun = { result in
            var error: UnsafeMutablePointer<GError>?
            let reply = g_dbus_connection_call_finish(bus, result, &error)
            var message: String?
            if let error {
                message = "the desktop's notification service did not answer: " + (swiftString(error.pointee.message) ?? "unknown error")
                g_error_free(error)
            }
            completion(reply, reply == nil ? message ?? "the desktop's notification service did not answer" : nil)
        }
        g_dbus_connection_call(bus, service, path, service, method, parameters, nil, G_DBUS_CALL_FLAGS_NONE,
                               callTimeout, nil, readyTrampoline, Unmanaged.passRetained(CallbackBox(run)).toOpaque())
    }

    /// The strings in GetCapabilities's reply, (as).
    private static func capabilities(_ reply: OpaquePointer) -> Set<String> {
        guard let list = g_variant_get_child_value(reply, 0) else { return [] }
        defer { g_variant_unref(list) }
        let stringArray = g_variant_type_new("as")!
        defer { g_variant_type_free(stringArray) }
        guard g_variant_is_of_type(list, stringArray) != 0 else { return [] }
        var names: Set<String> = []
        for index in 0..<g_variant_n_children(list) {
            if let item = g_variant_get_child_value(list, index) {
                if let name = swiftString(g_variant_get_string(item, nil)) {
                    names.insert(name)
                }
                g_variant_unref(item)
            }
        }
        return names
    }
}

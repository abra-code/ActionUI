// Sources/Styling/SymbolNames.swift
/*
 SF Symbol names, as documents give them (systemName, systemImage), mapped to the symbolic icons of
 GNOME's Adwaita icon theme, which GTK recolors with the text color as SF Symbols are. The table
 covers the names ActionUI's examples and documentation use, and common relatives of them; every
 icon it names is in Adwaita 48 or libadwaita (a test checks the theme).

 A name the table lacks is looked up again without a ".fill" suffix, then without a ".circle" or
 ".square" one ("plus.circle.fill" finds "plus"): Adwaita draws no filled or enclosed variants. A
 name with a "-" is taken as an icon theme name already ("document-save-symbolic"), so a document
 can name a Linux icon with a ":linux" suffixed key. Anything else shows image-missing, logged
 once per name.
*/

@MainActor
enum SymbolNames {
    /// What an unknown symbol shows.
    static let missing = "image-missing-symbolic"

    private static var reportedMissing: Set<String> = []

    /// The icon theme name for `symbol`.
    static func iconName(_ symbol: String) -> String {
        if let name = lookup(symbol) {
            return name
        }
        if reportedMissing.insert(symbol).inserted {
            ActionUIModel.shared.logger.log("No Linux icon for the symbol \"\(symbol)\"; showing \(missing)", .warning)
        }
        return missing
    }

    /// The icon for `symbol` from the table and its fallbacks, nil when there is none.
    static func lookup(_ symbol: String) -> String? {
        if symbol.contains("-") {
            return symbol
        }
        var name = symbol
        while true {
            if let icon = table[name] {
                return icon + "-symbolic"
            }
            if let shorter = dropSuffix(name) {
                name = shorter
            } else {
                return nil
            }
        }
    }

    /// `name` without its last ".fill", ".circle" or ".square", nil when it has none of them.
    private static func dropSuffix(_ name: String) -> String? {
        for suffix in [".fill", ".circle", ".square"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return nil
    }

    /// SF Symbol name -> icon name without "-symbolic". Filled and enclosed variants come from the
    /// fallbacks, except where Adwaita has a distinct icon (star and star.fill).
    static let table: [String: String] = [
        // Stars, hearts, bookmarks, flags, pins
        "star": "non-starred",
        "star.fill": "starred",
        "star.slash": "non-starred",
        "star.circle": "starred",
        "heart": "emote-love",
        "bookmark": "user-bookmarks",
        "flag": "mail-mark-important",
        "pin": "view-pin",
        "mappin": "mark-location",
        "mappin.and.ellipse": "mark-location",
        "map": "mark-location",
        "location": "find-location",

        // Editing and documents
        "pencil": "document-edit",
        "square.and.pencil": "document-edit",
        "trash": "user-trash",
        "xmark.bin": "user-trash",
        "plus": "list-add",
        "minus": "list-remove",
        "plus.square.on.square": "edit-copy",
        "rectangle.on.rectangle": "edit-copy",
        "doc.on.doc": "edit-copy",
        "doc.on.clipboard": "edit-paste",
        "scissors": "edit-cut",
        "plus.rectangle.on.rectangle": "tab-new",
        "arrow.uturn.backward": "edit-undo",
        "arrow.uturn.forward": "edit-redo",
        "arrow.counterclockwise": "edit-undo",
        "arrow.clockwise": "view-refresh",
        "arrow.triangle.2.circlepath": "view-refresh",
        "square.and.arrow.down": "document-save",
        "square.and.arrow.up": "send-to",
        "doc": "text-x-generic",
        "doc.text": "text-x-generic",
        "text.document": "text-x-generic",
        "doc.richtext": "x-office-document",
        "newspaper": "x-office-document",
        "arrow.up.document": "document-send",
        "doc.badge.arrow.up": "document-send",
        "printer": "printer",
        "paperclip": "mail-attachment",
        "link": "insert-link",
        "character.cursor.ibeam": "insert-text",
        "bold": "format-text-bold",
        "italic": "format-text-italic",
        "underline": "format-text-underline",
        "strikethrough": "format-text-strikethrough",
        "text.alignleft": "format-justify-left",
        "text.aligncenter": "format-justify-center",
        "text.alignright": "format-justify-right",
        "tablecells": "x-office-spreadsheet",
        "calendar": "x-office-calendar",

        // Search, settings, information
        "magnifyingglass": "system-search",
        "plus.magnifyingglass": "zoom-in",
        "minus.magnifyingglass": "zoom-out",
        "gear": "preferences-system",
        "gearshape": "preferences-system",
        "gearshape.2": "preferences-system",
        "slider.horizontal.3": "preferences-other",
        "wrench.and.screwdriver": "applications-engineering",
        "info": "dialog-information",
        "info.circle": "dialog-information",
        "questionmark": "dialog-question",
        "questionmark.circle": "dialog-question",
        "exclamationmark.triangle": "dialog-warning",
        "exclamationmark.circle": "dialog-error",
        "exclamationmark.bubble": "dialog-warning",
        "checkmark": "object-select",
        "checkmark.circle": "object-select",
        "xmark": "window-close",
        "ellipsis": "view-more-horizontal",
        "ellipsis.circle": "view-more-horizontal",
        "line.3.horizontal": "open-menu",
        "line.3.horizontal.decrease": "view-sort-descending",
        "list.bullet": "view-list-bullet",
        "list.bullet.rectangle.portrait": "view-list-bullet",
        "list.number": "view-list-ordered",
        "square.grid.2x2": "view-grid",
        "square.grid.3x3": "view-app-grid",
        "sidebar.left": "sidebar-show",
        "sidebar.right": "sidebar-show-right",
        "arrow.up.left.and.arrow.down.right": "view-fullscreen",
        "arrow.down.right.and.arrow.up.left": "view-restore",
        "eye": "view-reveal",
        "eye.slash": "view-conceal",
        "lock": "changes-prevent",
        "lock.open": "changes-allow",
        "bell": "preferences-system-notifications",
        "bell.slash": "notifications-disabled",
        "clock": "preferences-system-time",
        "power": "system-shutdown",
        "rectangle.portrait.and.arrow.right": "system-log-out",
        "arrow.up.forward.app": "adw-external-link",

        // Arrows and chevrons
        "arrow.up": "go-up",
        "arrow.down": "go-down",
        "arrow.left": "go-previous",
        "arrow.right": "go-next",
        "arrow.up.to.line": "go-top",
        "arrow.down.to.line": "go-bottom",
        "chevron.up": "pan-up",
        "chevron.down": "pan-down",
        "chevron.left": "pan-start",
        "chevron.right": "pan-end",
        "arrowshape.turn.up.left": "mail-reply-sender",
        "arrowshape.turn.up.backward": "mail-reply-sender",
        "arrowshape.turn.up.right": "mail-forward",

        // Places, mail, people
        "house": "go-home",
        "folder": "folder",
        "folder.badge.plus": "folder-new",
        "archivebox": "package-x-generic",
        "shippingbox": "package-x-generic",
        "tray": "mail-send-receive",
        "tray.and.arrow.down": "folder-download",
        "envelope": "mail-unread",
        "envelope.open": "mail-read",
        "paperplane": "mail-send",
        "person": "avatar-default",
        "person.crop.circle": "avatar-default",
        "person.2": "system-users",
        "person.3": "system-users",
        "person.badge.plus": "contact-new",
        "book.closed": "accessories-dictionary",
        "globe": "web-browser",
        "network": "network-workgroup",
        "wifi": "network-wireless",
        "wifi.slash": "network-wireless-disabled",
        "terminal": "utilities-terminal",
        "keyboard": "input-keyboard",
        "desktopcomputer": "computer",
        "iphone": "phone",
        "externaldrive": "drive-harddisk",

        // Media
        "photo": "image-x-generic",
        "photo.on.rectangle": "image-x-generic",
        "play": "media-playback-start",
        "pause": "media-playback-pause",
        "stop": "media-playback-stop",
        "forward": "media-seek-forward",
        "backward": "media-seek-backward",
        "record.circle": "media-record",
        "circle": "radio",
        "circle.fill": "media-record",
        "music.note": "audio-x-generic",
        "film": "video-x-generic",
        "mic": "audio-input-microphone",
        "mic.slash": "microphone-disabled",
        "camera": "camera-photo",
        "video": "camera-video",
        "speaker.wave.2": "audio-volume-medium",
        "speaker.wave.3": "audio-volume-high",
        "speaker.slash": "audio-volume-muted",
        "paintbrush": "applications-graphics",
        "bolt": "thunderbolt",

        // Weather
        "cloud": "weather-overcast",
        "sun.max": "weather-clear",
        "moon": "weather-clear-night",
        "cloud.rain": "weather-showers",
        "snowflake": "weather-snow",
    ]
}

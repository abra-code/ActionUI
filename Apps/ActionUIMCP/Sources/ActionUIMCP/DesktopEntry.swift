// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// DesktopEntry.swift - the server's icon on the Linux desktop. GNOME (and other desktops on Wayland)
// shows a window's icon and name from the desktop entry whose file name is the window's application
// ID, not from anything the program sets, so without one the server's windows show a generic icon.
// `actionui-mcp --install-desktop-entry` writes that entry for the current user, hidden from the app
// list (the server is started by an MCP client, never by hand), with this executable's path and
// the icon beside it; `--uninstall-desktop-entry` removes it. Run it again after moving the server.
// The entry must exist before a window opens: the desktop matches a window to an entry when the
// window appears.

#if os(Linux)
import FoundationEssentials
import Glibc

enum DesktopEntry {
    /// The application ID of the server's and the keeper's windows, and the entry's file name.
    static let applicationID = "com.abracode.actionui.mcp"

    /// The icon: share/actionui/ActionUIMCP.svg beside the server's bin folder in the Linux
    /// package (Scripts/make-linux-mcp-package.sh), else the one in the checkout the server was
    /// built from. nil when neither is there.
    static var iconPath: String? {
        var candidates: [URL] = []
        if let executable = HostSupport.executablePath {
            candidates.append(URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("share/actionui/ActionUIMCP.svg"))
        }
        // This file is <package>/Sources/ActionUIMCP/DesktopEntry.swift.
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/ActionUIMCP.svg"))
        return candidates.map(\.path).first { FileManager.default.fileExists(atPath: $0) }
    }

    /// $XDG_DATA_HOME/applications/<applicationID>.desktop, XDG_DATA_HOME defaulting to
    /// ~/.local/share. nil when there is no home folder to put it in.
    static var entryPath: String? {
        let environment = ProcessInfo.processInfo.environment
        var dataHome = environment["XDG_DATA_HOME"] ?? ""
        // The specification ignores a relative XDG_DATA_HOME.
        if !dataHome.hasPrefix("/") {
            guard let home = environment["HOME"], home.hasPrefix("/") else { return nil }
            dataHome = home + "/.local/share"
        }
        return dataHome + "/applications/" + applicationID + ".desktop"
    }

    /// Writes the entry; returns what to tell the user, and whether it worked.
    static func install() -> (message: String, ok: Bool) {
        guard let path = entryPath else { return ("there is no home folder (HOME) to install the desktop entry in", false) }
        // A path that is not UTF-8 reads back with replacement characters: an entry naming it
        // would name no file, and the desktop would ignore it.
        guard let executable = HostSupport.executablePath, FileManager.default.fileExists(atPath: executable) else {
            return ("the server's own path is unknown, or not one a desktop entry can name", false)
        }
        guard let icon = iconPath else { return ("the icon ActionUIMCP.svg is not beside the server (share/actionui)", false) }
        guard let exec = execValue(executable), let iconValue = stringValue(icon) else {
            return ("the server's path or its icon's holds a character a desktop entry cannot (a control character, or % in the server's)", false)
        }
        let text = """
            [Desktop Entry]
            Type=Application
            Name=ActionUI
            Comment=Windows an AI agent opens through the ActionUI MCP server
            Exec=\(exec)
            Icon=\(iconValue)
            Terminal=false
            NoDisplay=true

            """
        let file = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            return ("could not write \(path): \(error.displayText)", false)
        }
        return ("installed \(path): windows of a server started from now on show the ActionUI icon", true)
    }

    /// Removes the entry; nothing to remove is not an error.
    static func uninstall() -> (message: String, ok: Bool) {
        guard let path = entryPath else { return ("there is no home folder (HOME) to remove the desktop entry from", false) }
        guard FileManager.default.fileExists(atPath: path) else { return ("no desktop entry at \(path)", true) }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            return ("could not remove \(path): \(error.displayText)", false)
        }
        return ("removed \(path)", true)
    }

    /// A string value of a desktop entry: backslashes doubled; nil for a control character, which
    /// a one-line value cannot hold.
    private static func stringValue(_ text: String) -> String? {
        guard !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return text.replacing("\\", with: "\\\\")
    }

    /// The Exec value running `program` with no arguments: a path of plain characters as it is,
    /// else in double quotes with the characters the specification reserves escaped, then as a
    /// string value. nil for a "%": the specification writes it "%%", but GLib looks for the
    /// program before it expands that, finds none, and ignores the whole entry.
    private static func execValue(_ program: String) -> String? {
        guard !program.contains("%") else { return nil }
        let plain = program.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "/._+-".unicodeScalars.contains($0)
        }
        if plain { return program }
        var quoted = "\""
        for character in program {
            if "\"`$\\".contains(character) { quoted.append("\\") }
            quoted.append(character)
        }
        quoted.append("\"")
        return stringValue(quoted)
    }
}
#endif

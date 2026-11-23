// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(AppKit)
import AppKit
import Testing
@testable import ActionUIMCP

/// What SwiftUI does when ActionUI JSON sets a navigationTitle after the window opened: the window's
/// title replaced and its subtitle, the provenance line, cleared. The guard puts both back.
@MainActor @Test func aWindowKeepsTheHostsTitleAndProvenanceLine() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                          backing: .buffered, defer: true)
    window.title = "Report"
    window.subtitle = "Requested by Agent"
    let held = WindowTitleGuard(window: window, title: "Report", subtitle: "Requested by Agent")
    window.title = "Software Update\nRequested by Apple"
    window.subtitle = ""
    #expect(window.title == "Report")
    #expect(window.subtitle == "Requested by Agent")
    withExtendedLifetime(held) {}
}
#endif

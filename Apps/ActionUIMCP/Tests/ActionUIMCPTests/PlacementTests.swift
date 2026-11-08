// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(AppKit)
import AppKit
import Testing
@testable import ActionUIMCP

@Test func shortTitlesKeepTheirMenuName() {
    #expect(AppKitPlatform.menuTitle("ActionUI: short note") == "ActionUI: short note")
    let exact = String(repeating: "x", count: AppKitPlatform.maxMenuTitleLength)
    #expect(AppKitPlatform.menuTitle(exact) == exact)
}

@Test func longTitlesLoseTheirMiddle() {
    let title = "ActionUI: ActionUIRemote clients: perform_action, performAction, actionui_perform_action"
    let name = AppKitPlatform.menuTitle(title)
    #expect(name.count <= AppKitPlatform.maxMenuTitleLength)
    #expect(name.hasPrefix("ActionUI: ActionUIRemote cli"))
    #expect(name.hasSuffix("actionui_perform_action"))
    #expect(name.contains("\u{2026}"))
}

@Test func cascadeStepsRightAndDown() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let next = AppKitPlatform.nextCascadePoint(after: NSPoint(x: 100, y: 800), size: NSSize(width: 400, height: 300), in: visible)
    #expect(next == NSPoint(x: 100 + AppKitPlatform.cascadeStep, y: 800 - AppKitPlatform.cascadeStep))
}

@Test func cascadeGoesBackToTheTopAtTheBottom() {
    let visible = NSRect(x: 0, y: 40, width: 1440, height: 860)
    let next = AppKitPlatform.nextCascadePoint(after: NSPoint(x: 100, y: 750), size: NSSize(width: 900, height: 700), in: visible)
    #expect(next == NSPoint(x: 100 + AppKitPlatform.cascadeStep, y: visible.maxY))
}

@Test func cascadeGoesBackToTheLeftAtTheRight() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let next = AppKitPlatform.nextCascadePoint(after: NSPoint(x: 530, y: 800), size: NSSize(width: 900, height: 300), in: visible)
    #expect(next == NSPoint(x: visible.minX, y: 800 - AppKitPlatform.cascadeStep))
}

@Test func cascadeComesBackOnScreenAtTheLeft() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let next = AppKitPlatform.nextCascadePoint(after: NSPoint(x: -300, y: 800), size: NSSize(width: 900, height: 300), in: visible)
    #expect(next == NSPoint(x: visible.minX, y: 800 - AppKitPlatform.cascadeStep))
}
#endif

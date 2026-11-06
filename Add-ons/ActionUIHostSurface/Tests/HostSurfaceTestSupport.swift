// Add-ons/ActionUIHostSurface/Tests/HostSurfaceTestSupport.swift
//
// Shared helpers for the HostSurface tests: clients that record what they are told (a Swift delegate
// and a C delegate), windows on macOS and iOS, and a main-loop pump for the add-on's one-turn
// teardown decisions and SwiftUI's updates.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
import ActionUI
@testable import ActionUIHostSurface
#if os(macOS)
import AppKit
typealias TestWindow = NSWindow
#else
import UIKit
typealias TestWindow = UIWindow
#endif

/// A logger that keeps what it is handed, so a test can assert a warning fired.
final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var entries: [(String, LoggerLevel)] = []

    func log(_ message: String, _ level: LoggerLevel) {
        entries.append((message, level))
    }

    var warnings: [String] {
        entries.filter { $0.1 == .warning }.map(\.0)
    }
}

/// One event a client received.
struct RecordedEvent: Equatable, CustomStringConvertible {
    let event: HostSurfaceEvent
    let surfaceID: UInt64
    let viewID: Int
    let widthPixels: Int
    let heightPixels: Int

    var description: String { "\(event) #\(surfaceID) view \(viewID) \(widthPixels)x\(heightPixels)" }
}

/// A Swift client that records its events and frames, and can run code inside a callback.
@MainActor
final class RecordingClient: HostSurfaceDelegate {
    private(set) var received: [RecordedEvent] = []
    /// The kind of each surface event's surface, in order.
    private(set) var kinds: [AUIHostSurfaceKind] = []
    private(set) var frames: [UInt64] = []
    private(set) var inputs: [HostSurfaceInput] = []
    var onEvent: ((HostSurfaceInfo, HostSurfaceEvent) -> Void)?

    func hostSurface(_ surface: HostSurfaceInfo, event: HostSurfaceEvent) {
        kinds.append(surface.kind)
        received.append(RecordedEvent(event: event, surfaceID: surface.surfaceID, viewID: surface.viewID,
                                      widthPixels: surface.widthPixels, heightPixels: surface.heightPixels))
        onEvent?(surface, event)
    }

    func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double) {
        frames.append(surface.surfaceID)
    }

    func hostSurfaceInput(_ surface: HostSurfaceInfo, event: HostSurfaceInput) {
        inputs.append(event)
    }

    var events: [HostSurfaceEvent] { received.map(\.event) }
    var inputKinds: [AUIHostInputKind] { inputs.map(\.kind) }

    func clear() {
        received = []
        frames = []
        inputs = []
    }
}

/// A C client: an AUIHostSurfaceDelegate whose callbacks record into this object through userData.
@MainActor
final class RecordingCClient {
    struct Entry: Equatable {
        let surfaceID: UInt64
        let windowUUID: String
        let viewID: Int64
        let event: Int32
        let kind: Int32
        let hasHandle: Bool
        let widthPixels: UInt32
        let heightPixels: UInt32
    }

    /// One input event as the C callback saw it, with its strings copied during the callback.
    struct Input: Equatable {
        let kind: Int32
        let code: String
        let text: String?
        let structSize: UInt32
    }

    private(set) var entries: [Entry] = []
    private(set) var inputs: [Input] = []

    var userData: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    var delegate: AUIHostSurfaceDelegate {
        var delegate = AUIHostSurfaceDelegate()
        delegate.structSize = UInt32(MemoryLayout<AUIHostSurfaceDelegate>.size)
        delegate.surface = { surfaceID, windowUUID, viewID, event, info, userData in
            guard let userData, let info else {
                return
            }
            let client = Unmanaged<RecordingCClient>.fromOpaque(userData).takeUnretainedValue()
            let entry = Entry(surfaceID: surfaceID, windowUUID: windowUUID.map { String(cString: $0) } ?? "",
                              viewID: viewID, event: event, kind: info.pointee.kind,
                              hasHandle: info.pointee.handle != nil,
                              widthPixels: info.pointee.widthPixels, heightPixels: info.pointee.heightPixels)
            MainActor.assumeIsolated {
                client.entries.append(entry)
            }
        }
        delegate.input = { _, _, _, event, userData in
            guard let userData, let event else {
                return
            }
            let client = Unmanaged<RecordingCClient>.fromOpaque(userData).takeUnretainedValue()
            let input = Input(kind: event.pointee.kind, code: event.pointee.code.map { String(cString: $0) } ?? "<null>",
                              text: event.pointee.text.map { String(cString: $0) },
                              structSize: event.pointee.structSize)
            MainActor.assumeIsolated {
                client.inputs.append(input)
            }
        }
        return delegate
    }

    var events: [Int32] { entries.map(\.event) }
}

@MainActor
enum TestHost {
    /// Runs the main loop briefly: the add-on decides teardowns one turn after a detach, and SwiftUI
    /// applies model changes on the next update.
    static func pump(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func makeWindow(width: CGFloat = 400, height: CGFloat = 300) -> TestWindow {
        #if os(macOS)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
        #else
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.isHidden = false
        return window
        #endif
    }

    static func contentView(of window: TestWindow) -> HostSurfacePlatformView {
        #if os(macOS)
        return window.contentView!
        #else
        return window
        #endif
    }

    /// A surface view for (windowUUID, viewID), obtained like the representable does, in a new
    /// container that is not yet in a window.
    static func makeContainer(windowUUID: String, viewID: Int, properties: HostSurfaceProperties)
        -> HostSurfaceContainer {
        let key = HostSurfaceRegistry.Key(windowUUID: windowUUID, viewID: viewID)
        let surface = HostSurfaceRegistry.shared.obtainSurface(for: key, surfaceName: properties.surfaceName) {
            HostSurfaceView(windowUUID: windowUUID, viewID: viewID, properties: properties, model: nil,
                            logger: RecordingLogger())
        }
        return HostSurfaceContainer(surface: surface)
    }

    /// Puts a container into a window at the given size, as SwiftUI would.
    static func place(_ container: HostSurfaceContainer, in window: TestWindow,
                      width: CGFloat = 200, height: CGFloat = 100) {
        container.frame = CGRect(x: 10, y: 10, width: width, height: height)
        contentView(of: window).addSubview(container)
        #if os(iOS)
        container.layoutIfNeeded()
        #endif
    }

    static func resize(_ container: HostSurfaceContainer, width: CGFloat, height: CGFloat) {
        container.frame.size = CGSize(width: width, height: height)
        #if os(iOS)
        container.layoutIfNeeded()
        #endif
    }

    /// The scale a surface in this window reports.
    static func scale(of container: HostSurfaceContainer) -> Double {
        #if os(macOS)
        return Double(container.window?.backingScaleFactor ?? 1)
        #else
        return Double(container.surface.traitCollection.displayScale)
        #endif
    }

    static func close(_ window: TestWindow) {
        #if os(macOS)
        window.close()
        #else
        window.isHidden = true
        #endif
    }
}

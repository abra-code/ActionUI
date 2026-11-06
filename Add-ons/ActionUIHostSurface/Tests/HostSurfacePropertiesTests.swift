// Add-ons/ActionUIHostSurface/Tests/HostSurfacePropertiesTests.swift
//
// How the element reads its own properties: defaults, the required surfaceName, kinds this platform
// lacks, and ill-typed values (warn, then the default).

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
import ActionUI
@testable import ActionUIHostSurface

@MainActor
final class HostSurfacePropertiesTests: XCTestCase {

    func testDefaults() {
        let logger = RecordingLogger()
        let properties = HostSurfaceProperties(["surfaceName": "viewport"], logger: logger)
        XCTAssertEqual(properties, HostSurfaceProperties(surfaceName: "viewport"))
        XCTAssertEqual(properties.kind, .native)
        XCTAssertFalse(properties.continuous)
        XCTAssertTrue(properties.focusable)
        XCTAssertTrue(properties.opaque)
        XCTAssertEqual(properties.idealWidth, 320)
        XCTAssertEqual(properties.idealHeight, 240)
        XCTAssertEqual(logger.warnings, [])
    }

    func testAllProperties() {
        let logger = RecordingLogger()
        let properties = HostSurfaceProperties([
            "surfaceName": "canvas", "kind": "native", "continuous": true, "preferredFrameRate": 30,
            "focusable": false, "opaque": false, "hidden": true, "idealWidth": 640, "idealHeight": 480.5,
        ], logger: logger)
        XCTAssertEqual(properties, HostSurfaceProperties(
            surfaceName: "canvas", kind: .native, continuous: true, preferredFrameRate: 30, focusable: false,
            opaque: false, hidden: true, idealWidth: 640, idealHeight: 480.5))
        XCTAssertEqual(logger.warnings, [])
    }

    func testMissingOrEmptySurfaceNameWarns() {
        let missing = RecordingLogger()
        XCTAssertEqual(HostSurfaceProperties([:], logger: missing).surfaceName, "")
        XCTAssertEqual(missing.warnings.count, 1)
        let empty = RecordingLogger()
        XCTAssertEqual(HostSurfaceProperties(["surfaceName": ""], logger: empty).surfaceName, "")
        XCTAssertEqual(empty.warnings.count, 1)
        let number = RecordingLogger()
        XCTAssertEqual(HostSurfaceProperties(["surfaceName": 5], logger: number).surfaceName, "")
        XCTAssertEqual(number.warnings.count, 1)
    }

    func testKindsThisPlatformLacksAreUnsupported() {
        #if os(Linux)
        let lacking = ["vulkan"]
        let sink = HostSurfaceProperties(["surfaceName": "s", "kind": "sink"], logger: RecordingLogger())
        XCTAssertEqual(sink.kind, .native, "the frame sink is the native kind on Linux")
        XCTAssertEqual(HostSurfaceProperties(["surfaceName": "s", "kind": "gl"], logger: RecordingLogger()).kind, .gl)
        #else
        let lacking = ["sink", "gl", "vulkan"]
        #endif
        for name in lacking {
            let logger = RecordingLogger()
            let properties = HostSurfaceProperties(["surfaceName": "s", "kind": name], logger: logger)
            XCTAssertEqual(properties.kind, .unsupported(name))
            XCTAssertEqual(logger.warnings.count, 1, name)
        }
    }

    func testIllTypedValuesWarnAndUseTheDefault() {
        let logger = RecordingLogger()
        let properties = HostSurfaceProperties([
            "surfaceName": "s", "continuous": "yes", "focusable": 1, "preferredFrameRate": -5,
            "idealWidth": "wide", "idealHeight": true,
        ], logger: logger)
        XCTAssertEqual(properties, HostSurfaceProperties(surfaceName: "s"))
        XCTAssertEqual(logger.warnings.count, 5)
    }
}

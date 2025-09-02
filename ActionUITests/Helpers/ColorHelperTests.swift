import XCTest
import SwiftUI
@testable import ActionUI

final class ColorHelperTests: XCTestCase {
    func testResolveColorNamedColors() {
        // Test a few named colors
        XCTAssertEqual(ColorHelper.resolveColor("red"), Color.red)
        XCTAssertEqual(ColorHelper.resolveColor("blue"), Color.blue)
        XCTAssertEqual(ColorHelper.resolveColor("green"), Color.green)
        XCTAssertEqual(ColorHelper.resolveColor("accentcolor"), Color.accentColor)
        XCTAssertEqual(ColorHelper.resolveColor("primary"), Color.primary)
        XCTAssertEqual(ColorHelper.resolveColor("secondary"), Color.secondary)
        XCTAssertNil(ColorHelper.resolveColor("notacolor"))
    }

    func testResolveColorHexRGB() {
        // #RGB format
        let color = ColorHelper.resolveColor("#F00")
        // Red: 1, Green: 0, Blue: 0
        XCTAssertNotNil(color)
        // #0F0
        let green = ColorHelper.resolveColor("#0F0")
        XCTAssertNotNil(green)
        // #00F
        let blue = ColorHelper.resolveColor("#00F")
        XCTAssertNotNil(blue)
    }

    func testResolveColorHexRGBA() {
        // #RGBA format
        let color = ColorHelper.resolveColor("#F00F")
        XCTAssertNotNil(color)
        let color2 = ColorHelper.resolveColor("#0F08")
        XCTAssertNotNil(color2)
    }

    func testResolveColorHexRRGGBB() {
        // #RRGGBB format
        let color = ColorHelper.resolveColor("#FF0000")
        XCTAssertNotNil(color)
        let green = ColorHelper.resolveColor("#00FF00")
        XCTAssertNotNil(green)
        let blue = ColorHelper.resolveColor("#0000FF")
        XCTAssertNotNil(blue)
    }

    func testResolveColorHexRRGGBBAA() {
        // #RRGGBBAA format
        let color = ColorHelper.resolveColor("#FF000080")
        XCTAssertNotNil(color)
        let color2 = ColorHelper.resolveColor("#00FF0080")
        XCTAssertNotNil(color2)
    }

    func testResolveColorInvalid() {
        XCTAssertNil(ColorHelper.resolveColor("#GGGGGG"))
        XCTAssertNil(ColorHelper.resolveColor("#12345")) // Invalid length
        XCTAssertNil(ColorHelper.resolveColor(""))
        XCTAssertNil(ColorHelper.resolveColor("#"))
    }

    func testColorToHex() {
        // Opaque sRGB colors
        XCTAssertEqual(ColorHelper.colorToHex(Color(red: 1, green: 0, blue: 0)), "#FF0000")
        XCTAssertEqual(ColorHelper.colorToHex(Color(red: 0, green: 1, blue: 0)), "#00FF00")
        XCTAssertEqual(ColorHelper.colorToHex(Color(red: 0, green: 0, blue: 1)), "#0000FF")
        // Transparent sRGB color
        let transparentRed = Color(red: 1, green: 0, blue: 0, opacity: 0.5)
        // Accept both #FF000080 and #FF00007F due to rounding
        let hex = ColorHelper.colorToHex(transparentRed)
        XCTAssertTrue(hex == "#FF000080" || hex == "#FF00007F", "Transparent red hex should be #FF000080 or #FF00007F, got \(String(describing: hex))")
        // System colors (platform-dependent)
        // XCTAssertEqual(ColorHelper.colorToHex(Color.red), "#FF3A30") // iOS system red
        // XCTAssertEqual(ColorHelper.colorToHex(Color.green), "#28CD41") // iOS system green
        // XCTAssertEqual(ColorHelper.colorToHex(Color.blue), "#007AFF") // iOS system blue
        // Note: System colors may differ by platform and theme
    }

    func testResolveColorInvalidSemanticName() {
        // Not a supported semantic name for Color
        XCTAssertNil(ColorHelper.resolveColor("tertiary"))
        XCTAssertNil(ColorHelper.resolveColor("quaternary"))
        XCTAssertNil(ColorHelper.resolveColor("separator"))
        XCTAssertNil(ColorHelper.resolveColor("placeholder"))
        XCTAssertNil(ColorHelper.resolveColor("background")) // Not supported as Color
        XCTAssertNil(ColorHelper.resolveColor("foreground")) // Not supported as Color
    }

    func testResolveShapeStyleSemanticStyles() {
        // Supported semantic styles should not be nil
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("background"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("foreground"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("primary"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("secondary"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("tertiary"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("quaternary"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("separator"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("placeholder"))
    }

    func testResolveShapeStyleNamedColors() {
        // Named colors should resolve to Color (which is a ShapeStyle)
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("red"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("blue"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("green"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("accentcolor"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("primary"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("secondary"))
    }

    func testResolveShapeStyleHexColors() {
        // Hex colors should resolve to Color (which is a ShapeStyle)
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("#FF0000"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("#00FF00"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("#0000FF"))
        XCTAssertNotNil(ColorHelper.resolveShapeStyle("#FF000080"))
    }

    func testResolveShapeStyleInvalid() {
        // Unsupported semantic style or invalid color/hex
        XCTAssertNil(ColorHelper.resolveShapeStyle("notasemantic"))
        XCTAssertNil(ColorHelper.resolveShapeStyle("#GGGGGG"))
        XCTAssertNil(ColorHelper.resolveShapeStyle(""))
    }
}

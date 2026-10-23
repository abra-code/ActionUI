// Views/LayoutParityPixels.swift
/*
 Reads the frames of a layout parity fixture's Colors from a bitmap of it, as the Apple and web
 parity tests both do: each Color is its own "#RRGGBB" color, so its frame is the bounding box of
 the pixels of that color. Measuring paint, not views, leaves the renderers without test hooks.
*/

#if os(macOS)
import XCTest
import AppKit

enum LayoutParityPixels {
    /// One Color of a fixture: its element id and its sRGB components, 0...1.
    struct Leaf {
        let id: Int
        let red: Double, green: Double, blue: Double
    }

    /// The Colors of a document (id and "#RRGGBB" color).
    static func leaves(of document: Any) -> [Leaf] {
        var result: [Leaf] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["type"] as? String == "Color", let id = object["id"] as? Int,
                   let hex = (object["properties"] as? [String: Any])?["color"] as? String,
                   hex.count == 7, hex.hasPrefix("#"), let rgb = Int(hex.dropFirst(), radix: 16) {
                    result.append(Leaf(id: id, red: Double((rgb >> 16) & 0xFF) / 255,
                                       green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255))
                }
                object.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(document)
        return result
    }

    /// The root's fixed frame size, which every fixture's root has.
    static func rootSize(of document: Any, fixture: String) throws -> (width: Double, height: Double) {
        let frame = try XCTUnwrap(((document as? [String: Any])?["properties"] as? [String: Any])?["frame"] as? [String: Any],
                                  "\(fixture): the root needs a fixed frame")
        let width = try XCTUnwrap(frame["width"] as? Double ?? (frame["width"] as? Int).map(Double.init))
        let height = try XCTUnwrap(frame["height"] as? Double ?? (frame["height"] as? Int).map(Double.init))
        return (width, height)
    }

    /// Each leaf's frame, [x, y, width, height] in points, from `bitmap`, which shows the root at
    /// `width` points wide from its top leading corner. A leaf with no pixels has no frame.
    static func frames(in bitmap: NSBitmapImageRep, width: Double, leaves: [Leaf], fixture: String) -> [String: [Double]] {
        // Each leaf's color as the bitmap stores it (its color space may be Display P3, not sRGB).
        let targets: [(id: Int, components: [Double])] = leaves.compactMap { leaf in
            let color = NSColor(srgbRed: leaf.red, green: leaf.green, blue: leaf.blue, alpha: 1)
            guard let converted = color.usingColorSpace(bitmap.colorSpace) else { return nil }
            return (leaf.id, [converted.redComponent, converted.greenComponent, converted.blueComponent])
        }
        XCTAssertEqual(targets.count, leaves.count, "\(fixture): a color could not be converted")

        let pixelsWide = bitmap.pixelsWide
        let pixelsHigh = bitmap.pixelsHigh
        let scale = Double(pixelsWide) / width
        var bounds: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.9 else { continue }
                let components = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                // Blended edge pixels match no color closely and are left out.
                guard let match = targets.first(where: { target in
                    zip(target.components, components).allSatisfy { abs($0 - $1) < 0.06 }
                }) else { continue }
                let box = bounds[match.id] ?? (x, y, x, y)
                bounds[match.id] = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
            }
        }
        var frames: [String: [Double]] = [:]
        for (id, box) in bounds {
            let half = { (value: Double) in (value * 2).rounded() / 2 }
            frames[String(id)] = [half(Double(box.minX) / scale), half(Double(box.minY) / scale),
                                  half(Double(box.maxX - box.minX + 1) / scale), half(Double(box.maxY - box.minY + 1) / scale)]
        }
        return frames
    }
}
#endif

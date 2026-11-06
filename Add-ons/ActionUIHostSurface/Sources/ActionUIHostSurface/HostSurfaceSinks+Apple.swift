// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceSinks+Apple.swift
//
// The frame sink on Apple platforms ("kind": "sink"), the counterpart of HostSurfaceSinks+Adwaita.swift: the newest
// frame a client presented for each live sink surface, waiting for the main thread. actionUIHostSurfacePresentPixels
// runs on any thread and never waits for the main thread: it copies the pixels into a CGImage, puts it in the
// surface's slot (dropping a frame the main thread has not taken yet), and posts one main-queue task per slot at a
// time. The task hands the image to the surface view, which shows it as its sink layer's contents.
//
// A slot lives from the surface's "created" to its "destroyed"; presenting outside that returns false.

#if !os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreGraphics
import os
import CActionUIHostSurface

/// One presented frame, ready to show.
struct HostSurfaceFrame: @unchecked Sendable {
    let image: CGImage
}

enum HostSurfaceSinks {
    private struct Slot {
        var frame: HostSurfaceFrame?
        /// A main-queue task to take the frame is queued.
        var posted = false
    }

    private static let slots = OSAllocatedUnfairLock(initialState: [UInt64: Slot]())
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Opens the slot of a sink surface just announced. Main thread.
    static func open(_ surfaceID: UInt64) {
        slots.withLock { $0[surfaceID] = Slot() }
    }

    /// Closes the slot of a surface that got "destroyed": later presents return false. Main thread.
    static func close(_ surfaceID: UInt64) {
        slots.withLock { _ = $0.removeValue(forKey: surfaceID) }
    }

    static func isOpen(_ surfaceID: UInt64) -> Bool {
        slots.withLock { $0[surfaceID] != nil }
    }

    /// The Core Graphics layout of an AUIHostPixelFormat value, or nil.
    static func bitmapInfo(_ format: Int32) -> CGBitmapInfo? {
        switch format {
        case Int32(AUIHostPixelBGRA8Premultiplied.rawValue):
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case Int32(AUIHostPixelRGBA8Premultiplied.rawValue):
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        case Int32(AUIHostPixelBGRX8.rawValue):
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case Int32(AUIHostPixelRGBX8.rawValue):
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        default:
            return nil
        }
    }

    /// actionUIHostSurfacePresentPixels. Any thread.
    static func present(surfaceID: UInt64, width: Int, height: Int, stride: Int, format: Int32,
                        pixels: UnsafeRawPointer) -> Bool {
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max), stride >= width * 4,
              let bitmapInfo = bitmapInfo(format), isOpen(surfaceID) else {
            return false
        }
        // The last row needs only its pixels, so a client may hand a tightly cut buffer; the copy is whole rows,
        // as Core Graphics reads them.
        let (rows, rowsOverflow) = stride.multipliedReportingOverflow(by: height - 1)
        let (needed, neededOverflow) = rows.addingReportingOverflow(width * 4)
        let (copySize, copyOverflow) = stride.multipliedReportingOverflow(by: height)
        guard !rowsOverflow, !neededOverflow, !copyOverflow else {
            return false
        }
        // malloc, not Data(count:), so a size that cannot be had returns false (as on Linux) instead of trapping.
        // The padding after the last row's pixels is never read.
        guard let buffer = malloc(copySize) else {
            return false
        }
        buffer.copyMemory(from: pixels, byteCount: needed)
        guard let data = CFDataCreateWithBytesNoCopy(nil, buffer.assumingMemoryBound(to: UInt8.self), copySize,
                                                     kCFAllocatorMalloc) else {
            free(buffer)
            return false
        }
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                                  space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent) else {
            return false
        }
        let frame = HostSurfaceFrame(image: image)

        // The slot may have closed while the pixels were copied.
        let (stored, post) = slots.withLock { slots -> (Bool, Bool) in
            guard var slot = slots[surfaceID] else {
                return (false, false)
            }
            slot.frame = frame
            let post = !slot.posted
            slot.posted = true
            slots[surfaceID] = slot
            return (true, post)
        }
        guard stored else {
            return false
        }
        if post {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    deliver(surfaceID)
                }
            }
        }
        return true
    }

    /// Takes the newest frame of a surface and shows it. Main thread.
    @MainActor
    private static func deliver(_ surfaceID: UInt64) {
        let frame = slots.withLock { slots -> HostSurfaceFrame? in
            guard var slot = slots[surfaceID] else {
                return nil
            }
            let frame = slot.frame
            slot.frame = nil
            slot.posted = false
            slots[surfaceID] = slot
            return frame
        }
        guard let frame, let view = HostSurfaceRegistry.shared.liveSurface(surfaceID) else {
            return
        }
        view.show(frame)
    }
}

#endif

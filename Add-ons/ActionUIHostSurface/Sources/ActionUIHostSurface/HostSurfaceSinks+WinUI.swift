// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceSinks+WinUI.swift
//
// The frame sink's slots on Windows, as on Linux (HostSurfaceSinks+Adwaita.swift): the newest frame a client
// presented for each live surface, waiting for the main thread. actionUIHostSurfacePresentPixels runs on any thread
// and never waits for the main thread: it copies the pixels, as premultiplied BGRA with rows packed (what WinUI's
// WriteableBitmap takes), into the surface's slot (dropping a frame the main thread has not taken yet), and posts
// one main-thread task per slot at a time. The task hands the frame to the surface view
// (HostSurfaceView+WinUI.swift), which writes it into its image's bitmap.
//
// A slot lives from the surface's "created" to its "destroyed"; presenting outside that returns false.

#if os(Windows)

import FoundationEssentials
import Synchronization
import CActionUIHostSurface
import Dispatch
// malloc, free: FoundationEssentials does not bring the C library on Windows.
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#endif

/// One presented frame: premultiplied BGRA pixels, rows width * 4 bytes apart, which this value owns until it is
/// shown or dropped.
struct HostSurfaceFrame: @unchecked Sendable {
    /// From malloc: a frame too large for the memory left is refused, where Swift's allocate would end the process.
    let pixels: UnsafeMutableRawBufferPointer
    let width: Int
    let height: Int

    /// Frees the pixels (shown, or dropped).
    func drop() {
        free(pixels.baseAddress)
    }
}

enum HostSurfaceSinks {
    private struct Slot {
        var frame: HostSurfaceFrame?
        /// A main-thread task to take the frame is queued.
        var posted = false
    }

    private static let slots = Mutex<[UInt64: Slot]>([:])

    /// The largest frame taken, in pixels a side: WinUI's bitmaps are GPU textures, which Direct3D limits to 16384.
    static let maximumSide = 16384

    /// Opens the slot of a surface just announced. Main thread.
    static func open(_ surfaceID: UInt64) {
        slots.withLock { $0[surfaceID] = Slot() }
    }

    /// Closes the slot of a surface that got "destroyed": later presents return false. Main thread.
    static func close(_ surfaceID: UInt64) {
        let dropped = slots.withLock { $0.removeValue(forKey: surfaceID)?.frame }
        dropped?.drop()
    }

    static func isOpen(_ surfaceID: UInt64) -> Bool {
        slots.withLock { $0[surfaceID] != nil }
    }

    /// How a format's pixels become premultiplied BGRA: swap red and blue, make alpha opaque.
    private struct Conversion {
        var swapsRedAndBlue: Bool
        var opaque: Bool
    }

    private static func conversion(_ format: Int32) -> Conversion? {
        switch format {
        case Int32(AUIHostPixelBGRA8Premultiplied.rawValue):
            return Conversion(swapsRedAndBlue: false, opaque: false)
        case Int32(AUIHostPixelRGBA8Premultiplied.rawValue):
            return Conversion(swapsRedAndBlue: true, opaque: false)
        case Int32(AUIHostPixelBGRX8.rawValue):
            return Conversion(swapsRedAndBlue: false, opaque: true)
        case Int32(AUIHostPixelRGBX8.rawValue):
            return Conversion(swapsRedAndBlue: true, opaque: true)
        default:
            return nil
        }
    }

    /// actionUIHostSurfacePresentPixels. Any thread.
    static func present(surfaceID: UInt64, width: Int, height: Int, stride: Int, format: Int32,
                        pixels: UnsafeRawPointer) -> Bool {
        // The side bound also keeps every product below from overflowing (16384 * 16384 * 4 is 2^30).
        guard width > 0, height > 0, width <= maximumSide, height <= maximumSide, stride >= width * 4,
              let conversion = conversion(format), isOpen(surfaceID) else {
            return false
        }
        // The client's buffer: the last row needs only its pixels, so a client may hand a tightly cut buffer.
        let (rows, rowsOverflow) = stride.multipliedReportingOverflow(by: height - 1)
        guard !rowsOverflow, !rows.addingReportingOverflow(width * 4).overflow else {
            return false
        }
        let rowBytes = width * 4
        guard let destination = malloc(rowBytes * height) else {
            return false
        }
        let copy = UnsafeMutableRawBufferPointer(start: destination, count: rowBytes * height)
        for row in 0..<height {
            let from = pixels + row * stride
            let to = destination + row * rowBytes
            if !conversion.swapsRedAndBlue && !conversion.opaque {
                to.copyMemory(from: from, byteCount: rowBytes)
                continue
            }
            // Byte by byte: the client's buffer need not be aligned.
            let source = from.assumingMemoryBound(to: UInt8.self)
            let target = to.assumingMemoryBound(to: UInt8.self)
            for pixel in 0..<width {
                let offset = pixel * 4
                let first = source[offset]
                let third = source[offset + 2]
                target[offset] = conversion.swapsRedAndBlue ? third : first
                target[offset + 1] = source[offset + 1]
                target[offset + 2] = conversion.swapsRedAndBlue ? first : third
                target[offset + 3] = conversion.opaque ? 0xFF : source[offset + 3]
            }
        }
        let frame = HostSurfaceFrame(pixels: copy, width: width, height: height)
        guard store(frame, for: surfaceID) else {
            frame.drop()
            return false
        }
        return true
    }

    /// Puts a frame in a surface's slot, dropping the one waiting there, and posts the main-thread task if none is
    /// queued. false, with the frame not taken, when the slot is closed. Any thread.
    private static func store(_ frame: HostSurfaceFrame, for surfaceID: UInt64) -> Bool {
        let (stored, replaced, post) = slots.withLock { slots -> (Bool, HostSurfaceFrame?, Bool) in
            guard var slot = slots[surfaceID] else {
                return (false, nil, false)
            }
            let replaced = slot.frame
            slot.frame = frame
            let post = !slot.posted
            slot.posted = true
            slots[surfaceID] = slot
            return (true, replaced, post)
        }
        replaced?.drop()
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
        guard let frame else {
            return
        }
        defer {
            frame.drop()
        }
        HostSurfaceRegistry.shared.liveSurface(surfaceID)?.show(frame)
    }
}

#endif

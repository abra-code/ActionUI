// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceSinks+Adwaita.swift
//
// The frame sink's slots on Linux: the newest frame a client presented for each live surface, waiting
// for the main thread. actionUIHostSurfacePresentPixels runs on any thread and never waits for the main
// thread: it copies the pixels, puts them in the surface's slot (dropping a frame the main thread has
// not taken yet), and posts one main-thread task per slot at a time. The task hands the frame to the
// surface view (HostSurfaceView+Adwaita.swift), which shows it as a GdkMemoryTexture.
//
// A slot lives from the surface's "created" to its "destroyed"; presenting outside that returns false.

#if os(Linux)

import FoundationEssentials
import Synchronization
import CAdwaita
import CActionUIHostSurface
import Dispatch

/// One presented frame: the copied pixels (a GBytes this value owns until it is shown or dropped).
struct HostSurfaceFrame: @unchecked Sendable {
    let bytes: OpaquePointer
    let width: Int
    let height: Int
    let stride: Int
    let format: GdkMemoryFormat

    func release() {
        g_bytes_unref(bytes)
    }
}

enum HostSurfaceSinks {
    private struct Slot {
        var frame: HostSurfaceFrame?
        /// A main-thread task to take the frame is queued.
        var posted = false
    }

    private static let slots = Mutex<[UInt64: Slot]>([:])

    /// Opens the slot of a surface just announced. Main thread.
    static func open(_ surfaceID: UInt64) {
        slots.withLock { $0[surfaceID] = Slot() }
    }

    /// Closes the slot of a surface that got "destroyed": later presents return false. Main thread.
    static func close(_ surfaceID: UInt64) {
        let dropped = slots.withLock { $0.removeValue(forKey: surfaceID)?.frame }
        dropped?.release()
    }

    static func isOpen(_ surfaceID: UInt64) -> Bool {
        slots.withLock { $0[surfaceID] != nil }
    }

    /// The GDK format of an AUIHostPixelFormat value, or nil.
    static func memoryFormat(_ format: Int32) -> GdkMemoryFormat? {
        switch format {
        case Int32(AUIHostPixelBGRA8Premultiplied.rawValue):
            return GDK_MEMORY_B8G8R8A8_PREMULTIPLIED
        case Int32(AUIHostPixelRGBA8Premultiplied.rawValue):
            return GDK_MEMORY_R8G8B8A8_PREMULTIPLIED
        case Int32(AUIHostPixelBGRX8.rawValue):
            return GDK_MEMORY_B8G8R8X8
        case Int32(AUIHostPixelRGBX8.rawValue):
            return GDK_MEMORY_R8G8B8X8
        default:
            return nil
        }
    }

    /// actionUIHostSurfacePresentPixels. Any thread.
    static func present(surfaceID: UInt64, width: Int, height: Int, stride: Int, format: Int32,
                        pixels: UnsafeRawPointer) -> Bool {
        // GdkMemoryTexture takes int sizes; the bound also keeps width * 4 from overflowing.
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max), stride >= width * 4,
              let memoryFormat = memoryFormat(format), isOpen(surfaceID) else {
            return false
        }
        // The last row needs only its pixels, so a client may hand a tightly cut buffer.
        let (rows, rowsOverflow) = stride.multipliedReportingOverflow(by: height - 1)
        let (size, sizeOverflow) = rows.addingReportingOverflow(width * 4)
        guard !rowsOverflow, !sizeOverflow else {
            return false
        }
        guard let copy = g_try_malloc(gsize(size)) else {
            return false
        }
        copy.copyMemory(from: pixels, byteCount: size)
        guard let bytes = g_bytes_new_take(copy, gsize(size)) else {
            g_free(copy)
            return false
        }
        let frame = HostSurfaceFrame(bytes: bytes, width: width, height: height, stride: stride, format: memoryFormat)

        // The slot may have closed while the pixels were copied.
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
        replaced?.release()
        guard stored else {
            frame.release()
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
        guard let view = HostSurfaceRegistry.shared.liveSurface(surfaceID) else {
            frame.release()
            return
        }
        view.show(frame)
    }
}

#endif

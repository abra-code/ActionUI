// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceSinks+Adwaita.swift
//
// The frame sink's slots on Linux: the newest frame a client presented for each live surface, waiting
// for the main thread. actionUIHostSurfacePresentPixels and actionUIHostSurfacePresentDmabuf run on any
// thread and never wait for the main thread: they put the frame (copied pixels, or the description of a
// dmabuf) in the surface's slot (dropping a frame the main thread has not taken yet), and post one
// main-thread task per slot at a time. The task hands the frame to the surface view
// (HostSurfaceView+Adwaita.swift), which shows it as a GdkMemoryTexture or a GdkDmabufTexture.
//
// A dmabuf stays the client's: its release callback runs on the main thread once GTK no longer reads it
// (the texture is finalized), or at once (on the main thread) for a frame dropped before it was shown.
//
// A slot lives from the surface's "created" to its "destroyed"; presenting outside that returns false.

#if os(Linux)

import FoundationEssentials
import Synchronization
import CAdwaita
import CActionUIHostSurface
import Dispatch

/// One presented frame.
enum HostSurfaceFrame: @unchecked Sendable {
    /// Copied pixels: a GBytes this value owns until it is shown or dropped.
    case pixels(bytes: OpaquePointer, width: Int, height: Int, stride: Int, format: GdkMemoryFormat)
    /// A client's dmabuf: handed back with its release callback once GTK no longer reads it.
    case dmabuf(HostSurfaceDmabuf)

    /// Lets go of a frame that will not be shown: frees the pixels, hands a dmabuf back.
    func drop() {
        switch self {
        case .pixels(let bytes, _, _, _, _):
            g_bytes_unref(bytes)
        case .dmabuf(let buffer):
            buffer.release()
        }
    }
}

/// A client's dmabuf frame, as presented (the struct copied), until its release callback is called.
final class HostSurfaceDmabuf: @unchecked Sendable {
    let buffer: AUIHostDmabuf

    init(_ buffer: AUIHostDmabuf) {
        self.buffer = buffer
    }

    /// The planes in use.
    var planes: [AUIHostDmabufPlane] {
        withUnsafeBytes(of: buffer.planes) { bytes in
            Array(bytes.bindMemory(to: AUIHostDmabufPlane.self).prefix(Int(buffer.planeCount)))
        }
    }

    /// Calls the client's release callback on the main thread (the header's promise), on a later turn.
    func release() {
        DispatchQueue.main.async {
            self.buffer.release?(self.buffer.releaseData)
        }
    }
}

enum HostSurfaceSinks {
    private struct Slot {
        var frame: HostSurfaceFrame?
        /// A main-thread task to take the frame is queued.
        var posted = false
    }

    private static let slots = Mutex<[UInt64: Slot]>([:])
    /// The dmabuf formats the display imports, read once on the main thread (GDK is main-thread only).
    private static let dmabufFormats = Mutex<[AUIHostDmabufFormat]?>(nil)

    /// Opens the slot of a surface just announced. Main thread.
    @MainActor
    static func open(_ surfaceID: UInt64) {
        loadDmabufFormats()
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
        let frame = HostSurfaceFrame.pixels(bytes: bytes, width: width, height: height, stride: stride,
                                            format: memoryFormat)
        guard store(frame, for: surfaceID) else {
            frame.drop()
            return false
        }
        return true
    }

    /// Puts a frame in a surface's slot, dropping the one waiting there, and posts the main-thread task if
    /// none is queued. false, with the frame not taken, when the slot is closed. Any thread.
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
        guard let view = HostSurfaceRegistry.shared.liveSurface(surfaceID) else {
            frame.drop()
            return
        }
        view.show(frame)
    }

    // MARK: dmabuf frames

    /// Reads the display's dmabuf formats the first time a surface opens. Main thread.
    @MainActor
    private static func loadDmabufFormats() {
        guard dmabufFormats.withLock({ $0 == nil }) else {
            return
        }
        // No display yet (GTK not set up): nothing to cache; the next open reads them.
        guard let display = gdk_display_get_default() else {
            return
        }
        var formats: [AUIHostDmabufFormat] = []
        if let list = gdk_display_get_dmabuf_formats(display) {
            let count = gdk_dmabuf_formats_get_n_formats(list)
            formats.reserveCapacity(Int(count))
            for index in 0..<count {
                var fourcc: guint32 = 0
                var modifier: guint64 = 0
                gdk_dmabuf_formats_get_format(list, index, &fourcc, &modifier)
                formats.append(AUIHostDmabufFormat(fourcc: fourcc, modifier: UInt64(modifier)))
            }
        }
        dmabufFormats.withLock { $0 = formats }
    }

    /// actionUIHostSurfaceCopyDmabufFormats. Any thread.
    static func copyDmabufFormats(surfaceID: UInt64, into out: UnsafeMutablePointer<AUIHostDmabufFormat>?,
                                  capacity: Int) -> Int {
        guard isOpen(surfaceID) else {
            return 0
        }
        let formats = dmabufFormats.withLock { $0 ?? [] }
        if let out {
            for (index, format) in formats.prefix(capacity).enumerated() {
                out[index] = format
            }
        }
        return formats.count
    }

    /// actionUIHostSurfacePresentDmabuf. Any thread.
    static func presentDmabuf(surfaceID: UInt64, buffer: AUIHostDmabuf) -> Bool {
        guard buffer.structSize == UInt32(MemoryLayout<AUIHostDmabuf>.size),
              buffer.width > 0, buffer.height > 0, buffer.width <= UInt32(Int32.max), buffer.height <= UInt32(Int32.max),
              (1...4).contains(buffer.planeCount), buffer.release != nil else {
            return false
        }
        let frame = HostSurfaceDmabuf(buffer)
        guard frame.planes.allSatisfy({ $0.fd >= 0 }) else {
            return false
        }
        let importable = dmabufFormats.withLock { formats in
            formats?.contains { $0.fourcc == buffer.fourcc && $0.modifier == buffer.modifier } ?? false
        }
        guard importable else {
            return false
        }
        // Not stored (the slot closed): false, and the client keeps its buffer without a release.
        return store(.dmabuf(frame), for: surfaceID)
    }
}

#endif

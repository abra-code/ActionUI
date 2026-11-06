// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceSinks+Apple.swift
//
// The frame sink on Apple platforms ("kind": "sink"), the counterpart of HostSurfaceSinks+Adwaita.swift: the newest
// frame a client presented for each live sink surface, waiting for the main thread. actionUIHostSurfacePresentPixels
// runs on any thread and never waits for the main thread: it copies the pixels into an IOSurface, puts it in the
// surface's slot (dropping a frame the main thread has not taken yet), and posts one main-queue task per slot at a
// time. The task hands the IOSurface to the surface view, which shows it as its sink layer's contents.
//
// Why an IOSurface and not a CGImage: Core Animation color matches a new sRGB CGImage to the display's color space
// on the CPU, on the main thread, at every commit (about 4.8 ms for a 960 x 480 frame on a Display P3 screen). An
// IOSurface tagged sRGB is matched by the render server on the GPU, with the same colors on screen, so a frame costs
// one copy.
//
// Each slot keeps a few IOSurfaces of the frame's size for reuse. A surface is written only when it is neither the
// shown one, nor the one waiting for the main thread (unless the writer takes that frame's place), nor still in use
// by the render server (IOSurfaceIsInUse).
//
// A slot lives from the surface's "created" to its "destroyed"; presenting outside that returns false.

#if !os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreGraphics
import IOSurface
import os
import CActionUIHostSurface

/// One presented frame, ready to show: a BGRA, premultiplied, sRGB IOSurface no one writes to any more.
struct HostSurfaceFrame: @unchecked Sendable {
    let surface: IOSurface
}

enum HostSurfaceSinks {
    private struct Slot {
        /// The newest frame, waiting for the main thread.
        var pending: IOSurface?
        /// A main-queue task to take the pending frame is queued.
        var posted = false
        /// The layer's contents now. Main thread sets it.
        var shown: IOSurface?
        /// Surfaces free for the next frame, once the render server is done with them.
        var spare: [IOSurface] = []

        /// Keeps a surface for reuse, up to a few.
        mutating func recycle(_ surface: IOSurface) {
            if spare.count < HostSurfaceSinks.maxSpare {
                spare.append(surface)
            }
        }
    }

    /// Spare surfaces kept per slot: one the render server may still be showing, one to write.
    static let maxSpare = 2

    private static let slots = OSAllocatedUnfairLock(initialState: [UInt64: Slot]())

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

    /// How the pixels of an AUIHostPixelFormat become the surface's BGRA. Little-endian 32-bit words.
    enum Conversion {
        /// BGRA premultiplied: as is.
        case copy
        /// RGBA premultiplied: red and blue swapped.
        case swapRedBlue
        /// BGRX: alpha set.
        case opaque
        /// RGBX: red and blue swapped, alpha set.
        case swapRedBlueOpaque

        init?(_ format: Int32) {
            switch format {
            case Int32(AUIHostPixelBGRA8Premultiplied.rawValue): self = .copy
            case Int32(AUIHostPixelRGBA8Premultiplied.rawValue): self = .swapRedBlue
            case Int32(AUIHostPixelBGRX8.rawValue): self = .opaque
            case Int32(AUIHostPixelRGBX8.rawValue): self = .swapRedBlueOpaque
            default: return nil
            }
        }
    }

    /// A new BGRA surface tagged sRGB, or nil when the system cannot make one that size.
    private static func makeSurface(width: Int, height: Int) -> IOSurface? {
        guard let surface = IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4,
                                                   .pixelFormat: 0x4247_5241 /* 'BGRA' */]) else {
            return nil
        }
        // Made rarely (a few per frame size), so the tag is made each time.
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpace)
        }
        return surface
    }

    /// Copies width x height pixels into the surface, converted to BGRA. The last row reads only its pixels, so a
    /// client may hand a tightly cut buffer.
    private static func copy(_ pixels: UnsafeRawPointer, stride: Int, width: Int, height: Int,
                             conversion: Conversion, into surface: IOSurface) -> Bool {
        guard surface.lock(options: [], seed: nil) == KERN_SUCCESS else {
            return false
        }
        defer { surface.unlock(options: [], seed: nil) }
        let base = surface.baseAddress
        let surfaceStride = surface.bytesPerRow
        let rowBytes = width * 4
        for y in 0..<height {
            let source = pixels + y * stride
            let target = base + y * surfaceStride
            switch conversion {
            case .copy:
                target.copyMemory(from: source, byteCount: rowBytes)
            case .swapRedBlue:
                convertRow(source, target, width) { ($0 & 0xFF00_FF00) | (($0 & 0xFF) << 16) | (($0 >> 16) & 0xFF) }
            case .opaque:
                convertRow(source, target, width) { $0 | 0xFF00_0000 }
            case .swapRedBlueOpaque:
                convertRow(source, target, width) { 0xFF00_0000 | ($0 & 0x0000_FF00) | (($0 & 0xFF) << 16) | (($0 >> 16) & 0xFF) }
            }
        }
        return true
    }

    @inline(__always)
    private static func convertRow(_ source: UnsafeRawPointer, _ target: UnsafeMutableRawPointer, _ width: Int,
                                   _ convert: (UInt32) -> UInt32) {
        for x in 0..<width {
            // The client's buffer need not be aligned; the surface's rows are. Apple platforms are little-endian.
            let pixel = source.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
            target.storeBytes(of: convert(pixel), toByteOffset: x * 4, as: UInt32.self)
        }
    }

    /// The largest width and height an IOSurface takes (16384 on current systems).
    static let maxWidth = IOSurfaceGetPropertyMaximum(kIOSurfaceWidth)
    static let maxHeight = IOSurfaceGetPropertyMaximum(kIOSurfaceHeight)

    /// actionUIHostSurfacePresentPixels. Any thread.
    static func present(surfaceID: UInt64, width: Int, height: Int, stride: Int, format: Int32,
                        pixels: UnsafeRawPointer) -> Bool {
        // Larger than an IOSurface takes: refused rather than shown blank or not at all.
        guard width > 0, height > 0, width <= maxWidth, height <= maxHeight, stride >= width * 4,
              let conversion = Conversion(format) else {
            return false
        }
        let (rows, rowsOverflow) = stride.multipliedReportingOverflow(by: height - 1)
        let (_, neededOverflow) = rows.addingReportingOverflow(width * 4)
        guard !rowsOverflow, !neededOverflow else {
            return false
        }

        // A surface to write: a spare one the render server is done with, else the waiting frame's (this frame
        // replaces it anyway), else a new one. Spares of another size go.
        let (slotOpen, reused) = slots.withLock { slots -> (Bool, IOSurface?) in
            guard var slot = slots[surfaceID] else {
                return (false, nil)
            }
            slot.spare.removeAll { $0.width != width || $0.height != height }
            var surface: IOSurface?
            if let index = slot.spare.firstIndex(where: { !$0.isInUse }) {
                surface = slot.spare.remove(at: index)
            } else if let pending = slot.pending, pending.width == width, pending.height == height {
                surface = pending
                slot.pending = nil
            }
            slots[surfaceID] = slot
            return (true, surface)
        }
        guard slotOpen, let surface = reused ?? makeSurface(width: width, height: height),
              copy(pixels, stride: stride, width: width, height: height, conversion: conversion, into: surface) else {
            return false
        }

        // The slot may have closed while the pixels were copied.
        let (stored, post) = slots.withLock { slots -> (Bool, Bool) in
            guard var slot = slots[surfaceID] else {
                return (false, false)
            }
            // A frame another thread stored meanwhile is older than this one.
            if let older = slot.pending {
                slot.recycle(older)
            }
            slot.pending = surface
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
        let pending = slots.withLock { slots -> IOSurface? in
            guard var slot = slots[surfaceID] else {
                return nil
            }
            let pending = slot.pending
            slot.pending = nil
            slot.posted = false
            slots[surfaceID] = slot
            return pending
        }
        guard let pending, let view = HostSurfaceRegistry.shared.liveSurface(surfaceID) else {
            return
        }
        view.show(HostSurfaceFrame(surface: pending))
        // The surface shown before is free once the render server is done with it.
        slots.withLock { slots in
            guard var slot = slots[surfaceID] else {
                return
            }
            if let previous = slot.shown, previous !== pending {
                slot.recycle(previous)
            }
            slot.shown = pending
            slots[surfaceID] = slot
        }
    }
}

#endif

// Add-ons/ActionUIHostSurface/Tests/HostSurfaceDmabufSupport.swift
//
// Real dmabufs for the Linux tests, without a GPU: memory (a sealed memfd) turned into a dmabuf by
// /dev/udmabuf, filled with one color, in the linear layout. nil where udmabuf is not available.

#if os(Linux)

import Glibc
import CActionUIHostSurface

/// struct udmabuf_create (linux/udmabuf.h).
private struct UdmabufCreate {
    var memfd: UInt32
    var flags: UInt32
    var offset: UInt64
    var size: UInt64
}

/// _IOW('u', 0x42, struct udmabuf_create).
private let udmabufCreate: UInt = 0x4018_7542
private let udmabufFlagsCloexec: UInt32 = 0x01

// Linux ABI values Swift's Glibc module does not show (they need _GNU_SOURCE): memfd_create's flags and the
// seal commands (linux/memfd.h, linux/fcntl.h).
private let mfdCloexec: UInt32 = 0x0001
private let mfdAllowSealing: UInt32 = 0x0002
private let fAddSeals: Int32 = 1024 + 9
private let fSealShrink: Int32 = 0x0002

/// glibc's memfd_create, looked up at run time for the same reason.
private let memfdCreate: (@convention(c) (UnsafePointer<CChar>, UInt32) -> Int32)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "memfd_create") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (UnsafePointer<CChar>, UInt32) -> Int32).self)
}()

/// DRM_FORMAT_ARGB8888 ('AR24'): blue, green, red, alpha in memory. DRM_FORMAT_MOD_LINEAR is 0.
let testDrmFormatARGB8888: UInt32 = 0x3432_5241

final class TestDmabuf {
    let width: Int
    let height: Int
    let stride: Int
    let fd: Int32
    private let memfd: Int32

    /// A width x height ARGB8888 buffer filled with one pixel's four bytes (blue, green, red, alpha).
    init?(width: Int, height: Int, pixel: [UInt8]) {
        let stride = width * 4
        let page = Int(sysconf(Int32(_SC_PAGESIZE)))
        let size = (stride * height + page - 1) / page * page
        let device = open("/dev/udmabuf", O_RDWR | O_CLOEXEC)
        guard device >= 0 else {
            return nil
        }
        defer { close(device) }
        guard let memfdCreate else {
            return nil
        }
        let memfd = memfdCreate("hostsurface-test", mfdAllowSealing | mfdCloexec)
        guard memfd >= 0 else {
            return nil
        }
        guard ftruncate(memfd, off_t(size)) == 0, fcntl(memfd, fAddSeals, fSealShrink) == 0,
              let map = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, 0), map != MAP_FAILED else {
            close(memfd)
            return nil
        }
        for index in 0..<(width * height) {
            for byte in 0..<4 {
                map.storeBytes(of: pixel[byte], toByteOffset: index * 4 + byte, as: UInt8.self)
            }
        }
        munmap(map, size)
        var create = UdmabufCreate(memfd: UInt32(memfd), flags: udmabufFlagsCloexec, offset: 0, size: UInt64(size))
        let fd = withUnsafeMutablePointer(to: &create) { ioctl(device, udmabufCreate, UnsafeMutableRawPointer($0)) }
        guard fd >= 0 else {
            close(memfd)
            return nil
        }
        self.width = width
        self.height = height
        self.stride = stride
        self.fd = fd
        self.memfd = memfd
    }

    deinit {
        close(fd)
        close(memfd)
    }

    /// The frame description, with a release callback and its data.
    func frame(release: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, releaseData: UnsafeMutableRawPointer?,
               fourcc: UInt32 = testDrmFormatARGB8888) -> AUIHostDmabuf {
        var buffer = AUIHostDmabuf()
        buffer.structSize = UInt32(MemoryLayout<AUIHostDmabuf>.size)
        buffer.width = UInt32(width)
        buffer.height = UInt32(height)
        buffer.fourcc = fourcc
        buffer.modifier = 0
        buffer.premultiplied = true
        buffer.planeCount = 1
        buffer.planes.0 = AUIHostDmabufPlane(fd: fd, offset: 0, stride: UInt32(stride))
        buffer.release = release
        buffer.releaseData = releaseData
        return buffer
    }
}

#endif

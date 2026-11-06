// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//! Raw declarations of the HostSurface add-on (`ActionUIHostSurface.h`): an ActionUI element
//! whose pixels the program draws with its own renderer. Compiled with the `host-surface`
//! feature, which also links `ActionUIHostSurface.framework` on macOS (on Linux the add-on is in
//! `libActionUI.so`). No logic lives here; use `actionui::host_surface`.
//!
//! The C names are kept for the types and the struct fields; enum values are in upper case
//! (`AUIHostSurfaceCreated` is [`AUI_HOST_SURFACE_CREATED`]). `tests/host_surface_declarations.rs`
//! compares this file with the framework's headers and fails on any difference.
//!
//! The rules are the header's:
//! - Every callback runs on the main thread. [`actionUIHostSurfaceSetDelegate`],
//!   [`actionUIHostSurfaceSetCursor`] and [`ActionUIHostSurface_register`] are main-thread only;
//!   [`actionUIHostSurfaceRequestFrame`], [`actionUIHostSurfaceSetContinuous`],
//!   [`actionUIHostSurfacePresentPixels`], [`actionUIHostSurfacePresentDmabuf`] and
//!   [`actionUIHostSurfaceCopyDmabufFormats`] may be called from any thread and never wait.
//! - The dmabuf calls are Linux only: elsewhere they return false and 0.
//! - The handle in [`AUIHostSurfaceInfo`] stays valid until the Destroyed callback for that
//!   surfaceID returns; the client stops all use of it before returning.
//! - Strings passed to a callback are valid only until it returns.

use std::ffi::{c_char, c_int, c_void};

// MARK: - Enums

/// What the handle in [`AUIHostSurfaceInfo`] is.
pub type AUIHostSurfaceKind = c_int;
/// `CAMetalLayer *` (macOS, iOS).
pub const AUI_HOST_SURFACE_METAL_LAYER: AUIHostSurfaceKind = 1;
/// `ANativeWindow *` (Android).
pub const AUI_HOST_SURFACE_A_NATIVE_WINDOW: AUIHostSurfaceKind = 2;
/// No handle; draw in the render callback (Linux).
pub const AUI_HOST_SURFACE_GL_AREA: AUIHostSurfaceKind = 3;
/// No handle; present finished frames (Linux).
pub const AUI_HOST_SURFACE_FRAME_SINK: AUIHostSurfaceKind = 4;

/// The event passed to the surface callback.
pub type AUIHostSurfaceEvent = c_int;
pub const AUI_HOST_SURFACE_CREATED: AUIHostSurfaceEvent = 1;
pub const AUI_HOST_SURFACE_CHANGED: AUIHostSurfaceEvent = 2;
pub const AUI_HOST_SURFACE_SUSPENDED: AUIHostSurfaceEvent = 3;
pub const AUI_HOST_SURFACE_RESUMED: AUIHostSurfaceEvent = 4;
pub const AUI_HOST_SURFACE_DESTROYED: AUIHostSurfaceEvent = 5;

/// The kind of an input event.
pub type AUIHostInputKind = c_int;
pub const AUI_HOST_INPUT_POINTER_DOWN: AUIHostInputKind = 1;
pub const AUI_HOST_INPUT_POINTER_UP: AUIHostInputKind = 2;
pub const AUI_HOST_INPUT_POINTER_MOVE: AUIHostInputKind = 3;
pub const AUI_HOST_INPUT_POINTER_DRAG: AUIHostInputKind = 4;
pub const AUI_HOST_INPUT_POINTER_ENTER: AUIHostInputKind = 5;
pub const AUI_HOST_INPUT_POINTER_EXIT: AUIHostInputKind = 6;
pub const AUI_HOST_INPUT_POINTER_CANCEL: AUIHostInputKind = 7;
pub const AUI_HOST_INPUT_SCROLL: AUIHostInputKind = 8;
pub const AUI_HOST_INPUT_MAGNIFY: AUIHostInputKind = 9;
pub const AUI_HOST_INPUT_ROTATE: AUIHostInputKind = 10;
pub const AUI_HOST_INPUT_KEY_DOWN: AUIHostInputKind = 11;
pub const AUI_HOST_INPUT_KEY_UP: AUIHostInputKind = 12;
pub const AUI_HOST_INPUT_FOCUS_IN: AUIHostInputKind = 13;
pub const AUI_HOST_INPUT_FOCUS_OUT: AUIHostInputKind = 14;

pub type AUIHostPointerType = c_int;
pub const AUI_HOST_POINTER_MOUSE: AUIHostPointerType = 0;
pub const AUI_HOST_POINTER_TOUCH: AUIHostPointerType = 1;
pub const AUI_HOST_POINTER_PEN: AUIHostPointerType = 2;

pub type AUIHostScrollUnit = c_int;
pub const AUI_HOST_SCROLL_POINTS: AUIHostScrollUnit = 0;
pub const AUI_HOST_SCROLL_STEPS: AUIHostScrollUnit = 1;

pub type AUIHostScrollPhase = c_int;
pub const AUI_HOST_SCROLL_PHASE_NONE: AUIHostScrollPhase = 0;
pub const AUI_HOST_SCROLL_PHASE_BEGAN: AUIHostScrollPhase = 1;
pub const AUI_HOST_SCROLL_PHASE_CHANGED: AUIHostScrollPhase = 2;
pub const AUI_HOST_SCROLL_PHASE_ENDED: AUIHostScrollPhase = 3;
pub const AUI_HOST_SCROLL_PHASE_MOMENTUM: AUIHostScrollPhase = 4;
pub const AUI_HOST_SCROLL_PHASE_MOMENTUM_ENDED: AUIHostScrollPhase = 5;

/// Bits of [`AUIHostInputEvent::modifiers`] (an unnamed enum in the header).
pub const AUI_HOST_MODIFIER_SHIFT: u32 = 1;
pub const AUI_HOST_MODIFIER_CONTROL: u32 = 2;
/// Option on Apple.
pub const AUI_HOST_MODIFIER_ALT: u32 = 4;
/// Command on Apple.
pub const AUI_HOST_MODIFIER_META: u32 = 8;
pub const AUI_HOST_MODIFIER_CAPS_LOCK: u32 = 16;

/// The cursor over the surface, for [`actionUIHostSurfaceSetCursor`].
pub type AUIHostCursor = c_int;
pub const AUI_HOST_CURSOR_ARROW: AUIHostCursor = 0;
pub const AUI_HOST_CURSOR_I_BEAM: AUIHostCursor = 1;
pub const AUI_HOST_CURSOR_CROSSHAIR: AUIHostCursor = 2;
pub const AUI_HOST_CURSOR_POINTING_HAND: AUIHostCursor = 3;
pub const AUI_HOST_CURSOR_OPEN_HAND: AUIHostCursor = 4;
pub const AUI_HOST_CURSOR_CLOSED_HAND: AUIHostCursor = 5;
pub const AUI_HOST_CURSOR_RESIZE_LEFT_RIGHT: AUIHostCursor = 6;
pub const AUI_HOST_CURSOR_RESIZE_UP_DOWN: AUIHostCursor = 7;
pub const AUI_HOST_CURSOR_NOT_ALLOWED: AUIHostCursor = 8;
pub const AUI_HOST_CURSOR_HIDDEN: AUIHostCursor = 9;

/// The layout of the pixels given to `actionUIHostSurfacePresentPixels`: 4 bytes per pixel, in this order.
pub type AUIHostPixelFormat = c_int;
pub const AUI_HOST_PIXEL_BGRA8_PREMULTIPLIED: AUIHostPixelFormat = 1;
pub const AUI_HOST_PIXEL_RGBA8_PREMULTIPLIED: AUIHostPixelFormat = 2;
pub const AUI_HOST_PIXEL_BGRX8: AUIHostPixelFormat = 3;
pub const AUI_HOST_PIXEL_RGBX8: AUIHostPixelFormat = 4;

// MARK: - Structs

/// One surface: its kind, its native handle, and its size.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct AUIHostSurfaceInfo {
    pub structSize: u32,
    pub kind: i32,
    pub handle: *mut c_void,
    pub widthPoints: f64,
    pub heightPoints: f64,
    pub scale: f64,
    pub widthPixels: u32,
    pub heightPixels: u32,
}

/// One input event. `code` and `text` are valid only during the callback.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct AUIHostInputEvent {
    pub structSize: u32,
    pub kind: i32,
    pub pointerType: i32,
    pub button: i32,
    pub pointerID: i64,
    pub modifiers: u32,
    pub clickCount: i32,
    pub x: f64,
    pub y: f64,
    pub deltaX: f64,
    pub deltaY: f64,
    pub scrollUnit: i32,
    pub scrollPhase: i32,
    pub pressure: f64,
    pub tiltX: f64,
    pub tiltY: f64,
    pub keyCode: u32,
    pub code: *const c_char,
    pub text: *const c_char,
    pub timestampSeconds: f64,
}

/// The callbacks of one client. Any of them may be `None`. `structSize` must be
/// `size_of::<AUIHostSurfaceDelegate>()`, which `Default` fills in.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
#[rustfmt::skip] // tests/host_surface_declarations.rs reads one field per line
pub struct AUIHostSurfaceDelegate {
    pub structSize: u32,
    pub surface: Option<unsafe extern "C" fn(u64, *const c_char, i64, i32, *const AUIHostSurfaceInfo, *mut c_void)>,
    pub frame: Option<unsafe extern "C" fn(u64, *const c_char, i64, f64, *mut c_void)>,
    pub input: Option<unsafe extern "C" fn(u64, *const c_char, i64, *const AUIHostInputEvent, *mut c_void)>,
    pub render: Option<unsafe extern "C" fn(u64, *const c_char, i64, *mut c_void)>,
}

impl Default for AUIHostSurfaceDelegate {
    /// No callbacks, and the struct size the add-on checks.
    fn default() -> Self {
        AUIHostSurfaceDelegate {
            structSize: std::mem::size_of::<AUIHostSurfaceDelegate>() as u32,
            surface: None,
            frame: None,
            input: None,
            render: None,
        }
    }
}

/// One plane of a dmabuf: its file descriptor, and where its pixels start and how far apart its rows are.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
#[rustfmt::skip] // tests/host_surface_declarations.rs reads one field per line
pub struct AUIHostDmabufPlane {
    pub fd: i32,
    pub offset: u32,
    pub stride: u32,
}

/// A dmabuf frame for [`actionUIHostSurfacePresentDmabuf`] (Linux). `structSize` must be
/// `size_of::<AUIHostDmabuf>()`. The file descriptors stay the caller's and must stay open, with the
/// buffer unchanged, until `release` is called: exactly once for every present that returned true, on
/// the main thread, never for one that returned false.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
#[rustfmt::skip] // tests/host_surface_declarations.rs reads one field per line
pub struct AUIHostDmabuf {
    pub structSize: u32,
    pub width: u32,
    pub height: u32,
    pub fourcc: u32,
    pub modifier: u64,
    pub premultiplied: bool,
    pub planeCount: u32,
    pub planes: [AUIHostDmabufPlane; 4],
    pub release: Option<unsafe extern "C" fn(*mut c_void)>,
    pub releaseData: *mut c_void,
}

/// A pixel format and memory layout the display can import, from [`actionUIHostSurfaceCopyDmabufFormats`].
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[rustfmt::skip] // tests/host_surface_declarations.rs reads one field per line
pub struct AUIHostDmabufFormat {
    pub fourcc: u32,
    pub modifier: u64,
}

// MARK: - Functions

#[rustfmt::skip] // tests/host_surface_declarations.rs reads one declaration per line
unsafe extern "C" {
    pub fn ActionUIHostSurface_register();
    pub fn actionUIHostSurfaceSetDelegate(surfaceName: *const c_char, delegate: *const AUIHostSurfaceDelegate, userData: *mut c_void) -> bool;
    pub fn actionUIHostSurfaceRequestFrame(surfaceID: u64);
    pub fn actionUIHostSurfaceSetContinuous(surfaceID: u64, continuous: bool);
    pub fn actionUIHostSurfaceSetCursor(surfaceID: u64, cursor: i32) -> bool;
    pub fn actionUIHostSurfacePresentPixels(surfaceID: u64, width: u32, height: u32, stride: u32, format: i32, pixels: *const c_void) -> bool;
    pub fn actionUIHostSurfacePresentDmabuf(surfaceID: u64, buffer: *const AUIHostDmabuf) -> bool;
    pub fn actionUIHostSurfaceCopyDmabufFormats(surfaceID: u64, formats: *mut AUIHostDmabufFormat, capacity: u32) -> u32;
}

// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//! The `HostSurface` element: a part of the window that the program draws with its own
//! renderer (Metal, wgpu, ...), while ActionUI does the rest of the window. Needs the
//! `host-surface` feature (macOS and Linux); on macOS [`crate::App::new`] registers the element.
//!
//! A document places the element and names it:
//!
//! ```json
//! { "type": "HostSurface", "id": 5, "properties": { "surfaceName": "canvas" } }
//! ```
//!
//! The program binds a [`SurfaceDelegate`] to that name with [`crate::App::set_surface_delegate`],
//! before or after the document loads, and gets the native surface of every element with that
//! name, in every window:
//!
//! - [`SurfaceDelegate::created`]: build the renderer on [`SurfaceInfo::handle`] (on macOS a
//!   `CAMetalLayer`; on Linux a frame sink, see [`SurfaceId::present_pixels`]), sized in pixels.
//!   With the `wgpu` feature, [`wgpu_surface`] does it for wgpu.
//! - [`SurfaceDelegate::changed`]: resize to the new pixel size before the next frame.
//! - [`SurfaceDelegate::suspended`] / [`SurfaceDelegate::resumed`]: the surface left the screen
//!   (hidden, an occluded window, a collapsed layout) or came back. Ask for no drawable meanwhile.
//! - [`SurfaceDelegate::destroyed`]: stop all use of the handle before returning (join a render
//!   thread, drop the swapchain). It comes before the "created" of a successor.
//! - [`SurfaceDelegate::frame`]: a display refresh, while the element's `continuous` is true or
//!   after [`SurfaceId::request_frame`].
//! - [`SurfaceDelegate::input`]: pointer, touch, scroll, gestures, keys, focus.
//!
//! # Threads
//!
//! Every delegate method runs on the main thread. [`SurfaceId::request_frame`],
//! [`SurfaceId::set_continuous`] and [`SurfaceId::present_pixels`] may be called from any thread
//! and never wait. A render thread must not call [`crate::Window`] getters (they wait for the
//! main thread) while [`SurfaceDelegate::destroyed`] may be joining it; pace it by the frame
//! callback instead.
//!
//! # Panics
//!
//! A panic in a delegate method is caught and logged, like one in an action handler.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::ffi::{CStr, c_char, c_void};
use std::mem::ManuallyDrop;
use std::ptr::NonNull;

use actionui_sys::host_surface as sys;

use crate::{App, Result, ffi};

/// One announced surface, unique for the life of the process: every "created" brings a new one.
/// Key the renderer's state by it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SurfaceId(u64);

impl SurfaceId {
    /// The number the C interface uses.
    pub fn get(self) -> u64 {
        self.0
    }

    /// Asks for one [`SurfaceDelegate::frame`] at the next display refresh. Any thread; never
    /// waits. Does nothing once the surface is destroyed.
    pub fn request_frame(self) {
        unsafe { sys::actionUIHostSurfaceRequestFrame(self.0) };
    }

    /// Turns a frame callback at every display refresh on or off, until the element's
    /// `continuous` property changes. Any thread; never waits.
    pub fn set_continuous(self, continuous: bool) {
        unsafe { sys::actionUIHostSurfaceSetContinuous(self.0, continuous) };
    }

    /// Sets the cursor over the surface. Main thread only. Returns false when the surface is
    /// no longer alive.
    pub fn set_cursor(self, cursor: Cursor) -> Result<bool> {
        ffi::require_main_thread()?;
        Ok(unsafe { sys::actionUIHostSurfaceSetCursor(self.0, cursor as i32) })
    }

    /// Shows one finished frame on a frame-sink surface ([`SurfaceHandle::FrameSink`], Linux): `height`
    /// rows of `width` pixels, 4 bytes each in `format`, `stride` bytes apart. The pixels are copied
    /// before it returns; the newest frame wins when several come between two display refreshes.
    /// Render at the pixel size of the last `created` or `changed`. Any thread; never waits.
    /// Returns false when the surface is not a live frame sink (always on macOS), when `width` or
    /// `height` is 0, when `stride` is less than `width * 4`, or when `pixels` is too short for the
    /// frame.
    pub fn present_pixels(self, width: u32, height: u32, stride: u32, format: PixelFormat, pixels: &[u8]) -> bool {
        if width == 0 || height == 0 || (stride as u64) < width as u64 * 4 {
            return false;
        }
        let needed = stride as u64 * (height as u64 - 1) + width as u64 * 4;
        if (pixels.len() as u64) < needed {
            return false;
        }
        unsafe { sys::actionUIHostSurfacePresentPixels(self.0, width, height, stride, format as i32, pixels.as_ptr().cast()) }
    }
}

/// The layout of the pixels given to [`SurfaceId::present_pixels`]: 4 bytes per pixel, in this order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum PixelFormat {
    /// Blue, green, red, alpha; colors premultiplied by alpha.
    Bgra8Premultiplied = sys::AUI_HOST_PIXEL_BGRA8_PREMULTIPLIED,
    /// Red, green, blue, alpha; colors premultiplied by alpha.
    Rgba8Premultiplied = sys::AUI_HOST_PIXEL_RGBA8_PREMULTIPLIED,
    /// Blue, green, red, unused: opaque.
    Bgrx8 = sys::AUI_HOST_PIXEL_BGRX8,
    /// Red, green, blue, unused: opaque.
    Rgbx8 = sys::AUI_HOST_PIXEL_RGBX8,
}

/// The native surface the program draws into.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum SurfaceHandle {
    /// A `CAMetalLayer *` (macOS). For wgpu: `SurfaceTargetUnsafe::CoreAnimationLayer`.
    MetalLayer(NonNull<c_void>),
    /// A frame sink (Linux): no handle; render anywhere at the surface's pixel size and present
    /// the pixels with [`SurfaceId::present_pixels`]. For wgpu: `wgpu_surface::FrameSink` (the `wgpu` feature).
    FrameSink,
    /// A kind this version of the crate does not know, with its C value.
    Other(i32),
}

/// A surface as a [`SurfaceDelegate`] sees it. The handle is valid until
/// [`SurfaceDelegate::destroyed`] for this `id` returns.
#[derive(Clone, Debug)]
pub struct SurfaceInfo {
    pub id: SurfaceId,
    /// The window and element ID of the HostSurface element, as in the document.
    pub window_uuid: String,
    pub view_id: i64,
    pub handle: SurfaceHandle,
    pub width_points: f64,
    pub height_points: f64,
    /// Pixels per point.
    pub scale: f64,
    /// Nonzero in created and changed.
    pub width_pixels: u32,
    pub height_pixels: u32,
}

/// A client of HostSurface elements. Every method runs on the main thread.
pub trait SurfaceDelegate: 'static {
    fn created(&mut self, surface: &SurfaceInfo);
    fn changed(&mut self, _surface: &SurfaceInfo) {}
    fn suspended(&mut self, _surface: &SurfaceInfo) {}
    fn resumed(&mut self, _surface: &SurfaceInfo) {}
    /// Stop all use of the handle before returning. When the delegate's own call caused it (closing the
    /// window inside `created`, say), it arrives right after that call returns.
    fn destroyed(&mut self, surface: &SurfaceInfo);
    /// `timestamp`: the target presentation time in seconds on the display clock; use
    /// differences only.
    fn frame(&mut self, _surface: SurfaceId, _timestamp: f64) {}
    fn input(&mut self, _surface: SurfaceId, _event: &InputEvent) {}
}

/// The cursor over a surface.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum Cursor {
    Arrow = sys::AUI_HOST_CURSOR_ARROW,
    IBeam = sys::AUI_HOST_CURSOR_I_BEAM,
    Crosshair = sys::AUI_HOST_CURSOR_CROSSHAIR,
    PointingHand = sys::AUI_HOST_CURSOR_POINTING_HAND,
    OpenHand = sys::AUI_HOST_CURSOR_OPEN_HAND,
    ClosedHand = sys::AUI_HOST_CURSOR_CLOSED_HAND,
    ResizeLeftRight = sys::AUI_HOST_CURSOR_RESIZE_LEFT_RIGHT,
    ResizeUpDown = sys::AUI_HOST_CURSOR_RESIZE_UP_DOWN,
    NotAllowed = sys::AUI_HOST_CURSOR_NOT_ALLOWED,
    Hidden = sys::AUI_HOST_CURSOR_HIDDEN,
}

/// What an [`InputEvent`] is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum InputKind {
    PointerDown,
    PointerUp,
    /// Moved with no button down.
    PointerMove,
    /// Moved with a button or a touch down.
    PointerDrag,
    PointerEnter,
    PointerExit,
    /// The system took the pointer (a touch became a gesture).
    PointerCancel,
    Scroll,
    /// `delta_x` is added to the scale: 0.1 takes 1.0 to 1.1.
    Magnify,
    /// `delta_x` in degrees, counterclockwise positive.
    Rotate,
    KeyDown,
    KeyUp,
    FocusIn,
    FocusOut,
    /// A kind this version of the crate does not know, with its C value.
    Other(i32),
}

impl InputKind {
    fn from_c(kind: i32) -> InputKind {
        match kind {
            sys::AUI_HOST_INPUT_POINTER_DOWN => InputKind::PointerDown,
            sys::AUI_HOST_INPUT_POINTER_UP => InputKind::PointerUp,
            sys::AUI_HOST_INPUT_POINTER_MOVE => InputKind::PointerMove,
            sys::AUI_HOST_INPUT_POINTER_DRAG => InputKind::PointerDrag,
            sys::AUI_HOST_INPUT_POINTER_ENTER => InputKind::PointerEnter,
            sys::AUI_HOST_INPUT_POINTER_EXIT => InputKind::PointerExit,
            sys::AUI_HOST_INPUT_POINTER_CANCEL => InputKind::PointerCancel,
            sys::AUI_HOST_INPUT_SCROLL => InputKind::Scroll,
            sys::AUI_HOST_INPUT_MAGNIFY => InputKind::Magnify,
            sys::AUI_HOST_INPUT_ROTATE => InputKind::Rotate,
            sys::AUI_HOST_INPUT_KEY_DOWN => InputKind::KeyDown,
            sys::AUI_HOST_INPUT_KEY_UP => InputKind::KeyUp,
            sys::AUI_HOST_INPUT_FOCUS_IN => InputKind::FocusIn,
            sys::AUI_HOST_INPUT_FOCUS_OUT => InputKind::FocusOut,
            other => InputKind::Other(other),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PointerType {
    Mouse,
    Touch,
    Pen,
}

/// The unit of scroll deltas.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrollUnit {
    /// Precise deltas (a trackpad).
    Points,
    /// Wheel steps (a notched mouse wheel).
    Steps,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrollPhase {
    /// A wheel step, no gesture.
    None,
    Began,
    Changed,
    Ended,
    /// Inertia after the fingers lifted.
    Momentum,
    MomentumEnded,
}

/// The modifier keys held during an [`InputEvent`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Modifiers(u32);

impl Modifiers {
    pub fn bits(self) -> u32 {
        self.0
    }
    pub fn shift(self) -> bool {
        self.0 & sys::AUI_HOST_MODIFIER_SHIFT != 0
    }
    pub fn control(self) -> bool {
        self.0 & sys::AUI_HOST_MODIFIER_CONTROL != 0
    }
    /// Option on a Mac.
    pub fn alt(self) -> bool {
        self.0 & sys::AUI_HOST_MODIFIER_ALT != 0
    }
    /// Command on a Mac.
    pub fn meta(self) -> bool {
        self.0 & sys::AUI_HOST_MODIFIER_META != 0
    }
    pub fn caps_lock(self) -> bool {
        self.0 & sys::AUI_HOST_MODIFIER_CAPS_LOCK != 0
    }
}

/// One input event. Positions are in points from the top-left corner of the surface.
#[derive(Clone, Debug)]
pub struct InputEvent {
    pub kind: InputKind,
    pub pointer_type: PointerType,
    /// 0 primary, 1 secondary, 2 middle.
    pub button: i32,
    /// Stable per touch while it lasts; 0 for the mouse.
    pub pointer_id: i64,
    pub modifiers: Modifiers,
    pub click_count: i32,
    pub x: f64,
    pub y: f64,
    /// Scroll: how far the content should move, positive to the right and down, in
    /// `scroll_unit`. Magnify and rotate: `delta_x`, see [`InputKind`].
    pub delta_x: f64,
    pub delta_y: f64,
    pub scroll_unit: ScrollUnit,
    pub scroll_phase: ScrollPhase,
    /// 0...1; 1 when down and the device has no pressure.
    pub pressure: f64,
    pub tilt_x: f64,
    pub tilt_y: f64,
    /// The platform key code (a macOS virtual key code).
    pub key_code: u32,
    /// The W3C UI Events code of the key ("KeyA", "ArrowLeft"); empty when unknown.
    pub code: String,
    /// The text a key down produced; `None` for keys that produce no insertable text.
    pub text: Option<String>,
    /// The platform event time in seconds, on its monotonic clock.
    pub timestamp: f64,
}

impl InputEvent {
    /// # Safety
    /// `event` must point to a valid event whose strings are valid.
    unsafe fn from_c(event: &sys::AUIHostInputEvent) -> InputEvent {
        let string = |pointer: *const c_char| -> Option<String> {
            (!pointer.is_null()).then(|| unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned())
        };
        InputEvent {
            kind: InputKind::from_c(event.kind),
            pointer_type: match event.pointerType {
                sys::AUI_HOST_POINTER_TOUCH => PointerType::Touch,
                sys::AUI_HOST_POINTER_PEN => PointerType::Pen,
                _ => PointerType::Mouse,
            },
            button: event.button,
            pointer_id: event.pointerID,
            modifiers: Modifiers(event.modifiers),
            click_count: event.clickCount,
            x: event.x,
            y: event.y,
            delta_x: event.deltaX,
            delta_y: event.deltaY,
            scroll_unit: if event.scrollUnit == sys::AUI_HOST_SCROLL_STEPS { ScrollUnit::Steps } else { ScrollUnit::Points },
            scroll_phase: match event.scrollPhase {
                sys::AUI_HOST_SCROLL_PHASE_BEGAN => ScrollPhase::Began,
                sys::AUI_HOST_SCROLL_PHASE_CHANGED => ScrollPhase::Changed,
                sys::AUI_HOST_SCROLL_PHASE_ENDED => ScrollPhase::Ended,
                sys::AUI_HOST_SCROLL_PHASE_MOMENTUM => ScrollPhase::Momentum,
                sys::AUI_HOST_SCROLL_PHASE_MOMENTUM_ENDED => ScrollPhase::MomentumEnded,
                _ => ScrollPhase::None,
            },
            pressure: event.pressure,
            tilt_x: event.tiltX,
            tilt_y: event.tiltY,
            key_code: event.keyCode,
            code: string(event.code).unwrap_or_default(),
            text: string(event.text),
            timestamp: event.timestampSeconds,
        }
    }
}

// MARK: - Binding

/// One bound delegate. Its address is the C side's userData, so it stays put (boxed) and alive
/// until the C side can no longer call it.
struct Slot {
    delegate: RefCell<Box<dyn SurfaceDelegate>>,
    /// Surface events that arrived while the delegate was busy with another call (a window closed
    /// inside `created`, say), delivered when that call returns. Frames and input are dropped instead.
    deferred: RefCell<Vec<(i32, SurfaceInfo)>>,
}

// The tables are ManuallyDrop: the process exits from App::run with delegates still bound, and the main
// thread's thread-locals are destroyed then in no set order. Dropping a delegate there runs its own
// destructors, which may use thread-locals already gone (wgpu's queue does, and the process aborted);
// what is still bound at exit is left to the end of the process instead.
thread_local! {
    /// The bound delegates by surface name. Main thread only.
    static SLOTS: RefCell<ManuallyDrop<HashMap<String, Box<Slot>>>> = RefCell::new(ManuallyDrop::new(HashMap::new()));
    /// Unbound delegates the C side may still call: a change made inside a callback takes
    /// effect when the outermost callback returns, after this crate's code has run.
    static RETIRED: RefCell<ManuallyDrop<Vec<Box<Slot>>>> = const { RefCell::new(ManuallyDrop::new(Vec::new())) };
    /// How deep the main thread is in delegate callbacks.
    static DEPTH: Cell<u32> = const { Cell::new(0) };
}

impl App {
    /// Binds `delegate` to every HostSurface element whose `surfaceName` is `surface_name`, in
    /// every window, now and later. Live surfaces are announced to it at once. A delegate it
    /// replaces gets [`SurfaceDelegate::destroyed`] for its surfaces first. Called inside a
    /// delegate method, the change takes effect when the outermost callback returns.
    pub fn set_surface_delegate(&self, surface_name: &str, delegate: impl SurfaceDelegate) -> Result<()> {
        bind(surface_name, Some(Box::new(delegate)))
    }

    /// Unbinds the delegate of `surface_name`; it gets [`SurfaceDelegate::destroyed`] for its
    /// surfaces first.
    pub fn remove_surface_delegate(&self, surface_name: &str) -> Result<()> {
        bind(surface_name, None)
    }
}

fn bind(surface_name: &str, delegate: Option<Box<dyn SurfaceDelegate>>) -> Result<()> {
    ffi::require_main_thread()?;
    let name = ffi::cstring("surface name", surface_name)?;
    let slot = delegate.map(|delegate| Box::new(Slot { delegate: RefCell::new(delegate), deferred: RefCell::new(Vec::new()) }));
    let callbacks = sys::AUIHostSurfaceDelegate {
        structSize: size_of::<sys::AUIHostSurfaceDelegate>() as u32,
        surface: Some(on_surface),
        frame: Some(on_frame),
        input: Some(on_input),
        render: None,
    };
    let user_data = slot.as_ref().map_or(std::ptr::null_mut(), |slot| (&**slot as *const Slot).cast_mut().cast::<c_void>());
    // Recorded before the C call: a callback it runs (the old delegate's "destroyed") may bind
    // the name again, and the C side applies that change after this one, so it must win here too.
    let old = replace_slot(surface_name, slot);
    let bound = if user_data.is_null() {
        unsafe { sys::actionUIHostSurfaceSetDelegate(name.as_ptr(), std::ptr::null(), std::ptr::null_mut()) }
    } else {
        unsafe { sys::actionUIHostSurfaceSetDelegate(name.as_ptr(), &callbacks, user_data) }
    };
    if !bound {
        // The C side did nothing and called nothing: put the old binding back.
        drop(replace_slot(surface_name, old));
        return Err(ffi::failure("HostSurface refused the delegate (an empty surface name?)"));
    }
    if let Some(old) = old {
        retire(old);
    }
    Ok(())
}

/// Puts `slot` in the table under `surface_name` (or removes it) and returns the one it replaced,
/// to be dropped after the table is released: its delegate's Drop may bind again.
fn replace_slot(surface_name: &str, slot: Option<Box<Slot>>) -> Option<Box<Slot>> {
    SLOTS.with(|slots| {
        let mut slots = slots.borrow_mut();
        match slot {
            Some(slot) => slots.insert(surface_name.to_string(), slot),
            None => slots.remove(surface_name),
        }
    })
}

/// Frees an unbound delegate once the C side cannot call it any more: at once outside a
/// callback (the C side has sent it "destroyed" already), else after the outermost callback
/// returns (see [`with_delegate`]).
fn retire(slot: Box<Slot>) {
    if DEPTH.with(Cell::get) == 0 {
        drop(slot);
        return;
    }
    RETIRED.with(|retired| retired.borrow_mut().push(slot));
}

/// Frees the retired delegates on a main-loop turn after the outermost callback returned, when
/// the C side has applied the changes it deferred. A turn inside a callback (a modal panel run
/// from a delegate method) frees nothing: that callback schedules another when it returns.
fn free_retired() {
    if DEPTH.with(Cell::get) > 0 {
        return;
    }
    let retired: Vec<Box<Slot>> = RETIRED.with(|retired| std::mem::take(&mut **retired.borrow_mut()));
    drop(retired);
}

// MARK: - Callbacks

/// Runs `body` with the delegate of `user_data`, counting the depth, catching panics.
///
/// # Safety
/// `user_data` must be the address of a live [`Slot`], as the C side passes it back.
unsafe fn with_delegate(what: &str, user_data: *mut c_void, body: impl FnOnce(&mut dyn SurfaceDelegate)) {
    let slot = unsafe { &*user_data.cast::<Slot>() };
    DEPTH.with(|depth| depth.set(depth.get() + 1));
    ffi::guard(what, (), || match slot.delegate.try_borrow_mut() {
        Ok(mut delegate) => {
            body(&mut **delegate);
            // Surface events that arrived during the call, in order (one may bring more).
            loop {
                let next = {
                    let mut deferred = slot.deferred.borrow_mut();
                    if deferred.is_empty() { None } else { Some(deferred.remove(0)) }
                };
                let Some((event, surface)) = next else {
                    break;
                };
                surface_event(&mut **delegate, event, &surface);
            }
        }
        Err(_) => {
            let _ = crate::log::log(
                crate::LogLevel::Warning,
                &format!("A {what} call arrived while the delegate was still busy with another; skipped"),
            );
        }
    });
    let depth = DEPTH.with(|depth| {
        depth.set(depth.get() - 1);
        depth.get()
    });
    if depth == 0 && RETIRED.with(|retired| !retired.borrow().is_empty()) {
        crate::main_thread::dispatch(free_retired);
    }
}

unsafe extern "C" fn on_surface(
    surface_id: u64,
    window_uuid: *const c_char,
    view_id: i64,
    event: i32,
    info: *const sys::AUIHostSurfaceInfo,
    user_data: *mut c_void,
) {
    if info.is_null() || user_data.is_null() {
        return;
    }
    let info = unsafe { &*info };
    let handle = match (info.kind, NonNull::new(info.handle)) {
        (sys::AUI_HOST_SURFACE_METAL_LAYER, Some(layer)) => SurfaceHandle::MetalLayer(layer),
        (sys::AUI_HOST_SURFACE_FRAME_SINK, _) => SurfaceHandle::FrameSink,
        (kind, _) => SurfaceHandle::Other(kind),
    };
    let surface = SurfaceInfo {
        id: SurfaceId(surface_id),
        window_uuid: unsafe { ffi::copy_string(window_uuid) }.unwrap_or_default(),
        view_id,
        handle,
        width_points: info.widthPoints,
        height_points: info.heightPoints,
        scale: info.scale,
        width_pixels: info.widthPixels,
        height_pixels: info.heightPixels,
    };
    let slot = unsafe { &*user_data.cast::<Slot>() };
    if slot.delegate.try_borrow_mut().is_err() {
        // The delegate is inside another of its methods, which caused this event: deliver it when that
        // method returns, so a "destroyed" is never lost.
        slot.deferred.borrow_mut().push((event, surface));
        return;
    }
    unsafe {
        with_delegate("HostSurface delegate", user_data, |delegate| surface_event(delegate, event, &surface));
    }
}

fn surface_event(delegate: &mut dyn SurfaceDelegate, event: i32, surface: &SurfaceInfo) {
    match event {
        sys::AUI_HOST_SURFACE_CREATED => delegate.created(surface),
        sys::AUI_HOST_SURFACE_CHANGED => delegate.changed(surface),
        sys::AUI_HOST_SURFACE_SUSPENDED => delegate.suspended(surface),
        sys::AUI_HOST_SURFACE_RESUMED => delegate.resumed(surface),
        sys::AUI_HOST_SURFACE_DESTROYED => delegate.destroyed(surface),
        _ => {}
    }
}

unsafe extern "C" fn on_frame(surface_id: u64, _window_uuid: *const c_char, _view_id: i64, timestamp: f64, user_data: *mut c_void) {
    if user_data.is_null() {
        return;
    }
    unsafe { with_delegate("HostSurface frame", user_data, |delegate| delegate.frame(SurfaceId(surface_id), timestamp)) };
}

unsafe extern "C" fn on_input(
    surface_id: u64,
    _window_uuid: *const c_char,
    _view_id: i64,
    event: *const sys::AUIHostInputEvent,
    user_data: *mut c_void,
) {
    if event.is_null() || user_data.is_null() {
        return;
    }
    let event = unsafe { InputEvent::from_c(&*event) };
    unsafe { with_delegate("HostSurface input", user_data, |delegate| delegate.input(SurfaceId(surface_id), &event)) };
}

/// Registers the element; called by [`App::new`]. On Linux libActionUI.so registers it itself.
#[cfg(target_os = "macos")]
pub(crate) fn register_element() {
    unsafe { sys::ActionUIHostSurface_register() };
}

// MARK: - wgpu

/// wgpu on a HostSurface: the surface on its native handle, a device that works everywhere the
/// element does, and what to do with each `get_current_texture` result. Needs the `wgpu` feature.
#[cfg(feature = "wgpu")]
pub mod wgpu_surface {
    use super::{PixelFormat, SurfaceHandle, SurfaceId, SurfaceInfo};
    use crate::{Error, Result};

    /// Creates a wgpu surface on the element's native surface.
    ///
    /// # Safety
    /// `info` must be one a delegate method received (its fields are public, so any handle can be
    /// put in one), for a surface whose [`super::SurfaceDelegate::destroyed`] has not returned. The
    /// returned surface must be dropped before that `destroyed` returns.
    pub unsafe fn create(instance: &wgpu::Instance, info: &SurfaceInfo) -> Result<wgpu::Surface<'static>> {
        let SurfaceHandle::MetalLayer(layer) = info.handle else {
            return Err(Error::ActionUI(format!("no wgpu surface for the handle {:?}", info.handle)));
        };
        #[cfg(target_vendor = "apple")]
        return unsafe { instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::CoreAnimationLayer(layer.as_ptr())) }
            .map_err(|error| Error::ActionUI(format!("wgpu could not create a surface: {error}")));
        #[cfg(not(target_vendor = "apple"))]
        {
            let _ = (instance, layer);
            Err(Error::ActionUI("a Metal layer outside Apple platforms".into()))
        }
    }

    /// A device descriptor with the adapter's own limits. wgpu's defaults ask for more than some
    /// devices have (the iOS simulator's Metal device among them).
    pub fn device_descriptor(adapter: &wgpu::Adapter) -> wgpu::DeviceDescriptor<'static> {
        wgpu::DeviceDescriptor { required_limits: adapter.limits(), ..Default::default() }
    }

    /// What to do with the result of `Surface::get_current_texture`.
    pub enum NextFrame {
        /// Draw into it and present it.
        Draw(wgpu::SurfaceTexture),
        /// Skip this frame (an occluded window, a timeout, a validation error).
        Skip,
        /// Configure the surface again at the current pixel size, then try again.
        Reconfigure,
        /// The surface was lost: create it again with [`create`], configure it, then try again.
        Recreate,
    }

    /// wgpu on a frame-sink surface ([`SurfaceHandle::FrameSink`], Linux): an offscreen texture at
    /// the surface's pixel size to draw into, and [`FrameSink::present`] to copy it back and show it.
    /// A program that supports both kinds checks `info.handle` in `created`: [`create`] for a native
    /// surface, [`FrameSink::new`] for a sink.
    pub struct FrameSink {
        id: SurfaceId,
        target: Option<SinkTarget>,
    }

    struct SinkTarget {
        texture: wgpu::Texture,
        buffer: wgpu::Buffer,
        width: u32,
        height: u32,
        /// Bytes per row in the buffer: the row padded to wgpu's copy alignment.
        padded_row: u32,
    }

    impl FrameSink {
        /// The texture format to render in. Its values are shown as written (no sRGB conversion), and
        /// presented as premultiplied RGBA.
        pub const FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

        /// A sink for the surface; an error when it is not a frame sink.
        pub fn new(info: &SurfaceInfo) -> Result<Self> {
            if info.handle != SurfaceHandle::FrameSink {
                return Err(Error::ActionUI(format!("not a frame sink: {:?}", info.handle)));
            }
            Ok(FrameSink { id: info.id, target: None })
        }

        /// Makes the texture and the readback buffer for a pixel size (from `created` or `changed`).
        pub fn configure(&mut self, device: &wgpu::Device, width: u32, height: u32) {
            let width = width.max(1);
            let height = height.max(1);
            if let Some(target) = &self.target {
                if target.width == width && target.height == height {
                    return;
                }
            }
            let size = wgpu::Extent3d { width, height, depth_or_array_layers: 1 };
            let texture = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("HostSurface frame sink"),
                size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: Self::FORMAT,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });
            let alignment = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
            let padded_row = (width * 4).div_ceil(alignment) * alignment;
            let buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("HostSurface frame sink readback"),
                size: padded_row as u64 * height as u64,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            self.target = Some(SinkTarget { texture, buffer, width, height, padded_row });
        }

        /// A view of the texture to draw into; None before [`FrameSink::configure`].
        pub fn view(&self) -> Option<wgpu::TextureView> {
            self.target.as_ref().map(|target| target.texture.create_view(&Default::default()))
        }

        /// Submits `encoder` (whose passes drew into [`FrameSink::view`]), copies the texture back
        /// and presents it. Waits for the GPU. False when nothing was presented: not configured,
        /// the copy failed, or the surface is gone.
        pub fn present(&self, device: &wgpu::Device, queue: &wgpu::Queue, mut encoder: wgpu::CommandEncoder) -> bool {
            let Some(target) = &self.target else {
                return false;
            };
            encoder.copy_texture_to_buffer(
                wgpu::TexelCopyTextureInfo {
                    texture: &target.texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::TexelCopyBufferInfo {
                    buffer: &target.buffer,
                    layout: wgpu::TexelCopyBufferLayout {
                        offset: 0,
                        bytes_per_row: Some(target.padded_row),
                        rows_per_image: Some(target.height),
                    },
                },
                wgpu::Extent3d { width: target.width, height: target.height, depth_or_array_layers: 1 },
            );
            queue.submit([encoder.finish()]);
            let slice = target.buffer.slice(..);
            slice.map_async(wgpu::MapMode::Read, |_| {});
            if device.poll(wgpu::PollType::wait_indefinitely()).is_err() {
                target.buffer.unmap();
                return false;
            }
            let shown = match slice.get_mapped_range() {
                Ok(pixels) => self.id.present_pixels(
                    target.width,
                    target.height,
                    target.padded_row,
                    PixelFormat::Rgba8Premultiplied,
                    &pixels,
                ),
                Err(_) => false,
            };
            target.buffer.unmap();
            shown
        }
    }

    /// Gets the next texture and says what to do with it.
    pub fn next_frame(surface: &wgpu::Surface<'static>) -> NextFrame {
        match surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(texture) => NextFrame::Draw(texture),
            wgpu::CurrentSurfaceTexture::Suboptimal(texture) => NextFrame::Draw(texture),
            wgpu::CurrentSurfaceTexture::Outdated => NextFrame::Reconfigure,
            wgpu::CurrentSurfaceTexture::Lost => NextFrame::Recreate,
            wgpu::CurrentSurfaceTexture::Timeout
            | wgpu::CurrentSurfaceTexture::Occluded
            | wgpu::CurrentSurfaceTexture::Validation => NextFrame::Skip,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_kinds_map_from_c() {
        assert_eq!(InputKind::from_c(sys::AUI_HOST_INPUT_POINTER_DOWN), InputKind::PointerDown);
        assert_eq!(InputKind::from_c(sys::AUI_HOST_INPUT_FOCUS_OUT), InputKind::FocusOut);
        assert_eq!(InputKind::from_c(99), InputKind::Other(99));
    }

    #[test]
    fn modifiers_read_their_bits() {
        let modifiers = Modifiers(sys::AUI_HOST_MODIFIER_SHIFT | sys::AUI_HOST_MODIFIER_META);
        assert!(modifiers.shift() && modifiers.meta());
        assert!(!modifiers.alt() && !modifiers.control() && !modifiers.caps_lock());
    }

    #[test]
    fn binding_needs_the_main_thread() {
        struct Nothing;
        impl SurfaceDelegate for Nothing {
            fn created(&mut self, _surface: &SurfaceInfo) {}
            fn destroyed(&mut self, _surface: &SurfaceInfo) {}
        }
        assert!(matches!(bind("canvas", Some(Box::new(Nothing))), Err(crate::Error::NotMainThread)));
    }
}

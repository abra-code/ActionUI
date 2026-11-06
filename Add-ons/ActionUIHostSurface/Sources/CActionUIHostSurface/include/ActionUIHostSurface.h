// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIHostSurface.h
//  ActionUIHostSurface add-on
//
//  The plain C interface of the HostSurface element: a rectangle in an ActionUI layout whose
//  pixels the client draws with its own renderer (Metal, wgpu, MoltenVK, ANGLE, ...).
//
//  A client binds to an element by the element's "surfaceName" property, before or after the
//  document loads, with actionUIHostSurfaceSetDelegate. Its delegate then receives the surface
//  events (created, changed, suspended, resumed, destroyed), frame ticks and input. On Apple
//  platforms the surface is a CAMetalLayer, on Android an ANativeWindow. On Linux it is a frame sink
//  (or, with "kind": "gl", a GL area the client draws in from the render callback): the client renders where it
//  likes (offscreen with wgpu or Vulkan, or on the CPU) and presents finished frames with
//  actionUIHostSurfacePresentPixels.
//
//  Threads: every callback runs on the main thread. actionUIHostSurfaceSetDelegate,
//  actionUIHostSurfaceSetCursor and ActionUIHostSurface_register are main-thread only. actionUIHostSurfaceRequestFrame,
//  actionUIHostSurfaceSetContinuous and actionUIHostSurfacePresentPixels may be called from any thread
//  and never wait for the main thread. A client may render from its own thread (Metal layers allow it), but that thread must
//  not wait for the main thread while the "destroyed" callback may be joining it: several
//  functions of the ActionUI C adapter (actionUIGet..., actionUIInsertElement, ...) run
//  synchronously on the main thread when called from another thread, and would deadlock.
//
//  Lifetimes: actionUIHostSurfaceSetDelegate copies the delegate struct. The windowUUID and text
//  pointers a callback receives are valid only until it returns. userData is passed back
//  untouched and never read. The handle in AUIHostSurfaceInfo stays valid until the "destroyed"
//  callback for that surfaceID returns.
//

#ifndef ACTIONUI_HOSTSURFACE_H
#define ACTIONUI_HOSTSURFACE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// What the handle in AUIHostSurfaceInfo is.
typedef enum {
    AUIHostSurfaceMetalLayer = 1,      // handle: CAMetalLayer * (macOS, iOS)
    AUIHostSurfaceANativeWindow = 2,   // handle: ANativeWindow * (Android)
    AUIHostSurfaceGLArea = 3,          // handle: NULL; draw in the render callback (Linux)
    AUIHostSurfaceFrameSink = 4        // handle: NULL; present finished frames (Linux)
} AUIHostSurfaceKind;

/// The event passed to the surface callback.
///
/// - Created: the surface has a window, a nonzero pixel size and this delegate. The client builds
///   its swapchain (for wgpu: a surface from the layer, configured at the pixel size).
/// - Changed: the size or scale changed. Resize the swapchain to the new pixel size before the
///   next frame. Created and Changed always carry a nonzero pixel size.
/// - Suspended: the surface left the screen (hidden, its window closing, occluded or minimized,
///   the app in the background, a size of zero pixels, or a pending teardown). No frame callbacks
///   come while suspended, and the client must not ask the layer for a new drawable.
/// - Resumed: the surface is on screen again.
/// - Destroyed: synchronous. Stop all use of the handle before returning: join the render thread
///   and drop the swapchain. A surface that is replaced (for example the delegate changed) gets
///   Destroyed before its successor gets Created. Process exit sends no Destroyed.
typedef enum {
    AUIHostSurfaceCreated = 1,
    AUIHostSurfaceChanged = 2,
    AUIHostSurfaceSuspended = 3,
    AUIHostSurfaceResumed = 4,
    AUIHostSurfaceDestroyed = 5
} AUIHostSurfaceEvent;

typedef struct {
    uint32_t structSize;       // sizeof(AUIHostSurfaceInfo) of the sender; fields may be added at the end
    int32_t kind;              // AUIHostSurfaceKind
    void *handle;              // see AUIHostSurfaceKind; valid until Destroyed returns
    double widthPoints;
    double heightPoints;
    double scale;              // pixels per point
    uint32_t widthPixels;      // round(widthPoints * scale); nonzero in Created and Changed
    uint32_t heightPixels;
} AUIHostSurfaceInfo;

/// The kind of an input event. Pointer positions are in points from the top-left corner of the
/// surface.
typedef enum {
    AUIHostInputPointerDown = 1,
    AUIHostInputPointerUp = 2,
    AUIHostInputPointerMove = 3,       // no button down
    AUIHostInputPointerDrag = 4,       // a button or a touch down
    AUIHostInputPointerEnter = 5,
    AUIHostInputPointerExit = 6,
    AUIHostInputPointerCancel = 7,     // the system took the pointer (a touch became a gesture)
    AUIHostInputScroll = 8,            // deltaX, deltaY in scrollUnit; see AUIHostInputEvent
    AUIHostInputMagnify = 9,           // deltaX: added to the scale, 0.1 takes a scale of 1.0 to 1.1
    AUIHostInputRotate = 10,           // deltaX: rotation change in degrees, counterclockwise positive
    AUIHostInputKeyDown = 11,
    AUIHostInputKeyUp = 12,
    AUIHostInputFocusIn = 13,
    AUIHostInputFocusOut = 14
} AUIHostInputKind;

typedef enum {
    AUIHostPointerMouse = 0,
    AUIHostPointerTouch = 1,
    AUIHostPointerPen = 2
} AUIHostPointerType;

typedef enum {
    AUIHostScrollPoints = 0,           // precise deltas (trackpad, Magic Mouse)
    AUIHostScrollSteps = 1             // wheel steps (a notched mouse wheel)
} AUIHostScrollUnit;

typedef enum {
    AUIHostScrollPhaseNone = 0,        // a wheel step, no gesture
    AUIHostScrollPhaseBegan = 1,
    AUIHostScrollPhaseChanged = 2,
    AUIHostScrollPhaseEnded = 3,
    AUIHostScrollPhaseMomentum = 4,    // inertia after the fingers lifted
    AUIHostScrollPhaseMomentumEnded = 5
} AUIHostScrollPhase;

/// Bits of AUIHostInputEvent.modifiers.
enum {
    AUIHostModifierShift = 1,
    AUIHostModifierControl = 2,
    AUIHostModifierAlt = 4,            // Option on Apple
    AUIHostModifierMeta = 8,           // Command on Apple
    AUIHostModifierCapsLock = 16
};

/// The cursor over the surface, for actionUIHostSurfaceSetCursor. On iOS (a pointer on iPad) the
/// arrow, the I-beam and hidden are shown; the other shapes show the system pointer.
typedef enum {
    AUIHostCursorArrow = 0,
    AUIHostCursorIBeam = 1,
    AUIHostCursorCrosshair = 2,
    AUIHostCursorPointingHand = 3,
    AUIHostCursorOpenHand = 4,
    AUIHostCursorClosedHand = 5,
    AUIHostCursorResizeLeftRight = 6,
    AUIHostCursorResizeUpDown = 7,
    AUIHostCursorNotAllowed = 8,
    AUIHostCursorHidden = 9
} AUIHostCursor;

/// One input event, delivered to the client's input callback while the surface is on screen and its
/// element is enabled.
/// - Pointer events come for the mouse, trackpad clicks, touches (one event per touch) and the pen.
/// - The surface takes the scroll wheel, so an enclosing scroll view does not scroll as well.
/// - Keys come while the surface has keyboard focus. It never takes focus unasked: a click or tap
///   focuses it when the element's "focusable" is true (the default), and Tab and Shift-Tab move
///   focus in and out like any control (they are not delivered).
/// - FocusIn and FocusOut tell the client when keys start and stop coming. On macOS a focused surface
///   gets FocusOut when its window stops being key and FocusIn when it is key again; a client lets go of
///   keys held down at FocusOut, since their key up will not come.
typedef struct {
    uint32_t structSize;       // sizeof(AUIHostInputEvent) of the sender; fields may be added at the end
    int32_t kind;              // AUIHostInputKind
    int32_t pointerType;       // AUIHostPointerType
    int32_t button;            // 0 primary, 1 secondary, 2 middle
    int64_t pointerID;         // stable per touch while it lasts; 0 for the mouse
    uint32_t modifiers;        // AUIHostModifier bits
    int32_t clickCount;        // for PointerDown and PointerUp
    double x, y;               // points, origin at the top left of the surface
    // Scroll: how far the content should move, positive to the right and down, in scrollUnit.
    double deltaX, deltaY;
    int32_t scrollUnit;        // AUIHostScrollUnit
    int32_t scrollPhase;       // AUIHostScrollPhase
    double pressure;           // 0...1; 1 when down and the device has no pressure
    double tiltX, tiltY;       // pen tilt, -1...1
    uint32_t keyCode;          // platform key code (macOS virtual key code, iOS HID usage)
    const char *code;          // portable key name: the W3C UI Events "code" value, such as
                               // "KeyA" or "ArrowLeft"; "" when unknown; valid during the callback
    const char *text;          // UTF-8 text the key produced (KeyDown), or NULL, also for keys that
                               // produce no insertable text (arrows, function keys, Escape, Return,
                               // Backspace); valid during the callback
    double timestampSeconds;   // the platform event time, on its monotonic clock
} AUIHostInputEvent;

/// The callbacks of one client. Any of them may be NULL. Each gets the surfaceID, which the client
/// keys its state by and passes to the calls that address a surface, and the (windowUUID, viewID)
/// of the element, which relate it to the ActionUI document.
typedef struct {
    uint32_t structSize;       // sizeof(AUIHostSurfaceDelegate) of the client
    void (*surface)(uint64_t surfaceID, const char *windowUUID, int64_t viewID,
                    int32_t event, const AUIHostSurfaceInfo *info, void *userData);
    /// timestampSeconds: the target presentation time of the frame (CADisplayLink.targetTimestamp
    /// on Apple). Use differences only; it is not wall time.
    void (*frame)(uint64_t surfaceID, const char *windowUUID, int64_t viewID,
                  double timestampSeconds, void *userData);
    void (*input)(uint64_t surfaceID, const char *windowUUID, int64_t viewID,
                  const AUIHostInputEvent *event, void *userData);
    /// GL area only (Linux, "kind": "gl"): draw now, with GTK's GL context current and its framebuffer
    /// bound. Each frame callback asks for one; GTK also renders when it first shows or resizes the
    /// area. The surface callback runs with the context current too, so GL objects are made in Created
    /// and freed in Destroyed. Unused on Apple platforms and Android.
    void (*render)(uint64_t surfaceID, const char *windowUUID, int64_t viewID, void *userData);
} AUIHostSurfaceDelegate;

/// Registers the HostSurface element type with ActionUI. Main thread, once, before the first
/// document that uses the element loads.
void ActionUIHostSurface_register(void);

/// Binds a delegate to every HostSurface element whose "surfaceName" is surfaceName, in every
/// window, now and later. Pass NULL to unbind.
/// - Every live surface with that name gets Created at once (and Suspended after it when it is
///   off screen).
/// - Replacing or removing a delegate first sends Destroyed to the old one for every surface it
///   served.
/// - Called from inside a callback, it takes effect right after that callback returns.
/// Main thread only. Returns false, and does nothing, off the main thread or when surfaceName is
/// NULL or empty.
bool actionUIHostSurfaceSetDelegate(const char *surfaceName, const AUIHostSurfaceDelegate *delegate,
                                    void *userData);

/// Asks for one frame callback at the next display refresh. Any thread; never waits. Does nothing
/// when surfaceID is not a live surface (for example after its Destroyed).
void actionUIHostSurfaceRequestFrame(uint64_t surfaceID);

/// Turns frame callbacks at every display refresh on or off, overriding the element's
/// "continuous" property until the property changes value. Any thread; never waits. Does nothing
/// when surfaceID is not a live surface.
void actionUIHostSurfaceSetContinuous(uint64_t surfaceID, bool continuous);

/// Sets the cursor shown while the pointer is over the surface (an AUIHostCursor value), until the
/// next call or the surface's Destroyed. Main thread only. Returns false off the main thread, when
/// surfaceID is not a live surface, or when cursor is not an AUIHostCursor value.
bool actionUIHostSurfaceSetCursor(uint64_t surfaceID, int32_t cursor);

/// The layout of the pixels given to actionUIHostSurfacePresentPixels: 4 bytes per pixel, in this
/// order in memory.
typedef enum {
    AUIHostPixelBGRA8Premultiplied = 1,   // blue, green, red, alpha; colors premultiplied by alpha
    AUIHostPixelRGBA8Premultiplied = 2,   // red, green, blue, alpha; colors premultiplied by alpha
    AUIHostPixelBGRX8 = 3,                // blue, green, red, unused: opaque
    AUIHostPixelRGBX8 = 4                 // red, green, blue, unused: opaque
} AUIHostPixelFormat;

/// Frame sink only (AUIHostSurfaceFrameSink): shows one finished frame on the surface. The pixels are
/// copied before the call returns. Frames that come faster than the display refreshes are merged:
/// the newest is shown. The frame is drawn scaled to the surface, so render at the pixel size of the
/// last Created or Changed. Any thread; never waits.
/// Returns false, and shows nothing, when surfaceID is not a live frame-sink surface (for example
/// after its Destroyed, and always on Apple platforms, whose surfaces are Metal layers), when width
/// or height is 0, when stride is less than width * 4, when pixels is NULL, or when format is not an
/// AUIHostPixelFormat.
bool actionUIHostSurfacePresentPixels(uint64_t surfaceID, uint32_t width, uint32_t height, uint32_t stride,
                                      int32_t format, const void *pixels);

#ifdef __cplusplus
}
#endif

#endif // ACTIONUI_HOSTSURFACE_H

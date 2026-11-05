// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  hostsurface_c_demo.c
//  A C client of the HostSurface element (libhostsurface_c_demo.so), the native counterpart of
//  HostSurfaceDemoClient.kt: it binds to "demo.native" through the C interface (ActionUIHostSurface.h) and
//  draws into the ANativeWindow from the CPU: a moving color band, and a square where the last touch was.
//  Surface events go to logcat (tag HostSurfaceCDemo), and to a log the app can read (nativeEvents).
//
//  It finds the C functions in libactionui_hostsurface.so at run time (dlopen), so this demo needs no link
//  path into the add-on module's build folder; a client built outside Gradle (Rust, say) links it instead.
//

#include <ActionUIHostSurface.h>

#include <android/log.h>
#include <android/native_window.h>
#include <dlfcn.h>
#include <jni.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define LOG_TAG "HostSurfaceCDemo"

typedef bool (*SetDelegateFunction)(const char *, const AUIHostSurfaceDelegate *, void *);
typedef void (*SurfaceIDFunction)(uint64_t);
typedef void (*SetContinuousFunction)(uint64_t, bool);

static SetDelegateFunction setDelegate = NULL;
static SurfaceIDFunction requestFrame = NULL;
static SetContinuousFunction setContinuous = NULL;

/// The demo's one surface (all on the main thread).
static struct {
    uint64_t surfaceID;
    ANativeWindow *window;
    int32_t width;
    int32_t height;
    double scale;
    double touchX;
    double touchY;
    bool touched;
} demo;

/// The events so far, "CREATED 996x420; SUSPENDED; ...", for nativeEvents.
static char eventLog[4096];

static const char *eventName(int32_t event) {
    switch (event) {
        case AUIHostSurfaceCreated: return "CREATED";
        case AUIHostSurfaceChanged: return "CHANGED";
        case AUIHostSurfaceSuspended: return "SUSPENDED";
        case AUIHostSurfaceResumed: return "RESUMED";
        case AUIHostSurfaceDestroyed: return "DESTROYED";
        default: return "?";
    }
}

static void appendEvent(const char *text) {
    size_t used = strlen(eventLog);
    snprintf(eventLog + used, sizeof(eventLog) - used, "%s%s", used > 0 ? "; " : "", text);
}

static void onSurface(uint64_t surfaceID, const char *windowUUID, int64_t viewID, int32_t event,
                      const AUIHostSurfaceInfo *info, void *userData) {
    (void)windowUUID;
    (void)userData;
    char line[128];
    snprintf(line, sizeof(line), "%s %ux%u", eventName(event), info->widthPixels, info->heightPixels);
    appendEvent(line);
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "%s surface %llu view %lld kind %d", line,
                        (unsigned long long)surfaceID, (long long)viewID, info->kind);
    switch (event) {
        case AUIHostSurfaceCreated:
        case AUIHostSurfaceChanged:
            demo.surfaceID = surfaceID;
            demo.window = (ANativeWindow *)info->handle;
            demo.width = (int32_t)info->widthPixels;
            demo.height = (int32_t)info->heightPixels;
            demo.scale = info->scale;
            ANativeWindow_setBuffersGeometry(demo.window, demo.width, demo.height, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);
            requestFrame(surfaceID);
            break;
        case AUIHostSurfaceDestroyed:
            // The window is not used after this returns.
            if (demo.surfaceID == surfaceID) {
                demo.surfaceID = 0;
                demo.window = NULL;
            }
            break;
        default:
            break;
    }
}

static void onFrame(uint64_t surfaceID, const char *windowUUID, int64_t viewID, double seconds, void *userData) {
    (void)windowUUID;
    (void)viewID;
    (void)userData;
    if (surfaceID != demo.surfaceID || demo.window == NULL) {
        return;
    }
    ANativeWindow_Buffer buffer;
    if (ANativeWindow_lock(demo.window, &buffer, NULL) != 0) {
        return;
    }
    uint32_t *pixels = buffer.bits;
    int32_t band = (int32_t)(fmod(seconds * 0.25, 1.0) * buffer.width);
    int32_t square = buffer.height / 6;
    int32_t squareX = (int32_t)demo.touchX;
    int32_t squareY = (int32_t)demo.touchY;
    for (int32_t y = 0; y < buffer.height; y++) {
        uint32_t *row = pixels + (size_t)y * (size_t)buffer.stride;
        for (int32_t x = 0; x < buffer.width; x++) {
            // R8G8B8A8 in memory: 0xAABBGGRR as a little-endian word.
            uint32_t blue = (uint32_t)(80 + 120 * y / (buffer.height > 0 ? buffer.height : 1));
            uint32_t color = 0xFF000000u | (blue << 16) | (40u << 8) | 30u;
            if (x >= band && x < band + square) {
                color = 0xFF30C0F0u;
            }
            if (demo.touched && x >= squareX - square / 2 && x < squareX + square / 2 &&
                y >= squareY - square / 2 && y < squareY + square / 2) {
                color = 0xFFFFFFFFu;
            }
            row[x] = color;
        }
    }
    ANativeWindow_unlockAndPost(demo.window);
}

static void onInput(uint64_t surfaceID, const char *windowUUID, int64_t viewID, const AUIHostInputEvent *event,
                    void *userData) {
    (void)windowUUID;
    (void)viewID;
    (void)userData;
    if (event->kind == AUIHostInputPointerDown || event->kind == AUIHostInputPointerDrag) {
        demo.touched = true;
        // Input is in points; the buffer is in pixels, at the scale of the last CREATED or CHANGED.
        demo.touchX = event->x * demo.scale;
        demo.touchY = event->y * demo.scale;
        requestFrame(surfaceID);
    }
}

static AUIHostSurfaceDelegate delegate = {
    .structSize = sizeof(AUIHostSurfaceDelegate),
    .surface = onSurface,
    .frame = onFrame,
    .input = onInput,
    .render = NULL,
};

/// Binds the C client (true) or unbinds it (false). Main thread.
JNIEXPORT jboolean JNICALL
Java_com_abracode_actionui_addontest_HostSurfaceCDemo_nativeBind(JNIEnv *env, jclass demoClass, jboolean bind) {
    (void)env;
    (void)demoClass;
    if (setDelegate == NULL) {
        void *library = dlopen("libactionui_hostsurface.so", RTLD_NOW);
        if (library == NULL) {
            __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "dlopen: %s", dlerror());
            return JNI_FALSE;
        }
        setDelegate = (SetDelegateFunction)dlsym(library, "actionUIHostSurfaceSetDelegate");
        requestFrame = (SurfaceIDFunction)dlsym(library, "actionUIHostSurfaceRequestFrame");
        setContinuous = (SetContinuousFunction)dlsym(library, "actionUIHostSurfaceSetContinuous");
        if (setDelegate == NULL || requestFrame == NULL || setContinuous == NULL) {
            __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "dlsym: a HostSurface function is missing");
            setDelegate = NULL;
            return JNI_FALSE;
        }
    }
    return setDelegate("demo.native", bind ? &delegate : NULL, NULL) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_abracode_actionui_addontest_HostSurfaceCDemo_nativeEvents(JNIEnv *env, jclass demoClass) {
    (void)demoClass;
    return (*env)->NewStringUTF(env, eventLog);
}

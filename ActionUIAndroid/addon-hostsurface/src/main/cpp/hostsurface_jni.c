// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  hostsurface_jni.c
//  The HostSurface add-on's C interface on Android (libactionui_hostsurface.so)
//
//  The same C functions as on the other platforms (ActionUIHostSurface.h), for C, C++ and Rust clients,
//  over the add-on's Kotlin API (HostSurfaces.kt) through JNI:
//  - actionUIHostSurfaceSetDelegate copies the client's delegate struct and binds a Kotlin delegate that
//    forwards to it (HostSurfaceNative.kt); the Kotlin registry applies the usual rules.
//  - A surface's android.view.Surface becomes an ANativeWindow at CREATED. The library holds a reference
//    until DESTROYED for that surface has returned, so the handle stays valid as long as the header says.
//  - The library must be loaded with System.loadLibrary("actionui_hostsurface") before a client calls in
//    (the add-on's ContentProvider does it at process start), so JNI_OnLoad caches the Java VM and the
//    Kotlin bridge class: a thread that a client started has no class loader to find it with.
//

#include <ActionUIHostSurface.h>

#include <android/log.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <pthread.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LOG_TAG "ActionUIHostSurface"
#define EXPORT __attribute__((visibility("default")))

static JavaVM *javaVM = NULL;
static jclass bridgeClass = NULL;
static jmethodID registerMethod = NULL;
static jmethodID setDelegateMethod = NULL;
static jmethodID requestFrameMethod = NULL;
static jmethodID setContinuousMethod = NULL;
static jmethodID setCursorMethod = NULL;

/// One bound client: its delegate (copied) and userData. Freed by the bridge when the binding is retired.
typedef struct {
    AUIHostSurfaceDelegate delegate;
    void *userData;
} HostSurfaceClient;

// MARK: - Threads

static bool isMainThread(void) {
    // An app process's main thread is the one whose thread ID is the process ID.
    return gettid() == getpid();
}

static pthread_key_t detachKey;
static pthread_once_t detachKeyOnce = PTHREAD_ONCE_INIT;

static void detachThread(void *unused) {
    (void)unused;
    if (javaVM != NULL) {
        (*javaVM)->DetachCurrentThread(javaVM);
    }
}

static void makeDetachKey(void) {
    pthread_key_create(&detachKey, detachThread);
}

/// The calling thread's JNIEnv, attaching a client's thread to the VM on its first call (it is detached when
/// the thread ends). NULL before JNI_OnLoad or when the thread cannot be attached.
static JNIEnv *currentEnv(void) {
    if (javaVM == NULL) {
        return NULL;
    }
    JNIEnv *env = NULL;
    jint status = (*javaVM)->GetEnv(javaVM, (void **)&env, JNI_VERSION_1_6);
    if (status == JNI_OK) {
        return env;
    }
    if (status != JNI_EDETACHED) {
        return NULL;
    }
    if ((*javaVM)->AttachCurrentThread(javaVM, &env, NULL) != JNI_OK) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "could not attach a thread to the Java VM");
        return NULL;
    }
    pthread_once(&detachKeyOnce, makeDetachKey);
    pthread_setspecific(detachKey, env);
    return env;
}

/// Logs and clears a pending Java exception. True when there was one.
static bool clearException(JNIEnv *env, const char *what) {
    if (!(*env)->ExceptionCheck(env)) {
        return false;
    }
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s threw", what);
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
    return true;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    JNIEnv *env = NULL;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }
    jclass found = (*env)->FindClass(env, "com/abracode/actionui/addon/hostsurface/HostSurfaceNative");
    if (found == NULL) {
        clearException(env, "FindClass HostSurfaceNative");
        return JNI_ERR;
    }
    bridgeClass = (*env)->NewGlobalRef(env, found);
    (*env)->DeleteLocalRef(env, found);
    registerMethod = (*env)->GetStaticMethodID(env, bridgeClass, "register", "()V");
    setDelegateMethod = (*env)->GetStaticMethodID(env, bridgeClass, "setDelegate", "(Ljava/lang/String;J)Z");
    requestFrameMethod = (*env)->GetStaticMethodID(env, bridgeClass, "requestFrame", "(J)V");
    setContinuousMethod = (*env)->GetStaticMethodID(env, bridgeClass, "setContinuous", "(JZ)V");
    setCursorMethod = (*env)->GetStaticMethodID(env, bridgeClass, "setCursor", "(JI)Z");
    if (registerMethod == NULL || setDelegateMethod == NULL || requestFrameMethod == NULL ||
        setContinuousMethod == NULL || setCursorMethod == NULL) {
        clearException(env, "GetStaticMethodID on HostSurfaceNative");
        return JNI_ERR;
    }
    javaVM = vm;
    return JNI_VERSION_1_6;
}

// MARK: - The C interface

EXPORT void ActionUIHostSurface_register(void) {
    // The ContentProvider registers the element at process start; this is the same call, for symmetry.
    JNIEnv *env = isMainThread() ? currentEnv() : NULL;
    if (env == NULL) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "ActionUIHostSurface_register: main thread only, after the library is loaded");
        return;
    }
    (*env)->CallStaticVoidMethod(env, bridgeClass, registerMethod);
    clearException(env, "HostSurfaceNative.register");
}

/// Copies a client's delegate struct, honoring its structSize: a client built against an older, shorter
/// struct gets NULL for the callbacks it does not know. False when structSize does not cover the first
/// callback.
static bool copyDelegate(const AUIHostSurfaceDelegate *delegate, AUIHostSurfaceDelegate *copy) {
    size_t theirs = delegate->structSize;
    if (theirs < offsetof(AUIHostSurfaceDelegate, frame)) {
        return false;
    }
    size_t ours = sizeof(AUIHostSurfaceDelegate);
    size_t count = theirs < ours ? theirs : ours;
    // Whole fields only: the callbacks are pointers, so a size that ends inside one stops before it.
    count = count / sizeof(void *) * sizeof(void *);
    memset(copy, 0, sizeof(*copy));
    memcpy(copy, delegate, count);
    copy->structSize = (uint32_t)ours;
    return true;
}

EXPORT bool actionUIHostSurfaceSetDelegate(const char *surfaceName, const AUIHostSurfaceDelegate *delegate,
                                           void *userData) {
    if (surfaceName == NULL || surfaceName[0] == '\0' || !isMainThread()) {
        return false;
    }
    JNIEnv *env = currentEnv();
    if (env == NULL) {
        return false;
    }
    HostSurfaceClient *client = NULL;
    if (delegate != NULL) {
        client = calloc(1, sizeof(HostSurfaceClient));
        if (client == NULL) {
            return false;
        }
        if (!copyDelegate(delegate, &client->delegate)) {
            free(client);
            return false;
        }
        client->userData = userData;
    }
    jstring name = (*env)->NewStringUTF(env, surfaceName);
    if (name == NULL) {
        clearException(env, "NewStringUTF");
        free(client);
        return false;
    }
    jboolean bound = (*env)->CallStaticBooleanMethod(env, bridgeClass, setDelegateMethod, name,
                                                     (jlong)(intptr_t)client);
    (*env)->DeleteLocalRef(env, name);
    if (clearException(env, "HostSurfaceNative.setDelegate")) {
        // A callback the change ran threw, possibly after the registry took the client: it may be bound, and the
        // registry frees it when it retires the binding, so it is not freed here.
        return false;
    }
    if (bound == JNI_FALSE) {
        // Not bound, so the bridge never took the client.
        free(client);
        return false;
    }
    return true;
}

EXPORT void actionUIHostSurfaceRequestFrame(uint64_t surfaceID) {
    JNIEnv *env = currentEnv();
    if (env == NULL) {
        return;
    }
    (*env)->CallStaticVoidMethod(env, bridgeClass, requestFrameMethod, (jlong)surfaceID);
    clearException(env, "HostSurfaceNative.requestFrame");
}

EXPORT void actionUIHostSurfaceSetContinuous(uint64_t surfaceID, bool continuous) {
    JNIEnv *env = currentEnv();
    if (env == NULL) {
        return;
    }
    (*env)->CallStaticVoidMethod(env, bridgeClass, setContinuousMethod, (jlong)surfaceID,
                                 continuous ? JNI_TRUE : JNI_FALSE);
    clearException(env, "HostSurfaceNative.setContinuous");
}

EXPORT bool actionUIHostSurfaceSetCursor(uint64_t surfaceID, int32_t cursor) {
    if (!isMainThread()) {
        return false;
    }
    JNIEnv *env = currentEnv();
    if (env == NULL) {
        return false;
    }
    jboolean set = (*env)->CallStaticBooleanMethod(env, bridgeClass, setCursorMethod, (jlong)surfaceID, (jint)cursor);
    if (clearException(env, "HostSurfaceNative.setCursor")) {
        return false;
    }
    return set == JNI_TRUE;
}

EXPORT bool actionUIHostSurfacePresentPixels(uint64_t surfaceID, uint32_t width, uint32_t height, uint32_t stride,
                                             int32_t format, const void *pixels) {
    // Android surfaces are native windows, not frame sinks.
    (void)surfaceID;
    (void)width;
    (void)height;
    (void)stride;
    (void)format;
    (void)pixels;
    return false;
}

// MARK: - Native windows, by surfaceID (main thread only)

typedef struct {
    uint64_t surfaceID;
    ANativeWindow *window;
} SurfaceWindow;

static SurfaceWindow *windows = NULL;
static size_t windowCount = 0;
static size_t windowCapacity = 0;

static ANativeWindow *windowFor(uint64_t surfaceID) {
    for (size_t index = 0; index < windowCount; index++) {
        if (windows[index].surfaceID == surfaceID) {
            return windows[index].window;
        }
    }
    return NULL;
}

static bool addWindow(uint64_t surfaceID, ANativeWindow *window) {
    if (windowCount == windowCapacity) {
        size_t capacity = windowCapacity == 0 ? 4 : windowCapacity * 2;
        SurfaceWindow *grown = realloc(windows, capacity * sizeof(SurfaceWindow));
        if (grown == NULL) {
            return false;
        }
        windows = grown;
        windowCapacity = capacity;
    }
    windows[windowCount].surfaceID = surfaceID;
    windows[windowCount].window = window;
    windowCount += 1;
    return true;
}

static void releaseWindow(uint64_t surfaceID) {
    for (size_t index = 0; index < windowCount; index++) {
        if (windows[index].surfaceID == surfaceID) {
            ANativeWindow_release(windows[index].window);
            windows[index] = windows[windowCount - 1];
            windowCount -= 1;
            return;
        }
    }
}

// MARK: - From the Kotlin bridge (HostSurfaceNative.kt), on the main thread

// Strings come as NUL-terminated UTF-8 byte arrays: GetStringUTFChars gives modified UTF-8, which is not
// UTF-8 for characters outside the Basic Multilingual Plane.

/// The C string in a NUL-terminated byte array, or NULL for a NULL or empty array; release with releaseUTF8.
static const char *borrowUTF8(JNIEnv *env, jbyteArray bytes) {
    if (bytes == NULL || (*env)->GetArrayLength(env, bytes) == 0) {
        return NULL;
    }
    return (const char *)(*env)->GetByteArrayElements(env, bytes, NULL);
}

static void releaseUTF8(JNIEnv *env, jbyteArray bytes, const char *chars) {
    if (chars != NULL) {
        (*env)->ReleaseByteArrayElements(env, bytes, (jbyte *)chars, JNI_ABORT);
    }
}

JNIEXPORT void JNICALL
Java_com_abracode_actionui_addon_hostsurface_HostSurfaceNative_nativeSurface(
    JNIEnv *env, jclass bridge, jlong handle, jint event, jlong surfaceID, jbyteArray windowUUID, jint viewID,
    jobject surface, jint widthPixels, jint heightPixels, jfloat density) {
    (void)bridge;
    HostSurfaceClient *client = (HostSurfaceClient *)(intptr_t)handle;
    uint64_t identifier = (uint64_t)surfaceID;
    ANativeWindow *window = windowFor(identifier);
    if (event == AUIHostSurfaceCreated && window == NULL) {
        window = ANativeWindow_fromSurface(env, surface);
        if (window == NULL || !addWindow(identifier, window)) {
            __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "no native window for surface %llu",
                                (unsigned long long)identifier);
            if (window != NULL) {
                ANativeWindow_release(window);
            }
            return;
        }
    }
    if (window == NULL) {
        // Not announced to this client (its CREATED failed above): nothing to tell.
        return;
    }
    if (client != NULL && client->delegate.surface != NULL) {
        double scale = density > 0 ? (double)density : 1.0;
        AUIHostSurfaceInfo info = {
            .structSize = sizeof(AUIHostSurfaceInfo),
            .kind = AUIHostSurfaceANativeWindow,
            .handle = window,
            .widthPoints = widthPixels / scale,
            .heightPoints = heightPixels / scale,
            .scale = scale,
            .widthPixels = (uint32_t)widthPixels,
            .heightPixels = (uint32_t)heightPixels,
        };
        const char *uuid = borrowUTF8(env, windowUUID);
        client->delegate.surface(identifier, uuid != NULL ? uuid : "", viewID, event, &info, client->userData);
        releaseUTF8(env, windowUUID, uuid);
    }
    if (event == AUIHostSurfaceDestroyed) {
        // After the client's DESTROYED has returned: it has stopped using the window.
        releaseWindow(identifier);
    }
}

JNIEXPORT void JNICALL
Java_com_abracode_actionui_addon_hostsurface_HostSurfaceNative_nativeFrame(
    JNIEnv *env, jclass bridge, jlong handle, jlong surfaceID, jbyteArray windowUUID, jint viewID, jdouble seconds) {
    (void)bridge;
    HostSurfaceClient *client = (HostSurfaceClient *)(intptr_t)handle;
    if (client == NULL || client->delegate.frame == NULL || windowFor((uint64_t)surfaceID) == NULL) {
        return;
    }
    const char *uuid = borrowUTF8(env, windowUUID);
    client->delegate.frame((uint64_t)surfaceID, uuid != NULL ? uuid : "", viewID, seconds, client->userData);
    releaseUTF8(env, windowUUID, uuid);
}

JNIEXPORT void JNICALL
Java_com_abracode_actionui_addon_hostsurface_HostSurfaceNative_nativeInput(
    JNIEnv *env, jclass bridge, jlong handle, jlong surfaceID, jbyteArray windowUUID, jint viewID,
    jintArray integers, jdoubleArray doubles, jlong pointerID, jbyteArray code, jbyteArray text) {
    (void)bridge;
    HostSurfaceClient *client = (HostSurfaceClient *)(intptr_t)handle;
    if (client == NULL || client->delegate.input == NULL || windowFor((uint64_t)surfaceID) == NULL) {
        return;
    }
    // The order of HostSurfaceNative.forwardInput's arrays.
    jint ints[8] = {0};
    jdouble reals[10] = {0};
    if ((*env)->GetArrayLength(env, integers) < 8 || (*env)->GetArrayLength(env, doubles) < 10) {
        return;
    }
    (*env)->GetIntArrayRegion(env, integers, 0, 8, ints);
    (*env)->GetDoubleArrayRegion(env, doubles, 0, 10, reals);
    AUIHostInputEvent event = {
        .structSize = sizeof(AUIHostInputEvent),
        .kind = ints[0],
        .pointerType = ints[1],
        .button = ints[2],
        .pointerID = pointerID,
        .modifiers = (uint32_t)ints[3],
        .clickCount = ints[4],
        .scrollUnit = ints[5],
        .scrollPhase = ints[6],
        .keyCode = (uint32_t)ints[7],
        .x = reals[0],
        .y = reals[1],
        .deltaX = reals[2],
        .deltaY = reals[3],
        .pressure = reals[4],
        .tiltX = reals[5],
        .tiltY = reals[6],
        .timestampSeconds = reals[7],
    };
    const char *uuid = borrowUTF8(env, windowUUID);
    const char *codeChars = borrowUTF8(env, code);
    const char *textChars = borrowUTF8(env, text);
    event.code = codeChars != NULL ? codeChars : "";
    event.text = textChars;
    client->delegate.input((uint64_t)surfaceID, uuid != NULL ? uuid : "", viewID, &event, client->userData);
    releaseUTF8(env, windowUUID, uuid);
    releaseUTF8(env, code, codeChars);
    releaseUTF8(env, text, textChars);
}

JNIEXPORT void JNICALL
Java_com_abracode_actionui_addon_hostsurface_HostSurfaceNative_nativeFree(JNIEnv *env, jclass bridge, jlong handle) {
    (void)env;
    (void)bridge;
    free((HostSurfaceClient *)(intptr_t)handle);
}

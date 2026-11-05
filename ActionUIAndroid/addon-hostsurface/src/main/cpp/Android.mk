# libactionui_hostsurface.so: the HostSurface add-on's C interface on Android (hostsurface_jni.c), for C, C++ and
# Rust clients. Built with ndk-build, which comes with the NDK (no CMake package to install). The header is the
# one every platform uses, in the Apple add-on's folder of this repository.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := actionui_hostsurface
LOCAL_SRC_FILES := hostsurface_jni.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/../../../../../Add-ons/ActionUIHostSurface/Sources/CActionUIHostSurface/include
# Only the C interface and the JNI functions are exported (EXPORT and JNIEXPORT in the source).
LOCAL_CFLAGS := -std=c11 -Wall -Wextra -Werror -fvisibility=hidden
LOCAL_LDLIBS := -landroid -llog
include $(BUILD_SHARED_LIBRARY)

# libhostsurface_c_demo.so: a C client of the HostSurface element for the add-on test app
# (hostsurface_c_demo.c). It finds the add-on's C functions at run time, so it only needs the header.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := hostsurface_c_demo
LOCAL_SRC_FILES := hostsurface_c_demo.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/../../../../../Add-ons/ActionUIHostSurface/Sources/CActionUIHostSurface/include
LOCAL_CFLAGS := -std=c11 -Wall -Wextra -Werror
LOCAL_LDLIBS := -landroid -llog -ldl -lm
include $(BUILD_SHARED_LIBRARY)

//  native-lib.c - the JNI bridge between Kotlin and the shared C brain.
//
//  This is the ONLY Android-specific native code. It does not do any conversion
//  math itself; it forwards straight into aui_convert(), which lives in the shared
//  convert.c (compiled unchanged here by the NDK, exactly as Apple compiles it).
//
//  The export name follows JNI's mangling: Java_<package-with-underscores>_<Class>_<method>.
//  Here that is:
//    com.abracode.actionui.examples.unitconverter.NativeBridge#nativeConvert
//  -> Java_com_abracode_actionui_examples_unitconverter_NativeBridge_nativeConvert

#include <jni.h>
#include <android/log.h>
#include "convert.h"

#define TAG "UnitConverterNative"

// One-time breadcrumb so logcat confirms the shared .so loaded.
JNIEXPORT void JNICALL
Java_com_abracode_actionui_examples_unitconverter_NativeBridge_nativeHello(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    __android_log_print(ANDROID_LOG_INFO, TAG, "shared convert.c loaded via JNI");
}

// The one real entry point: forward (category, fromUnit, toUnit, value) into the
// shared C function and return its double result.
JNIEXPORT jdouble JNICALL
Java_com_abracode_actionui_examples_unitconverter_NativeBridge_nativeConvert(
        JNIEnv *env, jobject thiz,
        jint category, jint fromUnit, jint toUnit, jdouble value) {
    (void)env;
    (void)thiz;
    return aui_convert((int)category, (int)fromUnit, (int)toUnit, (double)value);
}

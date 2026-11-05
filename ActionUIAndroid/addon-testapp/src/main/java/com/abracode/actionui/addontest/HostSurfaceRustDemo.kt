package com.abracode.actionui.addontest

import android.util.Log

/**
 * The Rust client of the HostSurface demo (ActionUIRust/actionui/examples/host_surface_android.rs): wgpu
 * draws into "demo.rust" on the element's native window, through the add-on's C interface. The library is
 * in the APK only when the app is built with -PrustDemoLibs=<folder with arm64-v8a/libhost_surface_android.so>
 * (see ActionUIRust/BUILD_GUIDE.md); without it the canvas stays empty. Its events are in logcat under
 * HostSurfaceRust.
 */
object HostSurfaceRustDemo {
    /** Loads the Rust library and binds its client. Main thread, after the add-on's provider ran. */
    fun install() {
        try {
            System.loadLibrary("host_surface_android")
        } catch (error: UnsatisfiedLinkError) {
            Log.i("HostSurfaceRust", "the Rust demo is not in this build")
            return
        }
        if (!nativeBind()) {
            Log.w("HostSurfaceRust", "the Rust client could not bind")
        }
    }

    @JvmStatic
    private external fun nativeBind(): Boolean
}

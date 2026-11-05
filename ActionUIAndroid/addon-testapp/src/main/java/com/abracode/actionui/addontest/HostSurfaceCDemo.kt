package com.abracode.actionui.addontest

import android.util.Log

/**
 * The C client of the HostSurface demo (src/main/cpp/hostsurface_c_demo.c): it binds to "demo.native" through
 * the add-on's C interface (libactionui_hostsurface.so), as a C, C++ or Rust program would, and draws into the
 * native window from the CPU. Its surface events are in logcat under HostSurfaceCDemo.
 */
object HostSurfaceCDemo {
    /** Loads the demo's library and binds the C client. Main thread, after the add-on's provider ran. */
    fun install() {
        try {
            System.loadLibrary("hostsurface_c_demo")
        } catch (error: UnsatisfiedLinkError) {
            Log.w("HostSurfaceCDemo", "the C demo is not in this build: ${error.message}")
            return
        }
        if (!nativeBind(true)) {
            Log.w("HostSurfaceCDemo", "the C client could not bind")
        }
    }

    /** The surface events the C client got, "CREATED 996x420; SUSPENDED; ...". */
    fun events(): String = nativeEvents()

    @JvmStatic
    private external fun nativeBind(bind: Boolean): Boolean

    @JvmStatic
    private external fun nativeEvents(): String
}

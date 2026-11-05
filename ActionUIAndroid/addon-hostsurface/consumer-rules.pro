# libactionui_hostsurface.so looks these up by name (JNI_OnLoad in src/main/cpp/hostsurface_jni.c). Nothing in Kotlin
# calls the bridge methods, so a minified app would otherwise strip or rename them and C clients could not bind.
-keep class com.abracode.actionui.addon.hostsurface.HostSurfaceNative {
    public static *** register();
    public static *** setDelegate(java.lang.String, long);
    public static *** requestFrame(long);
    public static *** setContinuous(long, boolean);
    public static *** setCursor(long, int);
    native <methods>;
}

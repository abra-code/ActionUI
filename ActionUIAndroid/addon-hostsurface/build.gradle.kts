// The ActionUI `HostSurface` add-on element for Android: a part of the layout that the app draws with its own
// renderer (Vulkan, OpenGL ES, wgpu, or a Canvas) through an android.view.Surface. It mirrors the Apple add-on
// `Add-ons/ActionUIHostSurface`. Structure follows the :map-osm template: a self-registering ContentProvider,
// the element, and the client API (`HostSurfaces.setDelegate`). No dependency beyond the core library.

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.abracode.actionui.addon.hostsurface"
    compileSdk = 36

    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
    }
    testOptions {
        // The registry tests build SurfaceInfo values; android.jar's stubs return defaults instead of throwing.
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    api(project(":library"))
    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)
    implementation(libs.androidx.compose.ui)
    // ActionUIElement.properties is a kotlinx JsonObject in the element API.
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    // A library's instrumented tests run in the test APK itself, so the test activity goes there.
    androidTestImplementation(libs.androidx.compose.ui.test.manifest)
}

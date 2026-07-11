// The ActionUI `CachedImage` add-on element for Android. A thin ActionUIViewConstruction that wraps the
// AsyncImageCache library's `CachedImage` composable (the two-tier memory+disk cache), mirroring the Apple
// add-on `Add-ons/ActionUICachedImage`. Structure follows the :map-osm template: a self-registering
// ContentProvider plus a single element-construction object. The one element-specific dependency is the
// AsyncImageCache library, consumed via the composite build (see settings.gradle.kts includeBuild).

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.abracode.actionui.addon.cachedimage"
    compileSdk = 36
    defaultConfig { minSdk = 31 }
    compileOptions {
        // Java 17 to match the AsyncImageCache library it links (the other ActionUIAndroid modules target 11;
        // consuming a 17-bytecode library from an 11 module is fine for D8, but keeping this module at 17 avoids
        // the mixed-target compiler warning on the direct dependency).
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

dependencies {
    api(project(":library"))                        // core ActionUI, re-exported like the map modules

    // The element-specific dependency: substituted for AsyncImageCache's local Gradle build by includeBuild.
    implementation("com.abracode:asyncimagecache")

    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)
    implementation(libs.androidx.compose.ui)
    implementation(libs.kotlinx.serialization.json)  // ActionUIElement.properties is a kotlinx JsonObject

    testImplementation(libs.junit)
}

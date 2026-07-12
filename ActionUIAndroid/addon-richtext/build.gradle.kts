// The ActionUI `RichText` add-on element for Android. A thin ActionUIViewConstruction that wraps the RichText
// Compose renderer (com.abracode:richtext), mirroring the Apple add-on `Add-ons/ActionUIRichText`. Structure
// follows the :addon-cachedimage template: a self-registering ContentProvider plus a single element-construction
// object. The one element-specific dependency is the RichText library, consumed via the composite build (see
// settings.gradle.kts includeBuild); RichText in turn pulls AsyncImageCache for inline images.

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.abracode.actionui.addon.richtext"
    compileSdk = 36
    defaultConfig { minSdk = 31 }
    compileOptions {
        // Java 17 to match the RichText library it links (the other ActionUIAndroid modules target 11; keeping
        // this module at 17 avoids the mixed-target compiler warning on the direct dependency, as CachedImage does).
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

dependencies {
    api(project(":library"))                    // core ActionUI, re-exported like the map / CachedImage modules

    // The element-specific dependency: substituted for the RichText library's local Gradle build by includeBuild.
    implementation("com.abracode:richtext")

    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)
    implementation(libs.androidx.compose.ui)
    implementation(libs.kotlinx.serialization.json)  // ActionUIElement.properties is a kotlinx JsonObject

    testImplementation(libs.junit)
}

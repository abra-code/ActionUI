plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.abracode.actionui.examples.temperatureconverter"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.abracode.actionui.examples.temperatureconverter"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures { compose = true }

    // Single source of truth for the UI: package the shared JSON directly from
    // ../../shared as an extra assets directory. Use a plain path string (a
    // static directory) - AGP 9 rejects Provider-based srcDirs on the SourceSet
    // API ("You cannot add Provider instances to the Android SourceSet API").
    sourceSets["main"].assets.srcDir("../../shared")
}

dependencies {
    // Substituted to ActionUIAndroid's :library by the composite build (settings.gradle.kts).
    implementation("com.abracode.actionui:library")

    implementation(platform("androidx.compose:compose-bom:2026.02.01"))
    implementation("androidx.activity:activity-compose:1.8.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.core:core-ktx:1.10.1")
}

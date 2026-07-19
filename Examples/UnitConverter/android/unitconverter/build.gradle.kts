plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.abracode.actionui.examples.unitconverter"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.abracode.actionui.examples.unitconverter"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        // The shared C brain is built for these ABIs by the NDK (see cpp/CMakeLists.txt).
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures { compose = true }

    // THE DISTINCTIVE PART: compile shared/c/convert.c (plus the thin JNI wrapper)
    // with the NDK. CMake builds libunitconverter_native.so, which Kotlin loads and
    // calls over JNI. This is the SAME convert.c that the Apple ConvertC package
    // compiles, so iOS/macOS and Android return identical numbers.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Single source of truth for the UI: package the shared JSON directly from
    // ../../shared as an extra assets directory. Use a plain path string (a static
    // directory) - AGP 9 rejects Provider-based srcDirs on the SourceSet API
    // ("You cannot add Provider instances to the Android SourceSet API").
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

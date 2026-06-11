plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

// The OpenStreetMap provider for the ActionUI `Map` element: Leaflet (bundled
// in this module's assets) in the platform WebView - no Gradle dependency
// beyond the core library, no API key. Linking this module is all a client
// does: it self-registers at app startup (see OsmMapProvider). Link exactly
// one Map provider module.

android {
    namespace = "com.abracode.actionui.map.osm"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 31
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
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
}

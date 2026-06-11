plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

// The Google Maps provider for the ActionUI `Map` element: the native map
// via Google's official maps-compose (a Play Services client library).
// Linking this module is all a client does code-wise: it self-registers at
// app startup (see GoogleMapProvider). Link exactly one Map provider module.
//
// Host requirements, unlike :map-osm: a Maps API key in the app manifest
//   <meta-data android:name="com.google.android.geo.API_KEY"
//              android:value="YOUR_KEY"/>
// (tied to a billing-enabled Google Cloud project), and Google Play
// services on the device.

android {
    namespace = "com.abracode.actionui.map.google"
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
    // Google's official Compose wrapper for the Maps SDK (pulls
    // play-services-maps transitively).
    implementation(libs.maps.compose)
    testImplementation(libs.junit)
}

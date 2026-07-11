// ActionUI Add-On Test App - the Android counterpart of Apple's Add-ons/ActionUIAddOnTestApp. It exists so the
// core :demoApp (and the core :library) stay free of any add-on dependency: add-on elements are optional, and
// this small app is the only place that links them and exercises their example documents. Currently it links
// the :addon-cachedimage element (which pulls AsyncImageCache via the composite build); further add-ons would
// be added here the same way.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.abracode.actionui.addontest"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.abracode.actionui.addontest"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        // 17 to match the AsyncImageCache library linked transitively through :addon-cachedimage.
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":library"))
    // The add-on(s) under test. Each self-registers its element at startup via a ContentProvider.
    implementation(project(":addon-cachedimage"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.core.ktx)
}

// ── ActionUI JSON asset validation ───────────────────────────────────────────
// Same as the core demoApp: runs the shared Python validator over this app's add-on documents. Add-on element
// schemas (e.g. CachedImage) are auto-discovered from Add-ons/<AddOn>/Schemas when the validator runs in-place.
fun isPythonAvailable(): Boolean = try {
    ProcessBuilder("python3", "--version").redirectErrorStream(true).start().waitFor() == 0
} catch (e: Exception) {
    false
}

val verifyJsonResources by tasks.registering(Exec::class) {
    group = "verification"
    description = "Validate ActionUI add-on JSON assets for the Android platform."

    val repoRoot = rootProject.projectDir.parentFile
    val validator = repoRoot.resolve("Tools/verifier/validate_actionui.py")
    val assetsDir = layout.projectDirectory.dir("src/main/assets").asFile

    inputs.dir(assetsDir).withPropertyName("assets")
    inputs.file(validator).withPropertyName("validator")
    val marker = layout.buildDirectory.file("actionui/json-validation.ok")
    outputs.file(marker)

    workingDir = repoRoot
    commandLine("python3", validator.path, assetsDir.path, "--recursive", "--platform", "android")

    doFirst {
        if (!isPythonAvailable()) {
            logger.warn("python3 not found on PATH — skipping ActionUI JSON validation")
            throw StopExecutionException()
        }
        if (!validator.exists()) {
            logger.warn("ActionUI validator not found at $validator — skipping")
            throw StopExecutionException()
        }
    }
    doLast {
        marker.get().asFile.apply {
            parentFile.mkdirs()
            writeText("ok\n")
        }
    }
}

tasks.named("preBuild") {
    dependsOn(verifyJsonResources)
}

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.abracode.actionui.demo"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.abracode.actionui.demo"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
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
    implementation(platform(libs.androidx.compose.bom))
    implementation(project(":library"))
    // Exactly one Map provider module; it self-registers at startup.
    implementation(project(":map-osm"))
    // Add-on elements (e.g. :addon-cachedimage) are deliberately NOT linked here - the core demo app stays
    // free of add-on and AsyncImageCache dependencies, mirroring the Apple side. The separate :addon-testapp
    // module exercises the CachedImage add-on.
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}

// ── ActionUI JSON asset validation ───────────────────────────────────────────
// Android counterpart of the Xcode "verify_json_resources" run-script phase
// (ActionUISwiftTestApp/Scripts/verify_json_resources.sh). Runs the shared
// Python validator over the demoApp assets, filtering platform-suffixed keys for
// "android", and fails the build if any document is invalid. The equivalent
// standalone / CI entry point is scripts/verify_json_resources.sh.
fun isPythonAvailable(): Boolean = try {
    ProcessBuilder("python3", "--version")
        .redirectErrorStream(true)
        .start()
        .waitFor() == 0
} catch (e: Exception) {
    false
}

val verifyJsonResources by tasks.registering(Exec::class) {
    group = "verification"
    description = "Validate ActionUI JSON assets for the Android platform."

    val repoRoot = rootProject.projectDir.parentFile
    val validator = repoRoot.resolve("Tools/verifier/validate_actionui.py")
    val assetsDir = layout.projectDirectory.dir("src/main/assets").asFile

    // Incremental: only re-run when the assets or the validator change.
    inputs.dir(assetsDir).withPropertyName("assets")
    inputs.file(validator).withPropertyName("validator")
    val marker = layout.buildDirectory.file("actionui/json-validation.ok")
    outputs.file(marker)

    workingDir = repoRoot
    commandLine(
        "python3", validator.path, assetsDir.path,
        "--recursive", "--platform", "android",
    )

    // Don't break builds on machines without python3 (matches the shell script):
    // warn and skip instead of failing.
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

// Run before every build (CLI and Android Studio), like an Xcode build phase.
tasks.named("preBuild") {
    dependsOn(verifyJsonResources)
}

// ActionUI shared images: generates aui_* drawables (+ exact keep rules) from
// the Apple-named files in sharedImages/. This one line is the whole host
// integration; see the script header and Private/Android_Asset_Image_Design.md.
apply(from = "../actionui-images.gradle")

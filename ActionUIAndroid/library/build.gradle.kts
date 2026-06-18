plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.abracode.actionui"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 31

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
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
    val composeBom = platform(libs.androidx.compose.bom)
    api(composeBom)
    api(libs.androidx.compose.ui)
    api(libs.androidx.compose.ui.graphics)
    api(libs.androidx.compose.material3)
    api(libs.androidx.compose.material3.adaptive)
    api(libs.androidx.compose.material3.adaptive.layout)
    api(libs.androidx.compose.material3.adaptive.navigation)
    api(libs.androidx.navigation.compose)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
}

// -- Material Symbols (Rounded) variable font fetch ----------------------------
// The Material Symbols Rounded variable font is the Android render source for
// Image `materialName` (and, once the SF->Material map lands, `systemName`)
// glyphs - see Helpers/MaterialSymbolFont.kt. It is ~15 MB, so it is NOT
// committed (see .gitignore); this task downloads the font into
// src/main/assets/fonts/ and the name->codepoint table into
// src/main/assets/symbols/ (next to the SF->Material map - both are lookup
// tables) on first build. Both files are inputs to
// the asset-merge step, so hooking onto `preBuild` guarantees they exist before
// packaging. Downstream apps that want a smaller binary can subset the font in
// their own build (a pipeline template will live under Tools/).
//
// Source: github.com/google/material-design-icons (Apache-2.0).
val materialSymbolsVariant = "MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D"
val materialSymbolsBaseUrl =
    "https://raw.githubusercontent.com/google/material-design-icons/master/variablefont"

val fetchMaterialSymbols by tasks.registering {
    group = "build setup"
    description = "Download the Material Symbols (Rounded) variable font + codepoints into assets/ (~15 MB, gitignored)."

    val fontsDir = layout.projectDirectory.dir("src/main/assets/fonts")
    val symbolsDir = layout.projectDirectory.dir("src/main/assets/symbols")
    val fontFile = fontsDir.file("MaterialSymbolsRounded.ttf").asFile
    val codepointsFile = symbolsDir.file("MaterialSymbolsRounded.codepoints").asFile

    outputs.files(fontFile, codepointsFile)
    // Re-run only when a file is missing/truncated; never re-download otherwise.
    outputs.upToDateWhen { fontFile.length() > 1_000_000L && codepointsFile.length() > 0L }

    doLast {
        fontsDir.asFile.mkdirs()
        symbolsDir.asFile.mkdirs()

        fun download(url: String, dest: File, minBytes: Long) {
            if (dest.length() >= minBytes) return
            logger.lifecycle("fetchMaterialSymbols: downloading ${dest.name} ...")
            uri(url).toURL().openStream().use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            if (dest.length() < minBytes) {
                dest.delete()
                throw GradleException(
                    "fetchMaterialSymbols: ${dest.name} download looks truncated " +
                        "(< $minBytes bytes). Check network access to GitHub and retry."
                )
            }
        }

        download("$materialSymbolsBaseUrl/$materialSymbolsVariant.codepoints", codepointsFile, 10_000L)
        download("$materialSymbolsBaseUrl/$materialSymbolsVariant.ttf", fontFile, 1_000_000L)
    }
}

tasks.named("preBuild") {
    dependsOn(fetchMaterialSymbols)
}
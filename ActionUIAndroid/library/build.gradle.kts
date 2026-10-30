plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.abracode.actionui"
    compileSdk = 36

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
// src/main/assets/fonts/ on first build, and again when the committed table or
// commit below changes. The font is an input to the asset-merge step, so hooking
// onto `preBuild` guarantees it exists before packaging. Downstream apps that
// want a smaller binary can subset the font in their own build (a pipeline
// template will live under Tools/).
//
// The name->codepoint table, src/main/assets/symbols/MaterialSymbolsRounded.codepoints
// (next to the SF->Material map, which was made from it), IS committed, and
// material-symbols-font.commit names the upstream commit it came from. The task
// takes the latest upstream font when the latest table keeps every committed
// line (names may only be added, so no codepoint the map uses moves), else the
// font of the accepted commit, with a warning. It never edits the committed
// files: Tools/material_symbols/fetch-material-symbols-font.sh applies the same
// rule and records compatible additions, or with --accept a reviewed change.
//
// Source: github.com/google/material-design-icons (Apache-2.0).
val materialSymbolsVariant = "variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D"
val materialSymbolsRaw = "https://raw.githubusercontent.com/google/material-design-icons"
val materialSymbolsLatestApi = "https://api.github.com/repos/google/material-design-icons/commits/master"

val fetchMaterialSymbols by tasks.registering {
    group = "build setup"
    description = "Download the Material Symbols (Rounded) variable font into assets/ (~15 MB, gitignored): " +
        "the latest when compatible with the committed codepoints table, else the accepted commit."

    val fontsDir = layout.projectDirectory.dir("src/main/assets/fonts")
    val fontFile = fontsDir.file("MaterialSymbolsRounded.ttf").asFile
    val codepointsFile = layout.projectDirectory.file("src/main/assets/symbols/MaterialSymbolsRounded.codepoints").asFile
    val acceptedFile = layout.projectDirectory.file("material-symbols-font.commit").asFile

    inputs.files(codepointsFile, acceptedFile)
    outputs.file(fontFile)
    // Re-run only when the font is missing/truncated or an input changed; never re-download otherwise.
    outputs.upToDateWhen { fontFile.length() > 1_000_000L }

    doLast {
        fun tableLines(text: String): Set<String> =
            text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toSet()

        // A connection that does not open in 30 s or stalls for a minute fails instead of hanging the build.
        fun open(url: String, accept: String? = null): java.io.InputStream {
            val connection = uri(url).toURL().openConnection()
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            if (accept != null) {
                connection.setRequestProperty("Accept", accept)
            }
            return connection.getInputStream()
        }

        fun readText(url: String, accept: String? = null): String =
            open(url, accept).use { it.readBytes().toString(Charsets.UTF_8) }

        val accepted = acceptedFile.readText().trim()
        val commitPattern = Regex("[0-9a-f]{40}")
        if (!commitPattern.matches(accepted)) {
            throw GradleException("fetchMaterialSymbols: ${acceptedFile.name} does not hold a commit hash.")
        }
        val committed = tableLines(codepointsFile.readText())

        var commit = accepted
        try {
            val latest = readText(materialSymbolsLatestApi, "application/vnd.github.sha").trim()
            if (!commitPattern.matches(latest)) {
                logger.warn("fetchMaterialSymbols: the latest-release lookup did not return a commit hash; using the accepted commit $accepted.")
            } else if (latest != accepted) {
                val latestTable = tableLines(readText("$materialSymbolsRaw/$latest/$materialSymbolsVariant.codepoints"))
                val changed = (committed - latestTable).sorted()
                if (changed.isEmpty()) {
                    commit = latest
                } else {
                    logger.warn(
                        "fetchMaterialSymbols: the latest release ($latest) changes ${changed.size} names of the " +
                            "committed table (${changed.joinToString()}); using the accepted commit $accepted. " +
                            "Review with Tools/material_symbols/fetch-material-symbols-font.sh."
                    )
                    val acceptedTable = tableLines(readText("$materialSymbolsRaw/$accepted/$materialSymbolsVariant.codepoints"))
                    if (acceptedTable != committed) {
                        throw GradleException(
                            "fetchMaterialSymbols: the table of the accepted commit $accepted differs from " +
                                "${codepointsFile.name}; fix ${acceptedFile.name}."
                        )
                    }
                }
            }
        } catch (e: java.io.IOException) {
            logger.warn("fetchMaterialSymbols: cannot check the latest release (${e.message}); using the accepted commit $accepted.")
        }

        fontsDir.asFile.mkdirs()
        val partial = File(fontFile.path + ".partial")
        logger.lifecycle("fetchMaterialSymbols: downloading the font of $commit ...")
        try {
            open("$materialSymbolsRaw/$commit/$materialSymbolsVariant.ttf").use { input ->
                partial.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (e: java.io.IOException) {
            // A transfer cut midway would leave the partial file in the (packaged) assets folder.
            partial.delete()
            throw GradleException(
                "fetchMaterialSymbols: downloading the font of $commit failed (${e.message}). " +
                    "Check network access to GitHub and retry.",
                e
            )
        }
        if (partial.length() < 1_000_000L) {
            partial.delete()
            throw GradleException(
                "fetchMaterialSymbols: the font download looks truncated (< 1000000 bytes). " +
                    "Check network access to GitHub and retry."
            )
        }
        if (!partial.renameTo(fontFile)) {
            fontFile.delete()
            if (!partial.renameTo(fontFile)) {
                throw GradleException("fetchMaterialSymbols: cannot move the download to $fontFile.")
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(fetchMaterialSymbols)
}
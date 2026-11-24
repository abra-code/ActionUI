import java.io.IOException
import java.io.InputStream
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import javax.inject.Inject

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
        // BuildConfig.DEBUG picks the default log level (Common/ConsoleLogger.kt).
        buildConfig = true
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
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    // A library's instrumented tests run in the test APK itself, so the test activity
    // goes there and not into the debug build of every app that uses the library.
    androidTestImplementation(libs.androidx.compose.ui.test.manifest)
}

// -- Symbol fonts -------------------------------------------------------------------
// SF Symbols and Image `materialName` draw from two fonts that the build makes and packages as
// generated assets (nothing is committed; see Helpers/MaterialSymbolFont.kt):
//   fonts/MaterialSymbols.ttf  every Material Symbols Rounded glyph, variable on weight and fill,
//                              with grade and optical size pinned (about 4.3 MB instead of 15 MB);
//   fonts/FluentSymbols.ttf    the Fluent System Icons glyphs of Tools/fluent_symbols/sf_to_fluent.map,
//                              for the SF names Material has no glyph for (about 0.1 MB);
// plus that map, unchanged, and the two icon sets' licenses.
//
// fetchSymbolFontSources downloads the upstream fonts into Tools/material_symbols/font and
// Tools/fluent_symbols/font (gitignored, shared with the Linux build's scripts), only when what is
// there does not fit:
//   Material: src/main/assets/symbols/MaterialSymbolsRounded.codepoints (committed, what
//     sf_to_material.map was made from) and material-symbols-font.commit (the upstream commit it came
//     from). A font whose table keeps every committed line is kept. Otherwise the latest release is
//     taken when its table keeps every committed line (names may only be added, so no code point the
//     map uses moves), else the accepted commit, with a warning. Committed files are never edited:
//     Tools/material_symbols/fetch-material-symbols-font.sh records compatible additions, or with
//     --accept a reviewed change.
//   Fluent: the commit in Tools/fluent_symbols/fluent-icons-font.commit, the one the map was made for.
// generateSymbolFonts then runs Tools/material_symbols/make_android_symbol_fonts.py with fontTools,
// installed at a pinned version into a private Python environment under the build's .gradle folder.
// A first build therefore needs Python 3 and network access to GitHub and PyPI; later builds need
// neither until a map, a commit file or the fontTools version changes.
//
// Sources: github.com/google/material-design-icons (Apache-2.0),
// github.com/microsoft/fluentui-system-icons (MIT).

val symbolToolsDir = layout.projectDirectory.dir("../../Tools")
val pinnedFontToolsVersion = "4.62.1"

/** Downloads the Material and Fluent fonts the symbol fonts are made from, when they are missing or do not fit. */
abstract class FetchSymbolFontSources : DefaultTask() {
    @get:Internal abstract val materialFolder: DirectoryProperty
    @get:Internal abstract val materialAcceptedFile: RegularFileProperty
    @get:Internal abstract val materialTableFile: RegularFileProperty
    @get:Internal abstract val fluentFolder: DirectoryProperty
    @get:Internal abstract val fluentAcceptedFile: RegularFileProperty
    @get:Internal abstract val oldFontFile: RegularFileProperty

    private val commitPattern = Regex("[0-9a-f]{40}")
    private val materialRaw = "https://raw.githubusercontent.com/google/material-design-icons"
    private val materialLatestApi = "https://api.github.com/repos/google/material-design-icons/commits/master"
    private val materialVariant = "variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D"
    private val fluentRaw = "https://raw.githubusercontent.com/microsoft/fluentui-system-icons"

    // A connection that does not open in 30 s or stalls for a minute fails instead of hanging the build.
    private fun open(url: String, accept: String? = null): InputStream {
        val connection = URI(url).toURL().openConnection()
        connection.connectTimeout = 30_000
        connection.readTimeout = 60_000
        if (accept != null) {
            connection.setRequestProperty("Accept", accept)
        }
        return connection.getInputStream()
    }

    private fun readText(url: String, accept: String? = null): String =
        open(url, accept).use { it.readBytes().toString(Charsets.UTF_8) }

    private fun tableLines(text: String): Set<String> =
        text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toSet()

    private fun readCommit(file: File): String? =
        if (file.isFile) file.readText().trim().takeIf { commitPattern.matches(it) } else null

    /**
     * Puts the files of [commit] into [folder]: each URL of [downloads] into the file it names, and
     * [texts]; COMMIT goes first out and last in, so a folder with COMMIT always holds that commit's files.
     */
    private fun install(
        folder: File,
        commit: String,
        downloads: Map<String, String>,
        texts: Map<String, String>,
        minimumFontBytes: Pair<String, Long>,
    ) {
        val work = File(folder, ".download")
        work.deleteRecursively()
        if (!work.mkdirs()) {
            throw GradleException("$name: cannot make $work.")
        }
        try {
            for ((fileName, url) in downloads) {
                logger.lifecycle("$name: downloading $url")
                open(url).use { input -> File(work, fileName).outputStream().use { input.copyTo(it) } }
            }
        } catch (e: IOException) {
            work.deleteRecursively()
            throw GradleException(
                "$name: a download failed (${e.message}). Check network access to GitHub and retry.", e
            )
        }
        val (fontName, minimum) = minimumFontBytes
        if (File(work, fontName).length() < minimum) {
            work.deleteRecursively()
            throw GradleException("$name: the download of $fontName looks truncated. Check network access to GitHub and retry.")
        }
        for ((fileName, text) in texts) {
            File(work, fileName).writeText(text)
        }
        val commitFile = File(folder, "COMMIT")
        if (commitFile.exists() && !commitFile.delete()) {
            throw GradleException("$name: cannot replace $commitFile.")
        }
        for (file in work.listFiles().orEmpty()) {
            Files.move(
                file.toPath(), File(folder, file.name).toPath(), StandardCopyOption.REPLACE_EXISTING
            )
        }
        work.deleteRecursively()
        commitFile.writeText("$commit\n")
    }

    private fun fetchMaterial() {
        val folder = materialFolder.get().asFile
        val acceptedFile = materialAcceptedFile.get().asFile
        val accepted = readCommit(acceptedFile)
            ?: throw GradleException("$name: ${acceptedFile.name} does not hold a commit hash.")
        val committed = tableLines(materialTableFile.get().asFile.readText())
        val fontFile = File(folder, "MaterialSymbolsRounded.ttf")
        val tableFile = File(folder, "MaterialSymbolsRounded.codepoints")
        if (readCommit(File(folder, "COMMIT")) != null && fontFile.length() > 1_000_000L &&
            File(folder, "LICENSE").isFile && tableFile.isFile &&
            (committed - tableLines(tableFile.readText())).isEmpty()
        ) {
            return
        }

        var commit = accepted
        var table: String? = null
        try {
            val latest = readText(materialLatestApi, "application/vnd.github.sha").trim()
            if (!commitPattern.matches(latest)) {
                logger.warn("$name: the latest-release lookup did not return a commit hash; using the accepted commit $accepted.")
            } else if (latest != accepted) {
                val latestTable = readText("$materialRaw/$latest/$materialVariant.codepoints")
                val changed = (committed - tableLines(latestTable)).sorted()
                if (changed.isEmpty()) {
                    commit = latest
                    table = latestTable
                } else {
                    logger.warn(
                        "$name: the latest Material Symbols release ($latest) changes ${changed.size} names of the " +
                            "committed table (${changed.joinToString()}); using the accepted commit $accepted. " +
                            "Review with Tools/material_symbols/fetch-material-symbols-font.sh."
                    )
                }
            }
        } catch (e: IOException) {
            logger.warn("$name: cannot check the latest Material Symbols release (${e.message}); using the accepted commit $accepted.")
        }
        if (table == null) {
            table = try {
                readText("$materialRaw/$accepted/$materialVariant.codepoints")
            } catch (e: IOException) {
                throw GradleException(
                    "$name: downloading the Material Symbols table of $accepted failed (${e.message}). " +
                        "Check network access to GitHub and retry.", e
                )
            }
            if ((committed - tableLines(table)).isNotEmpty()) {
                throw GradleException(
                    "$name: the table of the accepted commit $accepted lacks lines of " +
                        "${materialTableFile.get().asFile.name}; fix ${acceptedFile.name}."
                )
            }
        }
        install(
            folder, commit,
            downloads = mapOf(
                fontFile.name to "$materialRaw/$commit/$materialVariant.ttf",
                "LICENSE" to "$materialRaw/$commit/LICENSE",
            ),
            texts = mapOf(tableFile.name to table),
            minimumFontBytes = fontFile.name to 1_000_000L,
        )
    }

    private fun fetchFluent() {
        val folder = fluentFolder.get().asFile
        val acceptedFile = fluentAcceptedFile.get().asFile
        val commit = readCommit(acceptedFile)
            ?: throw GradleException("$name: ${acceptedFile.name} does not hold a commit hash.")
        val fontName = "FluentSystemIcons-Resizable.ttf"
        if (readCommit(File(folder, "COMMIT")) == commit && File(folder, fontName).isFile && File(folder, "LICENSE").isFile) {
            return
        }
        install(
            folder, commit,
            downloads = mapOf(
                fontName to "$fluentRaw/$commit/fonts/$fontName",
                "LICENSE" to "$fluentRaw/$commit/LICENSE",
            ),
            texts = emptyMap(),
            minimumFontBytes = fontName to 100_000L,
        )
    }

    @TaskAction
    fun fetch() {
        fetchMaterial()
        fetchFluent()
        // The whole font that builds before the generated fonts downloaded into src/: anything there ships.
        val oldFont = oldFontFile.get().asFile
        if (oldFont.exists()) {
            logger.warn(
                "$name: $oldFont is the old downloaded font, no longer used; delete it, " +
                    "or it still ships in every app (15 MB)."
            )
        }
    }
}

/** Makes the symbol fonts, the Fluent map and the licenses into [outputDir], a generated assets folder. */
abstract class GenerateSymbolFonts : DefaultTask() {
    @get:InputFiles @get:PathSensitive(PathSensitivity.RELATIVE) abstract val sources: ConfigurableFileCollection
    @get:InputFile @get:PathSensitive(PathSensitivity.NONE) abstract val generator: RegularFileProperty
    @get:Input abstract val fontToolsVersion: Property<String>
    @get:Internal abstract val pythonFolder: DirectoryProperty
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val execOperations: ExecOperations
    @get:Inject abstract val fileOperations: FileSystemOperations

    private fun run(vararg command: Any): Boolean = try {
        execOperations.exec { commandLine(*command) }.exitValue == 0
    } catch (e: Exception) {
        logger.info("$name: ${command.joinToString(" ")} failed: ${e.message}")
        false
    }

    /** The private environment's Python with the pinned fontTools, made on first use. */
    private fun python(): File {
        val folder = pythonFolder.get().asFile
        val windows = System.getProperty("os.name").startsWith("Windows")
        val python = if (windows) File(folder, "Scripts/python.exe") else File(folder, "bin/python")
        val stamp = File(folder, "fonttools-version")
        val version = fontToolsVersion.get()
        if (python.isFile && stamp.isFile && stamp.readText().trim() == version) {
            return python
        }
        fileOperations.delete { delete(folder) }
        val base = listOf("python3", "python").firstOrNull { run(it, "--version") }
            ?: throw GradleException(
                "$name: building the symbol fonts needs Python 3 (python3 or python on the PATH)."
            )
        if (!run(base, "-m", "venv", folder.path)) {
            throw GradleException("$name: '$base -m venv $folder' failed; the symbol fonts need a Python 3 with venv.")
        }
        if (!run(python.path, "-m", "pip", "install", "--isolated", "--disable-pip-version-check", "--quiet", "fonttools==$version")) {
            fileOperations.delete { delete(folder) }
            throw GradleException(
                "$name: installing fontTools $version into $folder failed. Check network access to PyPI and retry."
            )
        }
        stamp.writeText("$version\n")
        return python
    }

    @TaskAction
    fun generate() {
        val python = python()
        val out = outputDir.get().asFile
        fileOperations.delete { delete(out) }
        // -I: only the private environment's packages, whatever PYTHONPATH or user site packages hold.
        if (!run(python.path, "-I", generator.get().asFile.path, out.path)) {
            throw GradleException("$name: make_android_symbol_fonts.py failed; its message is above.")
        }
    }
}

val fetchSymbolFontSources by tasks.registering(FetchSymbolFontSources::class) {
    group = "build setup"
    description = "Downloads the Material Symbols and Fluent System Icons fonts the symbol fonts are made from."
    materialFolder.set(symbolToolsDir.dir("material_symbols/font"))
    materialAcceptedFile.set(layout.projectDirectory.file("material-symbols-font.commit"))
    materialTableFile.set(layout.projectDirectory.file("src/main/assets/symbols/MaterialSymbolsRounded.codepoints"))
    fluentFolder.set(symbolToolsDir.dir("fluent_symbols/font"))
    fluentAcceptedFile.set(symbolToolsDir.file("fluent_symbols/fluent-icons-font.commit"))
    oldFontFile.set(layout.projectDirectory.file("src/main/assets/fonts/MaterialSymbolsRounded.ttf"))
}

val generateSymbolFonts by tasks.registering(GenerateSymbolFonts::class) {
    group = "build setup"
    description = "Makes the Material and Fluent symbol fonts the library draws SF Symbols and materialName with."
    dependsOn(fetchSymbolFontSources)
    sources.from(
        symbolToolsDir.file("material_symbols/font/MaterialSymbolsRounded.ttf"),
        symbolToolsDir.file("material_symbols/font/LICENSE"),
        symbolToolsDir.file("material_symbols/font/COMMIT"),
        symbolToolsDir.file("fluent_symbols/font/FluentSystemIcons-Resizable.ttf"),
        symbolToolsDir.file("fluent_symbols/font/LICENSE"),
        symbolToolsDir.file("fluent_symbols/font/COMMIT"),
        symbolToolsDir.file("fluent_symbols/sf_to_fluent.map"),
        symbolToolsDir.file("fluent_symbols/fluent-icons-font.commit"),
    )
    generator.set(symbolToolsDir.file("material_symbols/make_android_symbol_fonts.py"))
    fontToolsVersion.set(pinnedFontToolsVersion)
    pythonFolder.set(rootProject.layout.projectDirectory.dir(".gradle/symbol-fonts-python"))
    outputDir.set(layout.buildDirectory.dir("generated/symbolFonts"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(generateSymbolFonts, GenerateSymbolFonts::outputDir)
    }
}

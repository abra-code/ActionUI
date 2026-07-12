pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ActionUIAndroid"

include(":demoApp")
include(":library")
include(":map-osm")
include(":map-google")

// Add-ons are OPTIONAL, mirroring the Apple side where the core demo app links no add-ons and a separate
// ActionUIAddOnTestApp exercises them. The CachedImage add-on depends on the AsyncImageCache library, consumed
// as a composite build (its `com.abracode:asyncimagecache` module is substituted for the binary dependency).
// AsyncImageCache lives beside the ActionUI repo (this build is nested one level deeper as
// ActionUI/ActionUIAndroid), so it is two directories up. Include the composite build and the add-on modules
// ONLY when that sibling checkout is present, so a standalone ActionUIAndroid checkout still configures and
// builds the core library + demoApp with no dependency on AsyncImageCache.
val asyncImageCacheBuild = rootDir.resolve("../../AsyncImageCache/android")
if (asyncImageCacheBuild.exists()) {
    includeBuild(asyncImageCacheBuild)
    include(":addon-cachedimage")
    include(":addon-testapp")
} else {
    println("[ActionUIAndroid] AsyncImageCache not found at $asyncImageCacheBuild; " +
        "skipping :addon-cachedimage and :addon-testapp (core build unaffected).")
}

// The RichText add-on wraps the RichText Compose renderer, consumed via composite build (its
// `com.abracode:richtext` module is substituted for the binary dependency). RichText itself depends on
// AsyncImageCache (inline images), so it needs the AsyncImageCache composite build above too - hence the guard
// requires BOTH sibling checkouts. RichText lives beside ActionUI (this build is nested one level deeper as
// ActionUI/ActionUIAndroid), so it is two directories up. Include ONLY when present, so a standalone checkout
// still configures the core library + demoApp.
val richTextBuild = rootDir.resolve("../../RichText/android")
if (richTextBuild.exists() && asyncImageCacheBuild.exists()) {
    // Name it explicitly: its directory is also "android" (like AsyncImageCache/android), which would collide on
    // the default dir-derived build path ":android". The name is just a build identifier; the dependency
    // substitution is by the com.abracode:richtext coordinate, so naming does not affect it. RichText's own
    // settings include AsyncImageCache/android too, but that is the same directory as the include above, so
    // Gradle coalesces them into one build.
    includeBuild(richTextBuild) { name = "richtext" }
    include(":addon-richtext")
} else {
    println("[ActionUIAndroid] RichText not found at $richTextBuild (or AsyncImageCache missing); " +
        "skipping :addon-richtext (core build unaffected).")
}

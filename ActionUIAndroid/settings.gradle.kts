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

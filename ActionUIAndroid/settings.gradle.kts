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

// AsyncImageCache is consumed as a composite build: its `com.abracode:asyncimagecache` module is substituted
// for the binary dependency the :addon-cachedimage module declares. AsyncImageCache lives beside the ActionUI
// repo (this build is nested one level deeper as ActionUI/ActionUIAndroid), so it is two directories up.
includeBuild("../../AsyncImageCache/android")

include(":demoApp")
include(":library")
include(":map-osm")
include(":map-google")
include(":addon-cachedimage")

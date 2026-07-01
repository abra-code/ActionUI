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

rootProject.name = "TipBillSplitterAndroid"
// One app module per example, named after the example (not the generic ":app",
// which would collide conceptually with ActionUIAndroid's own ":app" demo module).
include(":tipbillsplitter")

// Consume the ActionUI Android library from the sibling repo dir as a Gradle
// composite build. The :tipbillsplitter module requests
// "com.abracode.actionui:library"; this substitution maps that coordinate to the
// :library project inside ActionUIAndroid, which is built from source. No
// publishing/Maven needed.
includeBuild("../../../ActionUIAndroid") {
    dependencySubstitution {
        substitute(module("com.abracode.actionui:library")).using(project(":library"))
    }
}

// Top-level build file. Declares the Android plugin once so every module uses
// the same AGP version defined in gradle/libs.versions.toml.
buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        // AGP's runtime Kotlin plugin uses deprecated Gradle configuration APIs.
        classpath(libs.kotlin.gradle.plugin)
    }
}

plugins {
    base
    alias(libs.plugins.android.application) apply false
}

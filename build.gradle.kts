// Top-level build file. Declares the Android plugin once so every module uses
// the same AGP version defined in gradle/libs.versions.toml.
plugins {
    base
    alias(libs.plugins.android.application) apply false
}

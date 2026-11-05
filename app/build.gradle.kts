plugins {
    alias(libs.plugins.android.application)
}

// Versions live in gradle.properties (which env.sh also reads) so the shell
// scripts and Gradle can never disagree about SDK/NDK/CMake versions. Reading
// only project properties (not environment variables) also keeps long-lived
// Gradle daemons from using a stale environment.
fun configInt(property: String, fallback: Int): Int =
    providers.gradleProperty(property)
        .map { it.toInt() }
        .getOrElse(fallback)

fun configString(property: String, fallback: String): String =
    providers.gradleProperty(property)
        .getOrElse(fallback)

val sdkCompile: Int = configInt("android.compileSdk", 34)
val sdkTarget: Int = configInt("android.targetSdk", sdkCompile)
val sdkMin: Int = configInt("android.minSdk", 24)
val toolBuildTools: String = configString("android.buildToolsVersion", "34.0.0")
val toolNdk: String = configString("android.ndkVersion", "27.0.12077973")
val toolCmake: String = configString("android.cmakeVersion", "3.22.1")
val abis: List<String> = configString("android.abis", "arm64-v8a,x86_64")
    .split(Regex("[,\\s]+"))
    .filter { it.isNotEmpty() }
require(abis.isNotEmpty()) { "android.abis in gradle.properties must not be empty" }
val appId: String = configString("android.applicationId", "com.example.nativeapp")
val appVersionCode: Int = configInt("android.versionCode", 1)
val appVersionName: String = configString("android.versionName", "1.0")

android {
    namespace = appId
    compileSdk = sdkCompile
    buildToolsVersion = toolBuildTools
    ndkVersion = toolNdk

    defaultConfig {
        applicationId = appId
        minSdk = sdkMin
        targetSdk = sdkTarget
        versionCode = appVersionCode
        versionName = appVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += abis
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Keep the fallback debug signing so `assembleRelease` is usable
            // locally without extra setup. Replace for store releases.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = toolCmake
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
}

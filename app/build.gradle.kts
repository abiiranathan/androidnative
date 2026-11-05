import org.gradle.api.attributes.Attribute
import org.gradle.api.file.FileCollection
import org.gradle.plugins.ide.eclipse.model.Classpath
import org.gradle.plugins.ide.eclipse.model.Library
import org.gradle.plugins.ide.eclipse.model.SourceFolder

plugins {
    alias(libs.plugins.android.application)
    eclipse
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
val androidSdkDirectory = androidComponents.sdkComponents.sdkDirectory

val toolBuildTools: String = configString("android.buildToolsVersion", "36.0.0")
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

    lint {
        // abiFilters is built from gradle.properties, which Lint cannot
        // evaluate; x86_64 is included, so this is a false positive.
        disable += "ChromeOsAbiSupport"
    }
}

// Configure the Eclipse model so VS Code's Java extension (Eclipse JDT LS)
// recognizes Java/Kotlin source files and the Android platform classes.
eclipse {
    classpath {
        file.whenMerged {
            val cp = this as Classpath

            // Tell JDT LS where the project source roots are
            cp.entries.add(SourceFolder("src/main/java", null))
            cp.entries.add(SourceFolder("src/test/java", null))
            cp.entries.add(SourceFolder("src/androidTest/java", null))

            // Add android.jar so android.* imports resolve
            val androidJar = androidSdkDirectory.get()
                .file("platforms/android-$sdkCompile/android.jar")
                .asFile
            if (androidJar.isFile) {
                cp.entries.add(Library(fileReference(androidJar)))
            }
        }
    }
}

// Resolve a configuration to the JARs that JDT LS can consume. AGP exposes
// Android dependencies as `android-classes-jar` artifacts, so attaching the
// raw configuration would hand the editor AARs it cannot read.
fun androidCompileJars(configurationName: String): FileCollection =
    configurations.findByName(configurationName)
        ?.incoming
        ?.artifactView {
            attributes {
                attribute(
                    Attribute.of("artifactType", String::class.java),
                    "android-classes-jar"
                )
            }
        }?.files
        ?: files()

// Attach both main and test compile dependencies once AGP has created the
// variant configurations.
afterEvaluate {
    val mainJars = androidCompileJars("debugCompileClasspath")
    val androidTestJars = androidCompileJars("debugAndroidTestCompileClasspath")

    eclipse.classpath.file.whenMerged {
        val cp = this as Classpath
        val seen = cp.entries
            .filterIsInstance<Library>()
            .mapTo(mutableSetOf()) { it.path }

        files(mainJars, androidTestJars).forEach { jar ->
            if (seen.add(jar.absolutePath)) {
                cp.entries.add(Library(fileReference(jar)))
            }
        }
    }
}

dependencies {
    testImplementation(libs.junit)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
}

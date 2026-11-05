# Customizing this project

This is a file-by-file guide for changing the template into your own app. It
assumes you are new to Android: each section says **what you want to do**, then
**which files to edit** and **what to run afterwards**.

You do not need to read it top to bottom. Change one thing at a time and run the
checks at the end of that section.

> Already set up a machine and built the app? See
> [QUICKSTART.md](QUICKSTART.md) first. This guide starts where that one ends.

## File map

| Goal | Main file(s) |
| --- | --- |
| App name, package, icon | `app/src/main/res/values/strings.xml`, `app/src/main/AndroidManifest.xml`, `app/src/main/res/` |
| SDK / NDK / API levels / ABIs | `gradle.properties` |
| App Gradle configuration | `app/build.gradle.kts` |
| Repositories and dependency resolution | `settings.gradle.kts` |
| Dependency versions | `gradle/libs.versions.toml` |
| UI and app logic | `app/src/main/java/` |
| Native C code and JNI | `app/src/main/cpp/` |
| Permissions and components | `app/src/main/AndroidManifest.xml` |
| Release signing | `app/build.gradle.kts`, local-only `keystore.properties` |
| Store version numbers | `gradle.properties` |
| Tests | `app/src/androidTest/`, `tests/test_core.c` |
| Shell/Make tooling | `Makefile`, `build.sh`, `env.sh`, `scripts/` |

Rule of thumb: edit source and version declarations in Git. Never commit
`local.properties`, `keystore.properties`, keystores, `app/build/`, or `dist/`.

## 1. App identity: name, package, icon

### Preferred: use the rename script

```sh
./scripts/new-project.sh --name "My App" --package com.example.myapp
```

It updates the application ID, Java package directories and declarations, JNI
symbol, native library name, app label, log tag, README title and Gradle project
name. Review the diff before committing:

```sh
git diff
git add -A
git commit -m "Initialize My App"
```

The application ID is permanent once an app is published. Pick it carefully.

### Manual changes, if you need them

| Change | File | What to change |
| --- | --- | --- |
| Display name | `app/src/main/res/values/strings.xml` | `<string name="app_name">...</string>` |
| Application ID / namespace | `gradle.properties` | `android.applicationId=...` |
| Gradle project name | `settings.gradle.kts` | `rootProject.name = "..."` |
| Package declarations | `app/src/main/java/**/*.java` | `package ...;` |
| JNI symbol | `app/src/main/cpp/jni_bridge.c` | `Java_<package>_NativeGreeting_format` |
| Native library name | `app/src/main/cpp/CMakeLists.txt`, `build.sh`, `NativeGreeting.java` | `nativeapp` / `System.loadLibrary(...)` |
| Launcher icon | `app/src/main/res/drawable/ic_launcher.xml` and `AndroidManifest.xml` | `android:icon="@drawable/ic_launcher"` |
| Log tag | `app/src/main/cpp/jni_bridge.c`, `build.sh`, `Makefile` | `LOG_TAG`, `make log` |

If you change the package manually, move the source directories too:

```text
app/src/main/java/<old-package>/       -> app/src/main/java/<new-package>/
app/src/androidTest/java/<old-package>/ -> app/src/androidTest/java/<new-package>/
```

For the launcher icon, the quickest route is to replace
`app/src/main/res/drawable/ic_launcher.xml` with your own vector drawable, or
put PNGs in `app/src/main/res/mipmap-*` and update `android:icon` in
`AndroidManifest.xml`. Use Android Studio's **Image Asset** wizard if you have
Android Studio; this project does not require it.

## 2. SDK, NDK, API levels and ABIs

Almost all version numbers live in **`gradle.properties`**:

```properties
android.compileSdk=34
android.targetSdk=34
android.minSdk=24
android.buildToolsVersion=36.0.0
android.ndkVersion=27.0.12077973
android.cmakeVersion=3.22.1
android.abis=arm64-v8a,x86_64
android.versionCode=1
android.versionName=1.0
```

`env.sh` reads the same file, so `bootstrap.sh`, `build.sh`, CMake and Gradle
stay in sync. Edit these values instead of hard-coding versions elsewhere.

| Setting | Meaning | Typical reason to change |
| --- | --- | --- |
| `compileSdk` | Android API used to compile | Use a newer API / library |
| `targetSdk` | Behaviour contract with Android | Play policy, new platform behaviour |
| `minSdk` | Oldest supported device | Drop old devices, or lower it |
| `buildToolsVersion` | SDK build tools | Newer tools, AGP requirement |
| `ndkVersion` | Native toolchain | Security/bug fixes, new API |
| `cmakeVersion` | Native build system | NDK/CMake compatibility |
| `abis` | Native CPU architectures | Add `armeabi-v7a` or drop emulator support |
| `versionCode` | Integer build number | Increment for every Play upload |
| `versionName` | User-visible version | Release naming |

### Recommended update procedure

1. Edit `gradle.properties`.
2. Install the matching SDK packages:

   ```sh
   ./bootstrap.sh
   ```

3. Verify the toolchain:

   ```sh
   make doctor
   ```

4. Clear stale native outputs:

   ```sh
   make clean
   ```

5. Rebuild and test:

   ```sh
   make test
   make apk
   ```

`compileSdk` and `buildToolsVersion` should move together. If you raise
`compileSdk` beyond what the pinned Android Gradle Plugin supports, update AGP
and Gradle as described in section 7.

### Play Store target API requirement

Google Play raises its required `targetSdk` every year. Since **August 31,
2026**, new apps and app updates must target **Android 16 (API level 36)** or
higher. This template pins `targetSdk=34`, so **bump it before publishing**.

Check the current rule in the
[Play target API guide](https://developer.android.com/google/play/requirements/target-sdk)
or the Play Console before an upload. Raising `targetSdk` changes runtime
behaviour (notifications, background work, edge-to-edge UI, predictive back),
so test on a device rather than only checking that it compiles.

`minSdk` changes affect native code too: the Gradle-free build compiles against
the minimum API level from `gradle.properties`. Test on an emulator at your
minimum API level if you lower it.

### Native ABIs

- `arm64-v8a` is required for modern phones and for Play's 64-bit requirement.
- `x86_64` is useful for emulators.
- Add `armeabi-v7a` only if you really need 32-bit devices; it increases APK
  size and build time.
- Do not remove `arm64-v8a` from a Play build.

## 3. Add a dependency

### First: understand where repositories live

Repositories are configured once in **`settings.gradle.kts`**:

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
```

`FAIL_ON_PROJECT_REPOS` means adding a `repositories { ... }` block inside
`app/build.gradle.kts` will fail. Put repositories in `settings.gradle.kts`.

### Normal Maven Central / Google dependency

1. Add a version and a library to **`gradle/libs.versions.toml`**:

   ```toml
   [versions]
   gson = "2.11.0"

   [libraries]
   gson = { module = "com.google.code.gson:gson", version.ref = "gson" }
   ```

2. Add it to **`app/build.gradle.kts`**:

   ```kotlin
   dependencies {
       implementation(libs.gson)
   }
   ```

3. Sync/build:

   ```sh
   make apk
   ```

Use `implementation` for normal libraries. Use `api` in a library module only
when the dependency is part of your public API; this project is an application,
so `implementation` is usually right.

### Dependency hosted only in a GitHub repository (JitPack)

JitPack builds a public GitHub repository and publishes it as a Maven
coordinate. Prefer a released tag or commit, not a moving branch.

1. Add the repository in **`settings.gradle.kts`**:

   ```kotlin
   dependencyResolutionManagement {
       repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
       repositories {
           google()
           mavenCentral()
           maven { url = uri("https://jitpack.io") }
       }
   }
   ```

2. Add the dependency. If the project is `github.com/owner/repo` and the tag is
   `v1.2.3`, the JitPack coordinate is:

   ```kotlin
   dependencies {
       implementation("com.github.owner:repo:v1.2.3")
   }
   ```

   Or declare it in the version catalog:

   ```toml
   [versions]
   mylibrary = "v1.2.3"

   [libraries]
   mylibrary = { module = "com.github.owner:repo", version.ref = "mylibrary" }
   ```

3. Build and check the dependency tree:

   ```sh
   ./gradlew :app:dependencies --configuration debugRuntimeClasspath
   make apk
   ```

JitPack can only build what the GitHub repository publishes, and the first
request may be slow while JitPack compiles it. Pin a tag or commit. A branch
name such as `main` makes builds non-reproducible.

### GitHub Packages

GitHub Packages requires authentication, even for public packages. Add the
repository in `settings.gradle.kts`:

```kotlin
maven {
    url = uri("https://maven.pkg.github.com/OWNER/REPO")
    credentials {
        username = providers.gradleProperty("gpr.user").orNull
            ?: System.getenv("GITHUB_ACTOR")
        password = providers.gradleProperty("gpr.token").orNull
            ?: System.getenv("GITHUB_TOKEN")
    }
}
```

Put the credentials in **`~/.gradle/gradle.properties`**, not in this repository:

```properties
gpr.user=your-github-username
gpr.token=ghp_...   # token with read:packages
```

The token needs the `read:packages` scope. Never commit it, and do not put it in
`gradle.properties` in the project.

### AAR or JAR attached to a GitHub release

If the project does not publish to a Maven repository:

1. Download the `.aar` or `.jar` from the GitHub release.
2. Put it in `app/libs/` (create the directory if needed).
3. Add to `app/build.gradle.kts`:

   ```kotlin
   dependencies {
       implementation(files("libs/mylibrary-release.aar"))
   }
   ```

This is simple, but you must update the file manually when the library changes.
For a long-lived dependency, prefer a real Maven repository or a versioned
internal repository.

### Native dependency (C/C++)

- Add sources with `add_subdirectory(...)` in
  `app/src/main/cpp/CMakeLists.txt`.
- Or link a prebuilt library with `find_package` / `target_link_libraries`.
- If the dependency ships an AAR with `.so` files, the normal Gradle dependency
  is enough; `externalNativeBuild` does not need to know about it.
- If you add C++ instead of C, add the C++ standard library if needed and update
  the CMake project language.

After adding native code, rebuild with `make clean && make apk` and re-run
`make connected-test`.

## 4. App code, permissions and resources

In the paths below, `<package>` means the package path, for example
`com/example/nativeapp`.

| You want to change | Edit |
| --- | --- |
| Screen/UI | `app/src/main/java/<package>/MainActivity.java` |
| JNI-facing Java API | `app/src/main/java/<package>/NativeGreeting.java` |
| C implementation | `app/src/main/cpp/core.c`, `core.h` |
| JNI bridge | `app/src/main/cpp/jni_bridge.c` |
| Native build/link flags | `app/src/main/cpp/CMakeLists.txt` |
| Text and labels | `app/src/main/res/values/strings.xml` |
| Icon and drawables | `app/src/main/res/drawable/` (and `mipmap-*` if added) |
| Backup rules | `app/src/main/res/xml/data_extraction_rules.xml`, `AndroidManifest.xml` |
| Permissions and activities | `app/src/main/AndroidManifest.xml` |
| On-device tests | `app/src/androidTest/java/<package>/NativeGreetingTest.java` |
| Host C tests | `tests/test_core.c` |

### Adding a permission

Edit `app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

For dangerous permissions (camera, location, notifications, etc.) you must also
request them at runtime from Java and handle denial. Declaring a permission in
the manifest is not enough on modern Android.

Only add permissions you use. A new permission can change your Play data-safety
declarations and may trigger review questions.

### Changing JNI code

Three things must agree:

1. The Java class and package (for example `com.example.myapp.NativeGreeting`).
2. The native function name:
   `Java_com_example_myapp_NativeGreeting_format`.
3. The library loaded by `System.loadLibrary("myapp")`.

If you rename the class, package or library, update all three and run:

```sh
make clean
make test
make apk
make connected-test
```

`./scripts/new-project.sh` handles the package and native-library cases for the
existing `NativeGreeting` facade. If you rename the Java class itself, also
rename the C function and every caller.

## 5. Signing the APK or App Bundle

### Current state

`app/build.gradle.kts` currently signs release builds with the shared Android
**debug** key:

```kotlin
release {
    isMinifyEnabled = false
    signingConfig = signingConfigs.getByName("debug")
}
```

That is convenient for local testing, but it is **not suitable for Play**.
The debug key is shared and has a well-known password. Create your own upload
key before publishing.

### 5.1 Create an upload keystore

Run this once and keep the file outside the repository (for example in
`~/keystores/`):

```sh
mkdir -p ~/keystores
keytool -genkeypair -v \
    -keystore ~/keystores/myapp-upload.jks \
    -alias upload \
    -keyalg RSA \
    -keysize 4096 \
    -validity 10000
```

Use strong passwords and store them in a password manager. Back up:

- the keystore file,
- the alias,
- the store password,
- the key password.

Losing the upload key can block updates until Google resets it. The Android
debug keystore is **not** a backup.

### 5.2 Create `keystore.properties` (local only)

Create **`keystore.properties`** in the project root:

```properties
storeFile=/home/you/keystores/myapp-upload.jks
storePassword=your-store-password
keyAlias=upload
keyPassword=your-key-password
```

This file is already ignored by `.gitignore`, along with `*.jks` and
`*.keystore`. Verify that Git does not see it:

```sh
git status --short
git check-ignore -v keystore.properties
```

Never commit this file, the keystore, or the passwords. Do not put them in a
public CI log either.

### 5.3 Read the keystore in `app/build.gradle.kts`

Add these imports at the very top of `app/build.gradle.kts`:

```kotlin
import java.io.FileInputStream
import java.util.Properties
```

After the `plugins` block, load the properties if the file exists:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("keystore.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
```

Inside the `android { ... }` block, add a release signing config:

```kotlin
signingConfigs {
    if (keystorePropertiesFile.exists()) {
        create("release") {
            storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }
}
```

Then replace the release build type's debug signing line:

```kotlin
buildTypes {
    release {
        isMinifyEnabled = false
        signingConfig = if (keystorePropertiesFile.exists()) {
            signingConfigs.getByName("release")
        } else {
            signingConfigs.getByName("debug")
        }
    }
}
```

The fallback keeps local `make release` working before you create a keystore.
A Play build must use the `release` config, so confirm `keystore.properties`
exists on the machine that builds the upload. For a strict release build, delete
the `else` branch so a missing keystore fails instead of falling back to debug
signing.

### 5.4 Build and verify the signed artifact

```sh
make bundle
# app/build/outputs/bundle/release/app-release.aab

make release
# app/build/outputs/apk/release/app-release.apk
```

Verify the APK certificate:

```sh
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs \
    app/build/outputs/apk/release/app-release.apk
```

For an AAB, Play validates the signature during upload. Locally, you can inspect
it with:

```sh
jarsigner -verify -verbose -certs \
    app/build/outputs/bundle/release/app-release.aab
```

### 5.5 Play App Signing

When you create the app in Play Console, enrol in **Play App Signing**:

- Google holds the **app signing key** used to sign builds delivered to users.
- You sign uploads with your **upload key** (the keystore above).
- If the upload key is lost, you can request a reset through Play Console.

Keep the upload keystore backed up. If you later change machines, copy the
keystore and `keystore.properties` securely rather than generating a new key.

### 5.6 The Gradle-free build

`build.sh` / `make apk-raw` always uses the debug keystore or the `KEYSTORE`
environment variable with the debug alias and password. It is a convenience
fallback, not a Play signing path. Use Gradle and the release signing config
for store builds.

## 6. Preparing for Google Play

### Before uploading

- [ ] `android.applicationId` is final and unique.
- [ ] `android.versionCode` is greater than the last uploaded build.
- [ ] `android.versionName` is the user-visible release name.
- [ ] `android.targetSdk` meets the current Play requirement.
- [ ] Release signing is configured with your upload keystore.
- [ ] `make test`, `make apk` and `make connected-test` pass.
- [ ] The release build installs and runs on a real device.
- [ ] The app does not request permissions it does not use.
- [ ] `android:allowBackup` and backup rules match what you intend to back up.
- [ ] No secrets, keystores, `local.properties` or API keys are in Git.
- [ ] The app has a privacy policy if it collects or shares user data.

### Build the upload artifact

```sh
make clean
make test
make bundle
```

Play uses Android App Bundles (`.aab`) for new apps. The output is:

```text
app/build/outputs/bundle/release/app-release.aab
```

Do not upload `app-debug.apk` or a release APK signed with the debug key.

### Play Console checklist

1. Create a Google Play Developer account and complete identity verification.
2. Create the app: name, default language, app or game, free or paid.
3. Enrol in Play App Signing.
4. Complete **App content**:
   - privacy policy
   - data safety
   - content rating questionnaire
   - ads declaration
   - target audience and content
   - news app declaration if applicable
   - app access instructions if parts require login
5. Add store listing assets:
   - app icon
   - feature graphic
   - phone/tablet screenshots
   - short and full description
6. Upload the AAB to **Internal testing** first.
7. Install from the internal testing link and verify the real signed build.
8. Promote to closed/open testing, then production with a staged rollout.

Keep the version code increasing for every upload, including test uploads. A
version code can never be reused for the same application ID.

### Native 64-bit requirement

Play requires 64-bit native libraries. This project ships `arm64-v8a`. The
`x86_64` library is for emulators and does not replace `arm64-v8a`. If you
change `android.abis`, keep a 64-bit phone ABI in the list.

### App size and permissions

- Check the current Play size limits before adding large assets; use asset
  delivery or Play Asset Delivery for big downloads.
- Sensitive permissions (location, camera, microphone, SMS, background location,
  etc.) have additional policy requirements.
- If you add analytics, ads, crash reporting or login, update the data safety
  form and privacy policy at the same time.

## 7. Updating Gradle, AGP and dependencies

| What | File | Command/notes |
| --- | --- | --- |
| AGP and libraries | `gradle/libs.versions.toml` | Change versions, then `make apk` |
| Gradle itself | `gradle/wrapper/gradle-wrapper.properties` | Prefer `./gradlew wrapper --gradle-version X` |
| SDK / NDK / CMake | `gradle.properties` | Then `./bootstrap.sh` and `make doctor` |
| Wrapper scripts/jar | `gradlew`, `gradle/wrapper/` | Regenerate, do not hand-edit |

AGP, Gradle, the Android SDK and Java have compatibility constraints. Upgrade
them together:

1. Read the AGP release notes for the required Gradle and JDK versions.
2. Update `gradle/libs.versions.toml` and the wrapper.
3. Run `make clean`, `make doctor`, `make test`, `make apk`.
4. Run `make connected-test` on a device.
5. Commit the wrapper and version catalog changes together.

Do not upgrade `compileSdk` and AGP independently without checking their
compatibility. A newer `compileSdk` than the AGP supports usually produces a
warning or a build failure.

## 8. What not to edit or commit

Generated or machine-specific files:

```text
app/build/          Gradle outputs
app/.cxx/           CMake/NDK outputs
build/              host test and raw build outputs
.gradle/            Gradle caches
.idea/              IDE settings
local.properties    local Android SDK path
keystore.properties signing passwords
*.jks, *.keystore   signing keys
dist/               source archives
```

These are in `.gitignore`. If `git status` shows one of them, stop and check
before committing. If you accidentally commit a keystore or token, rotate the
secret; deleting the file in a later commit is not enough because it remains in
history.

## 9. After every change

At minimum:

```sh
make doctor
make test
make apk
```

Before merging or releasing:

```sh
make clean
make test
make test-sanitize
make apk
make connected-test     # with a device attached
make lint
```

Before a Play upload:

```sh
make clean
make test
make bundle
```

## Quick reference

| I want to... | Edit... | Then run... |
| --- | --- | --- |
| Rename the app | `scripts/new-project.sh` | `git diff`, `make test`, `make apk` |
| Change the label | `app/src/main/res/values/strings.xml` | `make apk` |
| Change the icon | `app/src/main/res/drawable/ic_launcher.xml` | `make apk` |
| Change API levels | `gradle.properties` | `./bootstrap.sh`, `make doctor`, `make apk` |
| Add a Maven dependency | `gradle/libs.versions.toml`, `app/build.gradle.kts` | `make apk` |
| Add a GitHub/JitPack dependency | `settings.gradle.kts`, `app/build.gradle.kts` | `./gradlew :app:dependencies`, `make apk` |
| Add a permission | `app/src/main/AndroidManifest.xml` (+ Java runtime request) | `make apk` |
| Change UI | `app/src/main/java/.../MainActivity.java` | `make apk`, `make run` |
| Change native code | `app/src/main/cpp/` | `make clean`, `make test`, `make apk` |
| Set up release signing | `app/build.gradle.kts`, `keystore.properties` | `make bundle` |
| Bump the store version | `gradle.properties` | `make bundle` |
| Publish to Play | see section 6 | `make bundle`, upload AAB |

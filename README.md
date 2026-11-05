# androidnative

A small, self-contained Android test project built without Android Studio:
Gradle (Kotlin DSL) + the NDK/CMake for the native library, plus a Gradle-free
fallback build that needs only the Android SDK command-line tools.

The app is intentionally tiny: it loads `libnativeapp.so`, calls a C function
through JNI, and displays the result. It is a good starting point for testing a
toolchain and for pushing an APK to a physical device.

## Quick start

```sh
./bootstrap.sh          # install SDK/NDK/CMake and generate ./gradlew
source env.sh           # optional for interactive shells; scripts do this themselves
make doctor             # verify JDK, SDK, NDK, CMake and adb
make test               # host-side C tests (no device required)
make apk                # debug APK
adb devices             # confirm the phone is authorised
make install            # install on the connected device
make run                # install + launch
```

The debug APK is at
`app/build/outputs/apk/debug/app-debug.apk`.

If `./gradlew` already exists, a system Gradle is **not** required. Gradle
downloads the pinned wrapper distribution on the first build.

## Layout

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | Installs command-line tools, platform, build-tools, NDK, CMake, platform-tools. Idempotent. |
| `env.sh` | Shared shell configuration. Reads versions from `gradle.properties`, puts SDK tools on `PATH`, detects a JDK. Safe to source from your profile. |
| `gradle.properties` | **Single source of truth** for SDK/NDK/CMake versions, ABIs, app identity, and Gradle settings. |
| `settings.gradle.kts`, `build.gradle.kts` | Gradle project and plugin configuration. |
| `gradle/libs.versions.toml` | Version catalog (AGP, test libraries). Add dependencies here. |
| `gradlew`, `gradle/wrapper/` | Pinned Gradle 8.10.2 wrapper. Commit these. |
| `app/build.gradle.kts` | App module: namespace, SDK levels, ABIs, CMake hookup, test dependencies. |
| `app/src/main/java/` | `MainActivity` and the `NativeGreeting` JNI facade. |
| `app/src/main/cpp/` | `core.[ch]` (portable C, no JNI), `jni_bridge.c`, `CMakeLists.txt`. |
| `app/src/androidTest/` | On-device instrumentation tests (`NativeGreetingTest`). |
| `tests/test_core.c` | Host-side unit tests for `core.c`. |
| `build.sh` | Gradle-free fallback: NDK clang → aapt2 → javac → d8 → zipalign → apksigner. |
| `scripts/` | `env-run`, `doctor`, wrapper generation, device check, `local.properties`. |
| `Makefile` | Developer entry points (see `make help`). |
| `androidnative.tar.gz` | Local original source archive (gitignored); the extracted tree is the maintained project. |

## Make targets

Run `make help` for the full list.

| Target | What it does |
| --- | --- |
| `make bootstrap` | Install missing SDK components and generate `gradlew`. |
| `make doctor` | Diagnostic check; non-zero exit if something is missing. |
| `make test` | Compile and run the portable C core tests on the host. |
| `make test-sanitize` | Same tests with ASan + UBSan. |
| `make apk` | Debug APK via Gradle. |
| `make apk-raw` | Debug APK without Gradle (offline/no-wrapper fallback). |
| `make release` | Release APK, signed with the local debug key. |
| `make install` | Install the debug APK with `adb install -r`. |
| `make install-raw` | Install the Gradle-free APK (builds it if missing). |
| `make run` | Build, install, launch, and wait for the activity. |
| `make run-raw` | Same as `run`, using the Gradle-free build. |
| `make connected-test` | Run instrumentation tests on the connected device. |
| `make log` | `adb logcat -s NativeApp:V AndroidRuntime:E`. |
| `make devices` | List attached devices. |
| `make uninstall` | Remove the app from the device. |
| `make clean` | Remove build outputs. |
| `make distclean` | Also remove `.gradle/`, `local.properties`, IDE files. |
| `make lint` | Android Lint report at `app/build/reports/lint-results-debug.html`. |
| `make check` | Host tests + debug APK. |

## Requirements

- JDK 17+ (Arch: `sudo pacman -S jdk17-openjdk`, Debian/Ubuntu:
  `sudo apt install openjdk-17-jdk`)
- `curl`, `unzip`, `zip`
- A C compiler for host tests (`cc`; usually part of the base system)
- A system Gradle **only** for the one-time wrapper generation
  (Arch: `sudo pacman -S gradle`)
- A device with USB debugging enabled, or an emulator
  (`./bootstrap.sh --emulator --avd`)

`bootstrap.sh` installs everything under `$ANDROID_HOME` (default
`$HOME/Android/Sdk`) and writes a gitignored `local.properties` so Gradle and
IDEs find the same SDK.

## Using a physical device

1. Enable Developer options: tap **Build number** seven times.
2. Enable **USB debugging**.
3. Connect the cable and accept the RSA fingerprint prompt.
4. Check the device:

   ```sh
   adb devices          # must show "device", not "unauthorized"
   make install
   make run
   ```

If more than one device is attached, select one with
`ANDROID_SERIAL=<serial> make run`.

The debug APK contains `arm64-v8a` and `x86_64` native libraries. Most phones
use `arm64-v8a`; an x86_64 emulator uses the other.

## Versions

`gradle.properties` is authoritative:

```properties
android.compileSdk=34
android.targetSdk=34
android.minSdk=24
android.buildToolsVersion=34.0.0
android.ndkVersion=27.0.12077973
android.cmakeVersion=3.22.1
android.abis=arm64-v8a,x86_64
android.applicationId=com.example.nativeapp
android.versionCode=1
android.versionName=1.0
```

`env.sh` reads those values and exports `API_LEVEL`, `TARGET_API`, `MIN_API`,
`BUILD_TOOLS_VERSION`, `NDK_VERSION`, `CMAKE_VERSION`, `ABIS`, `APP_ID` and the
version fields for the shell scripts. Gradle reads the same `gradle.properties`
directly. There is therefore one place to edit, and bootstrap, the raw build and
Gradle stay in sync even when a long-lived Gradle daemon is reused.

To upgrade the SDK/NDK/CMake, edit `gradle.properties` and re-run
`make bootstrap`. To upgrade Gradle itself, run
`./gradlew wrapper --gradle-version <version>`.

## Adding dependencies

Java/Kotlin (including AARs and AndroidX): add an entry to
`gradle/libs.versions.toml`, then reference it in `app/build.gradle.kts`:

```toml
[versions]
gson = "2.11.0"
[libraries]
gson = { module = "com.google.code.gson:gson", version.ref = "gson" }
```

```kotlin
dependencies { implementation(libs.gson) }
```

Native: vendor the source with `add_subdirectory` in
`app/src/main/cpp/CMakeLists.txt`, or link a prebuilt library with
`find_package` / `target_link_libraries`.

## Troubleshooting

- **`adb devices` says `unauthorized`:** unlock the phone and accept the RSA
  prompt. Revoke/authorise again under Developer options if needed.
- **`make install`: no device found:** check the cable, USB mode (file transfer
  often enables adb), and USB debugging.
- **Gradle cannot find the SDK:** run `make local-properties` (or
  `source env.sh`). `local.properties` contains `sdk.dir=/path/to/Sdk`.
- **cmdline-tools download 404s:** set `CMDLINE_TOOLS_REV` to the current
  revision from Google's "Command line tools only" downloads and re-run
  `./bootstrap.sh`.
- **JDK/toolchain errors:** `make doctor`; on Arch select JDK 17 with
  `sudo archlinux-java set java-17-openjdk`.
- **Gradle download/network problems:** `make apk-raw` builds the same APK
  without Gradle, using only the installed SDK tools.
- **16 KB page devices (Android 15+):** both build paths already pass
  `-Wl,-z,max-page-size=16384`; the NDK is r27.
- **Lint reports newer dependency versions:** informational only. This project
  pins AGP 8.7.3 and Gradle 8.10.2 for a known-compatible combination.

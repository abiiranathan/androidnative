# Quick start: from a clean machine to a running app

This guide takes you from a fresh operating-system install to a debug APK
running on a phone or emulator. It assumes no Android Studio and no pre-existing
Android SDK.

If you only want to build the existing checkout, skip to
[Bootstrap the toolchain](#4-bootstrap-the-toolchain).

## What this project is

A minimal Android app with a C library behind JNI:

- Gradle (Kotlin DSL) + Android Gradle Plugin 8.7.3
- NDK r27 + CMake for `lib<package>.so`
- A Gradle-free fallback build (`make apk-raw`) that uses only SDK tools
- Host-side C unit tests (`make test`) and on-device JNI tests
  (`make connected-test`)
- SDK, NDK, CMake and ABI versions defined once in `gradle.properties`

Nothing here requires Android Studio. Android Studio can open the project later
if you want it.

> Ready to make it your own? **[CUSTOMIZING.md](CUSTOMIZING.md)** explains which
> files to edit for app identity, SDK/API versions, dependencies, signing and
> Play Store uploads.

## 1. Prerequisites

You need:

| Requirement | Why |
| --- | --- |
| JDK 17 or newer (`java`, `javac`) | Gradle and the Android build |
| `curl`, `unzip`, `zip`, `keytool` | SDK download, unpacking, APK packaging, signing |
| A C compiler (`cc`) | Host-side unit tests |
| `git` | Version control and `gh repo create` |
| `adb` | Installed by `bootstrap.sh`, used for devices |

A system Gradle is **not** required for normal builds. The wrapper
(`gradlew`) downloads the pinned Gradle version. A system Gradle is only needed
once if a checkout is missing `gradlew` (this repository includes it).

### Arch Linux

```sh
sudo pacman -S --needed jdk17-openjdk curl unzip zip base-devel git
sudo archlinux-java set java-17-openjdk   # if another JDK is default
```

### Debian / Ubuntu

```sh
sudo apt update
sudo apt install -y openjdk-17-jdk curl unzip zip build-essential git
```

### Fedora

```sh
sudo dnf install -y java-17-openjdk-devel curl unzip zip gcc make git
```

### macOS

```sh
xcode-select --install          # provides cc and git
brew install openjdk@17 curl unzip zip

# Homebrew's JDK is keg-only; put it on PATH for this shell:
export JAVA_HOME="$(brew --prefix openjdk@17)"
export PATH="$JAVA_HOME/bin:$PATH"
```

Add the two exports to `~/.zshrc` to make them permanent. `bootstrap.sh` and
`make doctor` warn if the JDK is older than 17.

### Windows

Use WSL2 with a Debian or Ubuntu distribution and follow the Debian steps.
Build and test from WSL. For USB devices, use `adb` from Windows or configure
USB passthrough for WSL; emulators are usually simpler.

### Check the basics

```sh
java -version     # must report 17 or newer
javac -version
cc --version
curl --version
```

## 2. Get the project

### Option A: create a new repository from the GitHub template

The upstream project is
[`abiiranathan/androidnative`](https://github.com/abiiranathan/androidnative)
and is marked as a template. With GitHub CLI:

```sh
gh auth login                     # once per machine
gh repo create my-app \
    --template abiiranathan/androidnative \
    --private --clone
cd my-app
```

You can also press **Use this template** on the GitHub page and clone the new
repository. A private template requires an account with access to the upstream
repository; use the archive option below if you do not have access.

### Option B: use a source archive

From a checkout of the template:

```sh
make dist
# dist/<project>-<version>.tar.gz
# dist/<project>-<version>.tar.gz.sha256
```

Unpack it anywhere:

```sh
tar -xzf dist/<project>-<version>.tar.gz
cd <project>-<version>
```

The archive has no `.git` directory, build outputs, `local.properties`, APKs or
signing material. Initialise a new repository when ready:

```sh
git init
git add -A
git commit -m "Initial commit"
```

### Option C: clone the template and rename it in place

```sh
git clone https://github.com/abiiranathan/androidnative.git my-app
cd my-app
./scripts/new-project.sh --name "My App" --package com.example.myapp
```

## 3. Rename the template

For a new application, set its display name and Java application ID:

```sh
./scripts/new-project.sh --name "My App" --package com.example.myapp
```

The script edits the current checkout in place and changes:

- `android.applicationId` in `gradle.properties` (and its fallbacks)
- the Java package directories and `package` declarations
- the JNI symbol in `app/src/main/cpp/jni_bridge.c`
- the native library name (`lib<last-package-segment>.so`)
- the app label, log tag, README title and Gradle `rootProject.name`

Derived values:

| Value | Example | Source |
| --- | --- | --- |
| Project slug | `my-app` | `--name`, lowercased; override with `--project` |
| Log tag | `MyApp` | alphanumeric characters from `--name` |
| Native library | `libmyapp.so` | last segment of `--package` |

Rules:

- `--package` must contain at least two segments and be a valid Java package.
- By default the script refuses to run when the Git working tree is dirty.
  Commit first, or pass `--force` if you intentionally want to rename on top of
  local edits.
- `.git` is never modified. Review the result before the first commit.

```sh
git diff
git add -A
git commit -m "Initialize My App from the androidnative template"
```

The script prints the exact next commands after a successful rename.

## 4. Bootstrap the toolchain

From the project root:

```sh
./bootstrap.sh
```

This downloads the Android command-line tools into `$ANDROID_HOME` (default
`~/Android/Sdk`), accepts the SDK licences, and installs:

- `platform-tools` (includes `adb`)
- `platforms;android-34`
- `build-tools;34.0.0`
- `ndk;27.0.12077973`
- `cmake;3.22.1`

It is idempotent: re-running only fills gaps. It also creates a gitignored
`local.properties` so Gradle and IDEs use the same SDK.

Optional environment setup:

```sh
source env.sh
```

Scripts and Makefile recipes already source `env.sh` themselves, so this is
only convenient for interactive `adb`, `sdkmanager` and `emulator` commands.
Run it from the project root in a shell that will keep using those tools.

If the SDK lives somewhere else:

```sh
ANDROID_HOME=/opt/android-sdk ./bootstrap.sh
```

### Emulator instead of a phone

```sh
./bootstrap.sh --emulator --avd
```

`--avd` creates (or reuses) an x86_64 AVD named `android-dev-34`. Start it with:

```sh
"$ANDROID_HOME/emulator/emulator" -avd android-dev-34 &
adb wait-for-device
```

On Linux, hardware acceleration needs `/dev/kvm` and membership in the `kvm`
group:

```sh
sudo usermod -aG kvm "$USER"    # log out and back in afterwards
```

## 5. Verify the toolchain

```sh
make doctor
```

`make doctor` prints the SDK path and versions, then checks the JDK, host
tools, platform, build-tools, NDK, CMake, `adb`, the Gradle wrapper and
`local.properties`. It exits non-zero if something needed by the build is
missing.

Verify the host-side C tests before involving Android:

```sh
make test
make test-sanitize     # optional: ASan + UBSan
```

## 6. Build the app

```sh
make apk
```

The debug APK is written to:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Useful variants:

```sh
make apk-raw      # same app without Gradle, using SDK tools only
make release      # release variant, signed with the local debug key
make bundle       # release App Bundle for Play (configure signing first)
make lint         # report: app/build/reports/lint-results-debug.html
make check        # host tests + debug APK
```

`make release` is for local verification. Its signing key is the shared Android
debug keystore; configure a real upload key before publishing to a store. See
[Signing the APK or App Bundle](CUSTOMIZING.md#5-signing-the-apk-or-app-bundle).

The debug APK contains `arm64-v8a` and `x86_64` native libraries. Most phones
use the first; x86_64 emulators use the second.

## 7. Connect a device

1. On the phone, open **Settings → About phone** and tap **Build number** seven
   times to enable Developer options.
2. Open **Settings → System → Developer options** and enable **USB debugging**.
3. Connect the USB cable.
4. Accept the RSA fingerprint prompt on the phone.
5. Verify:

   ```sh
   make devices
   # or: adb devices -l
   ```

   The state must be `device`, not `unauthorized`.

If more than one device is attached, choose one explicitly:

```sh
ANDROID_SERIAL=<serial> make run
```

## 8. Install, run and test on the device

```sh
make install          # adb install -r
make run              # build, install and launch
make log              # stream app + crash logs
make connected-test   # instrumentation tests for the JNI boundary
make uninstall        # remove the app
```

`make run` waits for the activity to start. The app displays a greeting from C,
the device ABI and the API level. If it starts but shows an error, `make log`
shows the native log tag and `AndroidRuntime` exceptions.

## 9. Clean up or start over

```sh
make clean        # build outputs only
make distclean    # also caches, local.properties, IDE files, dist/
```

After `make distclean`, run `./bootstrap.sh` again before building.

## Troubleshooting

**`adb devices` shows `unauthorized`**

Unlock the phone and accept the RSA prompt. If it never appears, revoke USB
debugging authorisations under Developer options, reconnect, and try again.

**`no device found` or `make run` fails immediately**

Check the cable and USB mode (file transfer usually enables adb), confirm USB
debugging is on, and run `make devices`. Emulators count as devices too.

**`java` is the wrong version / Gradle says JDK 17 is required**

Run `make doctor` to see which `javac` and `java` are used. On Arch:

```sh
sudo archlinux-java set java-17-openjdk
```

On macOS, export the Homebrew JDK before running any command:

```sh
export JAVA_HOME="$(brew --prefix openjdk@17)"
export PATH="$JAVA_HOME/bin:$PATH"
```

**Gradle cannot find the Android SDK**

```sh
make local-properties
cat local.properties
```

`local.properties` must contain `sdk.dir=/absolute/path/to/Sdk`. Delete it and
re-run `make local-properties` if the path is stale.

**`./gradlew` is missing or not executable**

The wrapper is committed. If it is absent from an archive or an old checkout:

```sh
make wrapper          # needs a system Gradle once
chmod +x gradlew
```

**Gradle cannot download its distribution**

Use the Gradle-free build, which needs only the SDK:

```sh
make apk-raw
```

**`cmdline-tools` download returns 404**

Google retired the pinned archive. Set the current revision from the
[command-line tools page](https://developer.android.com/studio#command-line-tools-only)
and re-run the bootstrap:

```sh
CMDLINE_TOOLS_REV=<revision> ./bootstrap.sh
```

**Lint reports newer dependency versions**

Those are informational. AGP, Gradle and the test libraries are pinned to a
known-compatible set; upgrade them together in `gradle.properties` and
`gradle/libs.versions.toml`.

**Android 15+ 16 KB page devices**

Both build paths pass `-Wl,-z,max-page-size=16384` and use NDK r27. If you
change the NDK or linker flags, keep that option.

**Build works but the app crashes on launch with `UnsatisfiedLinkError`**

The Java package, JNI symbol and native library name must stay in sync. Re-run
`make apk` after changing any of them, and check the symbol:

```sh
unzip -l app/build/outputs/apk/debug/app-debug.apk | grep 'lib/'
```

The `new-project.sh` script updates all three together.

## Checklist

```text
[ ] JDK 17+, curl, unzip, zip, cc, git installed
[ ] new repository from the template (or archive unpacked)
[ ] scripts/new-project.sh --name ... --package ...
[ ] git commit the rename
[ ] ./bootstrap.sh
[ ] make doctor
[ ] make test
[ ] make apk
[ ] adb devices shows "device"
[ ] make run
[ ] make connected-test
```

#!/usr/bin/env bash
# Installs the Android SDK (command-line only), platform, build-tools, NDK,
# platform-tools and CMake into $ANDROID_HOME. Idempotent: re-running only
# fills gaps. Also generates the Gradle wrapper when a system Gradle exists.
#
# Usage: ./bootstrap.sh [--emulator] [--avd] [--help]
#   --emulator  also install the emulator and an x86_64 system image
#   --avd       like --emulator, and create/update an AVD (implies --emulator)
#
# Environment:
#   CMDLINE_TOOLS_SHA256  expected SHA-256 of the command-line tools zip for
#                         this OS and CMDLINE_TOOLS_REV. When set, a mismatch
#                         aborts the install. When unset, the computed hash is
#                         printed so it can be pinned (e.g. as a CI variable).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$here/env.sh"

die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' -- $2"; }

# Prints the SHA-256 of $1 using whichever tool the host provides (GNU
# coreutils on Linux, shasum on macOS). Returns non-zero when neither exists so
# callers can decide whether the missing tool is fatal.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [--emulator] [--avd] [--help]

  --emulator  also install the emulator and an x86_64 system image
  --avd       like --emulator, and create/update an AVD (implies --emulator)
  --help      show this help

Installs command-line tools, platform-tools, the platform, build-tools, NDK
and CMake into $ANDROID_HOME, then generates the Gradle wrapper if a system
Gradle is available. Safe to re-run: it only fills gaps.

Set CMDLINE_TOOLS_SHA256 to verify the command-line tools download.
EOF
}

want_emulator=0
want_avd=0
for arg in "$@"; do
    case "$arg" in
        --emulator) want_emulator=1 ;;
        --avd)      want_emulator=1; want_avd=1 ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown option '$arg' (try --help)" ;;
    esac
done

need java  "JDK 17+ required (Arch: sudo pacman -S jdk17-openjdk; Debian/Ubuntu: apt install openjdk-17-jdk)"
need javac "JDK 17+ required (Arch: sudo pacman -S jdk17-openjdk; Debian/Ubuntu: apt install openjdk-17-jdk)"
need curl  "install curl"
need unzip "install unzip"
need zip   "install zip (used by the Gradle-free fallback build)"

if [[ "${ANDROID_DEV_JAVA_MAJOR:-0}" -lt 17 || "${ANDROID_DEV_JAVA_RUNTIME_MAJOR:-0}" -lt 17 ]]; then
    die "JDK 17+ required (javac major ${ANDROID_DEV_JAVA_MAJOR:-unknown}, java major ${ANDROID_DEV_JAVA_RUNTIME_MAJOR:-unknown}; check 'java -version')"
fi

mkdir -p "$ANDROID_HOME"

# ---------------------------------------------------------------------------
# 1. Command-line tools. The zip must end up at cmdline-tools/latest/ or
#    sdkmanager cannot locate its own libraries.
# ---------------------------------------------------------------------------
sdkmanager_bin="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$sdkmanager_bin" ]]; then
    url="https://dl.google.com/android/repository/commandlinetools-${CMDLINE_OS}-${CMDLINE_TOOLS_REV}_latest.zip"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    echo ">> downloading command-line tools: $url"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
        -o "$tmp/cmdline-tools.zip" "$url"

    # Integrity check. The hash is compared case-insensitively (tr rather than
    # ${var,,} so this stays portable to the bash 3.2 that macOS ships).
    actual_sha="$(sha256_of "$tmp/cmdline-tools.zip" || true)"
    if [[ -n "${CMDLINE_TOOLS_SHA256:-}" ]]; then
        [[ -n "$actual_sha" ]] || die "CMDLINE_TOOLS_SHA256 is set but neither sha256sum nor shasum is installed"
        expected_sha="$(printf '%s' "$CMDLINE_TOOLS_SHA256" | tr 'A-F' 'a-f')"
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            die "checksum mismatch for $url (expected $expected_sha, got $actual_sha)"
        fi
        echo ">> checksum ok: $actual_sha"
    elif [[ -n "$actual_sha" ]]; then
        echo ">> note: no CMDLINE_TOOLS_SHA256 pinned; downloaded zip has SHA-256 $actual_sha"
        echo "         Compare it with the value on Google's download page, then pin it."
    fi

    unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
    mkdir -p "$ANDROID_HOME/cmdline-tools"

    if [[ -e "$ANDROID_HOME/cmdline-tools/latest" ]]; then
        backup="$ANDROID_HOME/cmdline-tools/latest.bak.$(date +%s)"
        echo ">> moving incomplete cmdline-tools aside: $backup"
        mv "$ANDROID_HOME/cmdline-tools/latest" "$backup"
    fi
    mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$tmp"
    trap - EXIT
fi

# ---------------------------------------------------------------------------
# 2. Licenses. `yes` is fed via process substitution so pipefail does not trip
#    on SIGPIPE when sdkmanager stops reading. A failure here is tolerated on
#    purpose: if the licenses really were not accepted, the --install step
#    below fails with a clear message.
# ---------------------------------------------------------------------------
echo ">> accepting licenses"
"$sdkmanager_bin" --sdk_root="$ANDROID_HOME" --licenses < <(yes) >/dev/null || true

# ---------------------------------------------------------------------------
# 3. Packages.
# ---------------------------------------------------------------------------
packages=(
    "platform-tools"
    "platforms;android-${API_LEVEL}"
    "build-tools;${BUILD_TOOLS_VERSION}"
    "ndk;${NDK_VERSION}"
    "cmake;${CMAKE_VERSION}"
)
if (( want_emulator )); then
    packages+=(
        "emulator"
        "system-images;android-${API_LEVEL};google_apis;x86_64"
    )
fi

echo ">> installing: ${packages[*]}"
"$sdkmanager_bin" --sdk_root="$ANDROID_HOME" --install "${packages[@]}"

# ---------------------------------------------------------------------------
# 4. Verify that the files the build actually needs are present.
# ---------------------------------------------------------------------------
missing=0
check_path() {
    if [[ -e "$1" ]]; then
        echo "   ok  $1"
    else
        echo "   MISSING $1" >&2
        missing=1
    fi
}
echo ">> verifying installation"
check_path "$ANDROID_HOME/platforms/android-${API_LEVEL}/android.jar"
check_path "$ANDROID_HOME/build-tools/${BUILD_TOOLS_VERSION}/aapt2"
check_path "$ANDROID_HOME/platform-tools/adb"
check_path "$ANDROID_HOME/cmake/${CMAKE_VERSION}/bin/cmake"
check_path "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/${NDK_HOST_TAG}/bin"
(( missing == 0 )) || die "some SDK components are missing; re-run ./bootstrap.sh"

# Gradle and IDEs read this; it is gitignored and points at the same SDK.
"$here/scripts/ensure-local-properties.sh"

# ---------------------------------------------------------------------------
# 5. Optional emulator AVD.
# ---------------------------------------------------------------------------
if (( want_avd )); then
    avdmanager_bin="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
    avd_name="${AVD_NAME:-android-dev-${API_LEVEL}}"
    image="system-images;android-${API_LEVEL};google_apis;x86_64"
    if "$avdmanager_bin" list avd 2>/dev/null | grep -q "Name: ${avd_name}$"; then
        echo ">> AVD already exists: $avd_name"
    else
        echo ">> creating AVD: $avd_name"
        printf 'no\n' | "$avdmanager_bin" create avd \
            --name "$avd_name" --package "$image" --force >/dev/null
    fi
fi

# ---------------------------------------------------------------------------
# 6. Gradle wrapper (one-time; needs a system Gradle).
# ---------------------------------------------------------------------------
if [[ ! -x "$here/gradlew" ]]; then
    if command -v gradle >/dev/null 2>&1; then
        "$here/scripts/generate-wrapper.sh" || echo "warning: could not generate the Gradle wrapper" >&2
    else
        echo
        echo "note: no system 'gradle' found, so ./gradlew was not generated."
        echo "      Install Gradle once (or copy a wrapper), then run: make wrapper"
    fi
fi

echo
echo "Done."
echo "  version: API $API_LEVEL (min $MIN_API), build-tools $BUILD_TOOLS_VERSION"
echo "  ndk:     $NDK_VERSION"
echo "  cmake:   $CMAKE_VERSION"
echo
echo "Then:  make doctor && make test && make apk"
echo "       make install          # with a device connected over USB"
echo
# env.sh exports project-specific SDK/NDK paths and prepends to PATH. Sourcing
# it from a shell profile would leak those settings into every other project,
# so prefer a per-directory loader (direnv) or a one-off 'source' per shell.
echo "For interactive adb/sdkmanager/emulator use, either:"
echo "  - run 'direnv allow' (this repo ships an .envrc), or"
echo "  - run 'source \"$here/env.sh\"' in the shell you are working in."
echo "Scripts and Makefile recipes source env.sh themselves."

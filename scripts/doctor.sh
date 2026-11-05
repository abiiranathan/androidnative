#!/usr/bin/env bash
# Prints the toolchain that the build will use and checks for common problems.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../env.sh
source "$root/env.sh"

fail=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
have() { command -v "$1" >/dev/null 2>&1; }

section() { printf '\n%s\n' "$1"; }

section "Project"
printf '  root:       %s\n' "$root"
printf '  host:       %s (%s)\n' "$(uname -s)" "$(uname -m)"
printf '  Android SDK %s\n' "$ANDROID_HOME"

section "Versions (gradle.properties)"
printf '  compileSdk=%s targetSdk=%s minSdk=%s\n' "$API_LEVEL" "$TARGET_API" "$MIN_API"
printf '  build-tools=%s ndk=%s cmake=%s\n' "$BUILD_TOOLS_VERSION" "$NDK_VERSION" "$CMAKE_VERSION"

section "JDK"
if have java && have javac; then
    if [[ "${ANDROID_DEV_JAVA_MAJOR:-0}" -ge 17 && "${ANDROID_DEV_JAVA_RUNTIME_MAJOR:-0}" -ge 17 ]]; then
        ok "$(javac -version 2>&1) / $(java -version 2>&1 | head -n 1) (JAVA_HOME=${JAVA_HOME:-<not set>})"
    else
        bad "JDK 17+ required (javac ${ANDROID_DEV_JAVA_MAJOR:-unknown}, java ${ANDROID_DEV_JAVA_RUNTIME_MAJOR:-unknown})"
    fi
else
    bad "java/javac not on PATH"
fi

section "Host tools"
for tool in curl unzip zip keytool; do
    if have "$tool"; then
        ok "$tool -> $(command -v "$tool")"
    else
        bad "$tool not found"
    fi
done

section "Android SDK"
[[ -f "$ANDROID_HOME/platforms/android-$API_LEVEL/android.jar" ]] \
    && ok "platform android-$API_LEVEL" \
    || bad "missing platform android-$API_LEVEL (run make bootstrap)"

for tool in aapt2 d8 zipalign apksigner; do
    if have "$tool"; then
        ok "$tool -> $(command -v "$tool")"
    else
        bad "$tool not found (build-tools $BUILD_TOOLS_VERSION)"
    fi
done

if have adb; then ok "adb -> $(command -v adb)"; else bad "adb not found (platform-tools)"; fi
if have sdkmanager; then ok "sdkmanager -> $(command -v sdkmanager)"; else bad "sdkmanager not found"; fi

section "Native toolchain"
toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin"
[[ -d "$toolchain" ]] && ok "NDK $NDK_VERSION ($NDK_HOST_TAG)" || bad "missing $toolchain (run make bootstrap)"
[[ -x "$toolchain/aarch64-linux-android${MIN_API}-clang" ]] \
    && ok "aarch64 clang" \
    || bad "missing aarch64 clang wrapper"
[[ -x "$ANDROID_HOME/cmake/$CMAKE_VERSION/bin/cmake" ]] \
    && ok "SDK CMake $CMAKE_VERSION" \
    || bad "missing SDK CMake $CMAKE_VERSION (run make bootstrap)"

section "Gradle"
if [[ -x "$root/gradlew" && -f "$root/gradle/wrapper/gradle-wrapper.jar" ]]; then
    ok "wrapper present ($(sed -n 's/^distributionUrl=.*gradle-\([0-9.]*\)-.*/\1/p' "$root/gradle/wrapper/gradle-wrapper.properties"))"
else
    bad "gradlew or wrapper jar missing (run make wrapper)"
fi
if [[ -f "$root/local.properties" ]]; then
    ok "local.properties: $(tr '\n' ' ' < "$root/local.properties")"
else
    bad "local.properties missing (run make local-properties)"
fi

section "Device"
if have adb; then
    adb devices -l || true
fi

printf '\n'
if (( fail )); then
    echo "doctor: problems found" >&2
    exit 1
fi
echo "doctor: everything looks good"

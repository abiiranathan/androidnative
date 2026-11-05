#!/usr/bin/env bash
# Gradle-free fallback build: NDK clang -> aapt2 -> javac -> d8 -> zipalign
# -> apksigner. Useful when Gradle cannot download its distribution or when you
# want a fast, dependency-free APK. The primary build path is ./gradlew.
#
# Usage: ./build.sh [build|test|install|run|log|clean|help]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$ROOT/env.sh"

readonly APP_ID
readonly ACTIVITY=".MainActivity"
readonly LIB_NAME="nativeapp"
readonly LOG_TAG="NativeApp"
readonly APP_DIR="$ROOT/app/src/main"
readonly BUILD="$ROOT/build/raw"
readonly APK="$BUILD/app-debug.apk"
readonly UNSIGNED_APK="$BUILD/app.unsigned.apk"
readonly ALIGNED_APK="$BUILD/app.aligned.apk"

readonly ANDROID_JAR="$ANDROID_HOME/platforms/android-$API_LEVEL/android.jar"
readonly TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin"

# Debug signing identity (same convention as Android Studio's debug.keystore).
readonly KEYSTORE="${KEYSTORE:-$HOME/.android/debug.keystore}"
readonly KS_ALIAS="androiddebugkey"
readonly KS_PASS="android"

# -Werror matches the project's warning policy; hidden visibility keeps the .so
# surface down to the JNI entry points (marked JNIEXPORT).
readonly CFLAGS=(-std=c11 -O2 -fPIC -Wall -Wextra -Werror -fvisibility=hidden)
# max-page-size=16384: required for devices with 16 KB pages (Android 15+).
readonly LDFLAGS=(-shared -llog -Wl,--no-undefined -Wl,-z,max-page-size=16384)

read -r -a ABI_LIST <<< "${ABIS//,/ }"
readonly ABI_LIST

die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' -- $2"; }

usage() {
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Maps an Android ABI name to the NDK clang target triple prefix.
triple_for_abi() {
    case "$1" in
        arm64-v8a)   echo "aarch64-linux-android" ;;
        armeabi-v7a) echo "armv7a-linux-androideabi" ;;
        x86_64)      echo "x86_64-linux-android" ;;
        x86)         echo "i686-linux-android" ;;
        *) die "unknown ABI: $1" ;;
    esac
}

check_env() {
    (( ${#ABI_LIST[@]} > 0 )) || die "no ABIs configured (set android.abis in gradle.properties)"
    [[ -f "$ANDROID_JAR" ]] || die "missing $ANDROID_JAR -- run ./bootstrap.sh"
    [[ -x "$TOOLCHAIN/$(triple_for_abi "${ABI_LIST[0]}")${MIN_API}-clang" ]] \
        || die "missing NDK toolchain $TOOLCHAIN -- run ./bootstrap.sh"
    for tool in aapt2 d8 zipalign apksigner javac zip keytool; do
        need "$tool" "run ./bootstrap.sh to install the Android SDK tools"
    done
}

# Compiles the portable core and JNI bridge once per ABI into
# build/raw/stage/lib/<abi>/.
build_native() {
    local abi cc out
    rm -rf "$BUILD/stage"
    echo ">> native"
    for abi in "${ABI_LIST[@]}"; do
        cc="$TOOLCHAIN/$(triple_for_abi "$abi")${MIN_API}-clang"
        out="$BUILD/stage/lib/$abi"
        mkdir -p "$out"
        echo "   [$abi]"
        "$cc" "${CFLAGS[@]}" -I"$APP_DIR/cpp" \
            "$APP_DIR/cpp/core.c" "$APP_DIR/cpp/jni_bridge.c" \
            -o "$out/lib${LIB_NAME}.so" "${LDFLAGS[@]}"
    done
}

# aapt2 requires a package attribute, while AGP requires it to be absent from
# the source manifest. Generate an equivalent manifest just for this build.
generate_manifest() {
    awk -v pkg="$APP_ID" '
        !done && /<manifest([[:space:]>])/ {
            if ($0 !~ /package=/) {
                sub(/<manifest/, "<manifest package=\"" pkg "\"")
            }
            done = 1
        }
        { print }
    ' "$APP_DIR/AndroidManifest.xml" > "$BUILD/AndroidManifest.xml"
}

ensure_keystore() {
    [[ -f "$KEYSTORE" ]] && return 0
    mkdir -p "$(dirname "$KEYSTORE")"
    keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KS_PASS" \
        -alias "$KS_ALIAS" -keypass "$KS_PASS" -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
}

build_apk() {
    rm -rf "$BUILD/classes" "$BUILD/dex" "$BUILD/gen" "$BUILD/res.zip" \
           "$BUILD/AndroidManifest.xml" "$UNSIGNED_APK" "$ALIGNED_APK" "$APK"
    mkdir -p "$BUILD/classes" "$BUILD/dex" "$BUILD/gen"

    echo ">> resources"
    aapt2 compile --dir "$APP_DIR/res" -o "$BUILD/res.zip"
    generate_manifest
    aapt2 link -o "$UNSIGNED_APK" -I "$ANDROID_JAR" \
        --manifest "$BUILD/AndroidManifest.xml" --java "$BUILD/gen" \
        --min-sdk-version "$MIN_API" --target-sdk-version "$TARGET_API" \
        --version-code "$APP_VERSION_CODE" --version-name "$APP_VERSION_NAME" \
        "$BUILD/res.zip"

    echo ">> java"
    find "$APP_DIR/java" "$BUILD/gen" -name '*.java' -print0 |
        xargs -0 javac --release 11 -Xlint:all -classpath "$ANDROID_JAR" -d "$BUILD/classes"
    find "$BUILD/classes" -name '*.class' -print0 |
        xargs -0 d8 --lib "$ANDROID_JAR" --min-api "$MIN_API" --output "$BUILD/dex"

    echo ">> package"
    zip -q -j "$UNSIGNED_APK" "$BUILD/dex/classes.dex"
    (cd "$BUILD/stage" && zip -q -r "$UNSIGNED_APK" lib)
    zipalign -f 4 "$UNSIGNED_APK" "$ALIGNED_APK"

    ensure_keystore
    apksigner sign --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" \
        --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
        --min-sdk-version "$MIN_API" --out "$APK" "$ALIGNED_APK"
    apksigner verify --verbose "$APK" >/dev/null
    echo ">> built $APK"
}

require_device() {
    local count
    need adb "install platform-tools (run ./bootstrap.sh)"
    count="$(adb devices | awk 'NR > 1 && $2 == "device" { n++ } END { print n + 0 }')"
    (( count > 0 )) || die "no physical device or emulator found (check 'adb devices' and USB debugging)"
}

# Host-side unit tests for the portable C core (no Android involved).
run_tests() {
    local cc="${CC:-cc}"
    mkdir -p "$BUILD"
    echo ">> host tests ($("$cc" --version 2>/dev/null | head -n 1 || echo "$cc"))"
    "$cc" -std=c11 -O0 -g -Wall -Wextra -Werror -I"$APP_DIR/cpp" \
        "$ROOT/tests/test_core.c" "$APP_DIR/cpp/core.c" -o "$BUILD/test_core"
    "$BUILD/test_core"
}

cmd="${1:-build}"
case "$cmd" in
    help|-h|--help) usage ;;
    build)
        check_env
        build_native
        build_apk
        ;;
    test)
        run_tests
        ;;
    install)
        check_env
        require_device
        [[ -f "$APK" ]] || { build_native; build_apk; }
        adb install -r "$APK"
        ;;
    run)
        check_env
        require_device
        build_native
        build_apk
        adb install -r "$APK"
        adb shell am start -n "$APP_ID/$ACTIVITY"
        ;;
    log)
        need adb "install platform-tools"
        adb logcat -s "$LOG_TAG:V" AndroidRuntime:E
        ;;
    clean)
        rm -rf "$BUILD"
        ;;
    *)
        die "usage: $0 [build|test|install|run|log|clean|help]"
        ;;
esac

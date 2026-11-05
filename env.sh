#!/usr/bin/env bash
# Shared configuration for every script in this project.
#
# Usage:
#   source env.sh            # interactive shells / shell profile
#   scripts/env-run.sh CMD   # scripts and Makefile recipes
#
# This file is *sourced*, so it deliberately does not enable `set -e`.
# SDK/NDK/CMake versions are read from gradle.properties, which is the single
# source of truth, so Gradle and the shell scripts cannot drift apart. Change
# versions in gradle.properties, then re-run ./bootstrap.sh. ANDROID_HOME,
# JAVA_HOME, CMDLINE_TOOLS_REV and the signing keystore can still be overridden
# from the environment.

_android_dev_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ANDROID_DEV_ROOT="$_android_dev_root"

# Reads `key=value` from gradle.properties, falling back to $2.
_android_dev_prop() {
    local key="$1" fallback="$2" value=""
    if [[ -r "$_android_dev_root/gradle.properties" ]]; then
        value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" \
            "$_android_dev_root/gradle.properties" | tail -n 1)"
    fi
    printf '%s' "${value:-$fallback}"
}

# ---------------------------------------------------------------------------
# Versions (gradle.properties is authoritative)
# ---------------------------------------------------------------------------
API_LEVEL="$(_android_dev_prop android.compileSdk 34)"                  # compileSdk
TARGET_API="$(_android_dev_prop android.targetSdk "$API_LEVEL")"        # targetSdk
MIN_API="$(_android_dev_prop android.minSdk 24)"                        # minSdk
BUILD_TOOLS_VERSION="$(_android_dev_prop android.buildToolsVersion 36.0.0)"
NDK_VERSION="$(_android_dev_prop android.ndkVersion 27.0.12077973)"
CMAKE_VERSION="$(_android_dev_prop android.cmakeVersion 3.22.1)"
ABIS="$(_android_dev_prop android.abis 'arm64-v8a,x86_64')"             # NDK ABIs
APP_ID="$(_android_dev_prop android.applicationId com.example.nativeapp)"
APP_VERSION_CODE="$(_android_dev_prop android.versionCode 1)"
APP_VERSION_NAME="$(_android_dev_prop android.versionName 1.0)"
: "${CMDLINE_TOOLS_REV:=11076708}" # bump if Google retires this archive

# Exported for child processes (bootstrap, build.sh, Gradle via env-run.sh).
export API_LEVEL TARGET_API MIN_API BUILD_TOOLS_VERSION NDK_VERSION CMAKE_VERSION
export ABIS APP_ID APP_VERSION_CODE APP_VERSION_NAME

# ---------------------------------------------------------------------------
# Android SDK location. Explicit environment wins; otherwise try common paths.
# ---------------------------------------------------------------------------
if [[ -z "${ANDROID_HOME:-}" ]]; then
    for _android_dev_candidate in \
        "${ANDROID_SDK_ROOT:-}" \
        "$HOME/Android/Sdk" \
        "$HOME/Library/Android/sdk" \
        "/opt/android-sdk" \
        "/usr/lib/android-sdk"; do
        if [[ -n "$_android_dev_candidate" && -d "$_android_dev_candidate" ]]; then
            ANDROID_HOME="$_android_dev_candidate"
            break
        fi
    done
    unset _android_dev_candidate
fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

# The NDK path follows gradle.properties, not a potentially stale shell export.
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    Linux)
        NDK_HOST_TAG="linux-x86_64"
        CMDLINE_OS="linux"
        ;;
    Darwin)
        NDK_HOST_TAG="darwin-x86_64"
        CMDLINE_OS="mac"
        ;;
    *)
        echo "error: unsupported host OS '$(uname -s)' (use WSL on Windows)" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac
export NDK_HOST_TAG CMDLINE_OS

# ---------------------------------------------------------------------------
# JDK. Gradle only needs a JDK 17+ on PATH, but exporting JAVA_HOME makes IDE
# and Gradle launches consistent when the shell already has a JDK.
# ---------------------------------------------------------------------------
if [[ -z "${JAVA_HOME:-}" ]] && command -v javac >/dev/null 2>&1; then
    _android_dev_javac="$(command -v javac)"
    _android_dev_real=""
    if command -v readlink >/dev/null 2>&1; then
        _android_dev_real="$(readlink -f "$_android_dev_javac" 2>/dev/null || true)"
    fi
    if [[ -n "$_android_dev_real" ]]; then
        _android_dev_home="$(cd "$(dirname "$_android_dev_real")/.." 2>/dev/null && pwd || true)"
        if [[ -n "$_android_dev_home" && -x "$_android_dev_home/bin/javac" ]]; then
            export JAVA_HOME="$_android_dev_home"
        fi
    fi
    unset _android_dev_javac _android_dev_real _android_dev_home
fi

if command -v javac >/dev/null 2>&1; then
    _android_dev_jv="$(javac -version 2>&1 | awk '{print $2; exit}')"
    _android_dev_jmajor="${_android_dev_jv%%.*}"
    [[ "$_android_dev_jmajor" == "1" ]] && _android_dev_jmajor="$(printf '%s' "$_android_dev_jv" | cut -d. -f2)"
    export ANDROID_DEV_JAVA_MAJOR="${_android_dev_jmajor:-0}"
    unset _android_dev_jv _android_dev_jmajor
else
    export ANDROID_DEV_JAVA_MAJOR=0
fi

if command -v java >/dev/null 2>&1; then
    _android_dev_jrv="$(java -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')"
    _android_dev_jrmajor="${_android_dev_jrv%%.*}"
    [[ "$_android_dev_jrmajor" == "1" ]] && _android_dev_jrmajor="$(printf '%s' "$_android_dev_jrv" | cut -d. -f2)"
    export ANDROID_DEV_JAVA_RUNTIME_MAJOR="${_android_dev_jrmajor:-0}"
    unset _android_dev_jrv _android_dev_jrmajor
else
    export ANDROID_DEV_JAVA_RUNTIME_MAJOR=0
fi

# ---------------------------------------------------------------------------
# PATH: prepend SDK tools without duplicating entries on repeated sourcing.
# ---------------------------------------------------------------------------
_android_dev_prepend_path() {
    [[ -d "$1" ]] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}

_android_dev_prepend_path "$ANDROID_HOME/cmdline-tools/latest/bin"
_android_dev_prepend_path "$ANDROID_HOME/platform-tools"
_android_dev_prepend_path "$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION"
_android_dev_prepend_path "$ANDROID_HOME/cmake/$CMAKE_VERSION/bin"
_android_dev_prepend_path "$ANDROID_HOME/emulator"

export PATH
unset _android_dev_prepend_path

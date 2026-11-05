#!/usr/bin/env bash
# Generates (or regenerates) the Gradle wrapper without configuring this
# project. A system Gradle is only needed for this one-time step; the wrapper
# pins the version used by every later build.
#
# Usage: scripts/generate-wrapper.sh [--force]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
force=0
[[ "${1:-}" == "--force" ]] && force=1

properties="$root/gradle/wrapper/gradle-wrapper.properties"
version="${GRADLE_VERSION:-}"
if [[ -z "$version" && -r "$properties" ]]; then
    version="$(sed -n 's/^distributionUrl=.*gradle-\([0-9.]*\)-.*/\1/p' "$properties" | head -n 1)"
fi
version="${version:-8.10.2}"

if (( force == 0 )) && [[ -x "$root/gradlew" && -f "$root/gradle/wrapper/gradle-wrapper.jar" ]]; then
    echo "Gradle wrapper already present (use --force to regenerate)."
    exit 0
fi

if ! command -v gradle >/dev/null 2>&1; then
    echo "error: system 'gradle' is required once to generate the wrapper." >&2
    echo "       Arch: sudo pacman -S gradle    Debian/Ubuntu: sudo apt install gradle" >&2
    echo "       Or copy a wrapper from another project and set the URL to Gradle $version." >&2
    exit 1
fi

echo ">> generating Gradle wrapper $version"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Pin the distribution checksum when it can be fetched; this protects future
# builds against a tampered or truncated download.
sha256="${GRADLE_SHA256:-}"
if [[ -z "$sha256" ]] && command -v curl >/dev/null 2>&1; then
    sha256="$(curl -fsSL --max-time 20 \
        "https://services.gradle.org/distributions/gradle-${version}-bin.zip.sha256" \
        2>/dev/null || true)"
fi

# Use a throwaway project so the installed Gradle never evaluates this project's
# build scripts (a system Gradle 9.x cannot necessarily configure AGP 8.x).
printf 'rootProject.name = "wrapper-seed"\n' > "$tmp/settings.gradle.kts"
wrapper_args=(wrapper --gradle-version "$version" --distribution-type bin)
if [[ -n "$sha256" ]]; then
    wrapper_args+=(--gradle-distribution-sha256-sum "$sha256")
fi
(
    cd "$tmp"
    gradle --no-daemon --console=plain "${wrapper_args[@]}"
)

mkdir -p "$root/gradle/wrapper"
cp "$tmp/gradlew" "$tmp/gradlew.bat" "$root/"
cp "$tmp/gradle/wrapper/gradle-wrapper.jar" \
   "$tmp/gradle/wrapper/gradle-wrapper.properties" \
   "$root/gradle/wrapper/"
chmod +x "$root/gradlew"

echo ">> wrote $root/gradlew"

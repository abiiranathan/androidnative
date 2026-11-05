#!/usr/bin/env bash
# Creates or updates local.properties (gitignored) so Gradle and IDEs find the
# same SDK that env.sh selected. Other local properties are preserved.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../env.sh
source "$root/env.sh"

properties="$root/local.properties"
current=""
if [[ -f "$properties" ]]; then
    current="$(sed -n 's/^sdk\.dir=//p' "$properties" | tail -n 1)"
fi

if [[ "$current" != "$ANDROID_HOME" ]]; then
    tmp="$(mktemp "$properties.XXXXXX")"
    if [[ -f "$properties" ]]; then
        grep -v '^sdk\.dir=' "$properties" > "$tmp" || true
    fi
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" >> "$tmp"
    mv "$tmp" "$properties"
    echo ">> local.properties: sdk.dir=$ANDROID_HOME"
fi

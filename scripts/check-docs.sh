#!/usr/bin/env bash
# Checks that documented SDK examples match gradle.properties.
#
# Usage: scripts/check-docs.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
properties="$root/gradle.properties"
compile_sdk="$(sed -n 's/^android\.compileSdk=//p' "$properties" | tail -n 1)"
target_sdk="$(sed -n 's/^android\.targetSdk=//p' "$properties" | tail -n 1)"

[[ "$compile_sdk" =~ ^[0-9]+$ ]] || {
    echo "error: android.compileSdk must be a plain integer in $properties" >&2
    exit 1
}
[[ "$target_sdk" =~ ^[0-9]+$ ]] || {
    echo "error: android.targetSdk must be a plain integer in $properties" >&2
    exit 1
}

require_line() {
    local file="$1" expected="$2"
    if ! grep -Fqx -- "$expected" "$root/$file"; then
        echo "error: $file is missing or has a stale SDK example: $expected" >&2
        return 1
    fi
}

require_contains() {
    local file="$1" expected="$2"
    if ! grep -Fq -- "$expected" "$root/$file"; then
        echo "error: $file is missing or has a stale SDK example: $expected" >&2
        return 1
    fi
}

for file in README.md CUSTOMIZING.md; do
    require_line "$file" "android.compileSdk=$compile_sdk"
    require_line "$file" "android.targetSdk=$target_sdk"
done

require_line QUICKSTART.md "- \`platforms;android-$compile_sdk\`"
require_contains QUICKSTART.md "\`android-dev-$compile_sdk\`"

if (( target_sdk >= 36 )); then
    require_contains CUSTOMIZING.md "This template pins \`targetSdk=$target_sdk\`, so no target API bump is needed"
fi

echo ">> documentation SDK examples match compileSdk=$compile_sdk and targetSdk=$target_sdk"

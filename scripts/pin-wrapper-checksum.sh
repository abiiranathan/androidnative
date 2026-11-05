#!/usr/bin/env bash
# Fetches and pins the official SHA-256 for the configured Gradle distribution.
#
# Usage: scripts/pin-wrapper-checksum.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
properties="$root/gradle/wrapper/gradle-wrapper.properties"

[[ -r "$properties" ]] || {
    echo "error: missing $properties" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required to fetch the Gradle distribution checksum" >&2
    exit 1
}

distribution_url="$(sed -n 's/^distributionUrl=//p' "$properties" | tail -n 1)"
distribution_url="${distribution_url//\\:/:}"
[[ "$distribution_url" == https://services.gradle.org/distributions/* ]] || {
    echo "error: unsupported Gradle distribution URL: $distribution_url" >&2
    exit 1
}

checksum_url="${distribution_url}.sha256"
checksum="$(curl -fsSL --max-time 30 "$checksum_url" | awk 'NR == 1 { print $1 }')"
[[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]] || {
    echo "error: invalid SHA-256 response from $checksum_url" >&2
    exit 1
}

tmp="$(mktemp "$properties.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
awk -v checksum="$checksum" '
    /^distributionSha256Sum=/ { next }
    {
        print
        if (!inserted && /^distributionUrl=/) {
            print "distributionSha256Sum=" checksum
            inserted = 1
        }
    }
    END { if (!inserted) exit 1 }
' "$properties" > "$tmp"

mv "$tmp" "$properties"
trap - EXIT
echo ">> pinned Gradle distribution SHA-256: $checksum"

#!/usr/bin/env bash
# Fails early with a useful message when no usable device is attached.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../env.sh
source "$root/env.sh"

mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')

if (( ${#devices[@]} == 0 )); then
    cat >&2 <<'EOF'
error: no device found.

Connect a physical device and enable USB debugging:
  1. Settings -> About phone -> tap "Build number" 7 times
  2. Settings -> System -> Developer options -> USB debugging
  3. Accept the RSA fingerprint prompt on the device
  4. Verify with: adb devices
EOF
    exit 1
fi

if (( ${#devices[@]} > 1 )); then
    echo "warning: ${#devices[@]} devices connected; adb uses ANDROID_SERIAL or an interactive prompt" >&2
fi

printf 'device: %s\n' "${devices[*]}"

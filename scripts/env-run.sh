#!/usr/bin/env bash
# Runs a command with the project's Android toolchain on PATH.
#
# Usage: scripts/env-run.sh <command> [args...]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../env.sh
source "$root/env.sh"

exec "$@"

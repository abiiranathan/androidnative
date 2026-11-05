#!/usr/bin/env bash
# Creates a clean, shareable source archive of this project. The archive is
# suitable for handing to someone else or attaching to a release; it contains
# no git history, build outputs, local SDK paths, APKs or signing material.
#
# Usage: scripts/package-template.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

name="$(sed -n 's/^rootProject\.name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' \
    "$root/settings.gradle.kts" | tail -n 1)"
name="${name:-androidnative}"
version="$(sed -n 's/^android\.versionName=//p' "$root/gradle.properties" | tail -n 1)"
version="${version:-0.0.0}"

outdir="$root/dist"
archive="$outdir/${name}-${version}.tar.gz"
top="${name}-${version}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/$top" "$outdir"

echo ">> staging $top"
tar -C "$root" \
    --exclude='./.git' --exclude='./.git/*' \
    --exclude='./.gradle' --exclude='./.gradle/*' \
    --exclude='./.kotlin' --exclude='./.kotlin/*' \
    --exclude='./.idea' --exclude='./.idea/*' \
    --exclude='./.externalNativeBuild' --exclude='./.externalNativeBuild/*' \
    --exclude='./build' --exclude='./build/*' \
    --exclude='./app/build' --exclude='./app/build/*' \
    --exclude='./app/bin' --exclude='./app/bin/*' \
    --exclude='./app/.cxx' --exclude='./app/.cxx/*' \
    --exclude='./app/.externalNativeBuild' --exclude='./app/.externalNativeBuild/*' \
    --exclude='./.classpath' --exclude='./.project' \
    --exclude='./.settings' --exclude='./.settings/*' \
    --exclude='./app/.classpath' --exclude='./app/.project' \
    --exclude='./app/.settings' --exclude='./app/.settings/*' \
    --exclude='./app/factorypath' \
    --exclude='./dist' --exclude='./dist/*' \
    --exclude='./captures' --exclude='./captures/*' \
    --exclude='./out' --exclude='./out/*' \
    --exclude='./local.properties' \
    --exclude='./*.iml' --exclude='*/*.iml' --exclude='*/*/*.iml' \
    --exclude='*.jks' --exclude='*.keystore' --exclude='*.p12' \
    --exclude='*.pem' --exclude='*.key' \
    --exclude='./keystore.properties' --exclude='./signing.properties' \
    --exclude='./*.tar.gz' --exclude='./*.tgz' \
    --exclude='*.apk' --exclude='*.aab' --exclude='*.ap_' \
    --exclude='*.dex' --exclude='*.hprof' \
    --exclude='*.log' --exclude='./.env' --exclude='./.env.*' \
    --exclude='*.swp' --exclude='*.swo' --exclude='.DS_Store' \
    -cf - . | tar -C "$stage/$top" -xf -

# Fail loudly rather than shipping a polluted archive.
polluted() {
    find "$stage/$top" \
        \( -name '.git' -o -name '.gradle' -o -name '.kotlin' -o -name '.idea' \
           -o -name '.externalNativeBuild' -o -name 'build' -o -name 'bin' \
           -o -name '.cxx' -o -name 'dist' -o -name 'captures' -o -name 'out' \
           -o -name '.classpath' -o -name '.project' -o -name '.settings' \
           -o -name 'factorypath' \
           -o -name 'local.properties' -o -name 'keystore.properties' \
           -o -name 'signing.properties' -o -name '*.iml' \
           -o -name '*.apk' -o -name '*.aab' -o -name '*.ap_' \
           -o -name '*.jks' -o -name '*.keystore' -o -name '*.p12' \
           -o -name '*.pem' -o -name '*.key' -o -name '*.log' \
           -o -name '*.tar.gz' -o -name '*.tgz' -o -name '.env' -o -name '.env.*' \) \
        -print
}
if [[ -n "$(polluted)" ]]; then
    echo "error: staging directory contains ignored artifacts:" >&2
    polluted >&2
    exit 1
fi

tar -C "$stage" -czf "$archive" "$top"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$outdir" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$outdir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
fi

echo ">> wrote $archive"
echo "   size: $(du -h "$archive" | cut -f1)"
if [[ -f "$archive.sha256" ]]; then
    echo "   sha256: $(cut -d' ' -f1 "$archive.sha256")"
fi
echo
echo "Recipient can unpack it with:"
echo "  tar -xzf $(basename "$archive") && cd $top"

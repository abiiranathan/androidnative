#!/usr/bin/env bash
# Renames this template for a new project: application ID, Java/Kotlin package
# and source directories, app label, native library, JNI symbol, log tag and the
# Gradle project name. The checkout is edited in place; .git is never touched.
#
# Usage:
#   scripts/new-project.sh --name "My App" --package com.example.myapp [--force]
#
# Options:
#   --name NAME        Display name (app label, README title). Required.
#   --package PACKAGE  Java application ID, e.g. com.example.myapp. Required.
#   --project SLUG     Gradle/archive name. Default: derived from --name.
#   --force            Allow running with uncommitted changes.
#   -h, --help         Show this help.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() { echo "error: $*" >&2; exit 1; }

usage() {
    sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

display_name=""
package=""
project=""
force=0
while (( $# )); do
    case "$1" in
        --name)    display_name="${2:-}"; shift 2 ;;
        --package) package="${2:-}"; shift 2 ;;
        --project) project="${2:-}"; shift 2 ;;
        --force)   force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option '$1' (try --help)" ;;
    esac
done

[[ -n "$display_name" ]] || die "--name is required (try --help)"
[[ -n "$package" ]] || die "--package is required (try --help)"
[[ "$display_name" != *$'\n'* ]] || die "--name must be a single line"
[[ "$package" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] \
    || die "--package must be a Java/Kotlin package with at least two segments, e.g. com.example.myapp"

# ---------------------------------------------------------------------------
# Derive names.
# ---------------------------------------------------------------------------
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//' \
        | cut -c1-64
}

if [[ -z "$project" ]]; then
    project="$(slugify "$display_name")"
    [[ -n "$project" ]] \
        || die "cannot derive a project name from '$display_name'; pass --project"
fi
[[ "$project" =~ ^[a-z0-9][a-z0-9._-]*$ ]] \
    || die "--project must start with a letter/digit and contain only a-z, 0-9, '.', '_' or '-'"

log_tag="$(printf '%s' "$display_name" | tr -cd '[:alnum:]' | cut -c1-32)"
[[ -n "$log_tag" ]] || log_tag="$(printf '%s' "$project" | tr -cd '[:alnum:]')"
[[ -n "$log_tag" ]] || die "cannot derive a log tag; use a name with letters or digits"

# Native library name follows the last package segment.
lib_name="${package##*.}"
lib_name="$(printf '%s' "$lib_name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_')"
lib_name="${lib_name%_}"
[[ "$lib_name" =~ ^[a-z0-9_]+$ ]] \
    || die "cannot derive a native library name from package '$package'"

# JNI encodes '.' and '_' in class/package names.
jni_symbol_for() {
    local s="$1"
    s="${s//_/_1}"
    s="${s//./_}"
    printf '%s' "$s"
}

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

# Escape a string so sed treats it as a literal BRE pattern.
sed_pattern() {
    printf '%s' "$1" | sed -e 's/[][\\.*^$]/\\&/g'
}

# Escape a string for use as the replacement half of a sed s|...|...|g.
sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Replaces every literal occurrence of $1 with $2 in file $3. Portable across
# GNU and BSD sed (the temporary .bak file is removed either way).
replace_in_file() {
    local old="$1" new="$2" file="$3"
    [[ -f "$file" ]] || return 0
    sed -i.bak "s|$(sed_pattern "$old")|$(sed_replacement "$new")|g" "$file"
    rm -f "$file.bak"
}

# ---------------------------------------------------------------------------
# Read the current identity from the checkout.
# ---------------------------------------------------------------------------
old_package="$(sed -n 's/^android\.applicationId=//p' gradle.properties | tail -n 1)"
[[ -n "$old_package" ]] || die "cannot read android.applicationId from gradle.properties"

old_project="$(sed -n 's/^rootProject\.name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' \
    settings.gradle.kts | tail -n 1)"
old_project="${old_project:-androidnative}"

old_label="$(sed -n 's/.*<string name="app_name">\(.*\)<\/string>.*/\1/p' \
    app/src/main/res/values/strings.xml | tail -n 1)"
old_label="${old_label:-NativeApp}"

old_log_tag="$(sed -n 's/^#define LOG_TAG "\(.*\)"/\1/p' \
    app/src/main/cpp/jni_bridge.c | tail -n 1)"
old_log_tag="${old_log_tag:-NativeApp}"

old_lib_name="$(sed -n 's/^add_library(\([A-Za-z0-9_]*\) SHARED.*/\1/p' \
    app/src/main/cpp/CMakeLists.txt | tail -n 1)"
old_lib_name="${old_lib_name:-nativeapp}"

old_jni="Java_$(jni_symbol_for "$old_package")_NativeGreeting_format"
new_jni="Java_$(jni_symbol_for "$package")_NativeGreeting_format"

old_readme_title="$(sed -n '1s/^# //p' README.md)"
old_readme_title="${old_readme_title:-$old_project}"

# ---------------------------------------------------------------------------
# Safety checks.
# ---------------------------------------------------------------------------
if (( ! force )) && command -v git >/dev/null 2>&1 \
        && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain)" ]]; then
        die "uncommitted changes; commit them first or re-run with --force"
    fi
fi

if [[ "$package" == "$old_package" && "$project" == "$old_project" \
        && "$display_name" == "$old_label" ]]; then
    die "the project already has these values; nothing to rename"
fi

for base in app/src/main/java app/src/test/java app/src/androidTest/java; do
    old_dir="$base/${old_package//.//}"
    new_dir="$base/${package//.//}"
    if [[ "$old_dir" != "$new_dir" && -e "$new_dir" ]]; then
        die "$new_dir already exists; remove it or choose another --package"
    fi
done

# ---------------------------------------------------------------------------
# Move Java/Kotlin source trees.
# ---------------------------------------------------------------------------
moved_dirs=()
for base in app/src/main/java app/src/test/java app/src/androidTest/java; do
    old_dir="$base/${old_package//.//}"
    new_dir="$base/${package//.//}"
    [[ "$old_dir" == "$new_dir" ]] && continue
    [[ -d "$old_dir" ]] || continue

    mkdir -p "$(dirname "$new_dir")"
    mv "$old_dir" "$new_dir"
    moved_dirs+=("$old_dir -> $new_dir")

    # Remove now-empty package directories, stopping at the source root.
    dir="$(dirname "$old_dir")"
    while [[ "$dir" != "$base" && "$dir" != "/" ]]; do
        rmdir "$dir" 2>/dev/null || break
        dir="$(dirname "$dir")"
    done
done

# ---------------------------------------------------------------------------
# Rewrite file contents.
# ---------------------------------------------------------------------------
replace_in_file "android.applicationId=$old_package" \
    "android.applicationId=$package" gradle.properties
replace_in_file "rootProject.name = \"$old_project\"" \
    "rootProject.name = \"$project\"" settings.gradle.kts
replace_in_file "android.applicationId $old_package" \
    "android.applicationId $package" env.sh
replace_in_file "configString(\"android.applicationId\", \"$old_package\")" \
    "configString(\"android.applicationId\", \"$package\")" app/build.gradle.kts
replace_in_file "APP_ID      := $old_package" \
    "APP_ID      := $package" Makefile

replace_in_file ">$old_label<" \
    ">$(xml_escape "$display_name")<" app/src/main/res/values/strings.xml

# Rewrite every Java and Kotlin package declaration, at any package depth.
while IFS= read -r -d '' java_file; do
    replace_in_file "package $old_package;" "package $package;" "$java_file"
done < <(find app/src -name '*.java' -print0)

while IFS= read -r -d '' kotlin_file; do
    replace_in_file "package $old_package" "package $package" "$kotlin_file"
done < <(find app/src -name '*.kt' -print0)

replace_in_file "$old_jni" "$new_jni" app/src/main/cpp/jni_bridge.c
replace_in_file "#define LOG_TAG \"$old_log_tag\"" \
    "#define LOG_TAG \"$log_tag\"" app/src/main/cpp/jni_bridge.c
replace_in_file "readonly LOG_TAG=\"$old_log_tag\"" \
    "readonly LOG_TAG=\"$log_tag\"" build.sh
replace_in_file "adb logcat -s $old_log_tag:V" \
    "adb logcat -s $log_tag:V" Makefile
replace_in_file "adb logcat -s $old_log_tag:V" \
    "adb logcat -s $log_tag:V" README.md

replace_in_file "$old_lib_name" "$lib_name" app/src/main/cpp/CMakeLists.txt
replace_in_file "readonly LIB_NAME=\"$old_lib_name\"" \
    "readonly LIB_NAME=\"$lib_name\"" build.sh
replace_in_file "System.loadLibrary(\"$old_lib_name\")" \
    "System.loadLibrary(\"$lib_name\")" \
    "app/src/main/java/${package//.//}/NativeGreeting.java"
replace_in_file "lib$old_lib_name.so" "lib$lib_name.so" \
    "app/src/main/java/${package//.//}/NativeGreeting.java"
replace_in_file "lib$old_lib_name.so" "lib$lib_name.so" README.md

# README: title, property snippet, and the template source URLs are preserved
# on purpose (they point at the upstream template, not the new project).
replace_in_file "# $old_readme_title" "# $display_name" README.md
replace_in_file "android.applicationId=$old_package" \
    "android.applicationId=$package" README.md
replace_in_file "androidnative-<version>" "$project-<version>" README.md

# ---------------------------------------------------------------------------
# Verify the important identities actually changed.
# ---------------------------------------------------------------------------
fail=0
check_contains() {
    local needle="$1" file="$2" what="$3"
    if ! grep -qF -- "$needle" "$file"; then
        echo "error: $what not found in $file" >&2
        fail=1
    fi
}
check_absent() {
    local needle="$1" where="$2" what="$3"
    if grep -rqF -- "$needle" $where 2>/dev/null; then
        echo "error: $what still contains '$needle'" >&2
        fail=1
    fi
}
check_absent_regex() {
    local pattern="$1" where="$2" what="$3"
    if grep -rqE -- "$pattern" $where 2>/dev/null; then
        echo "error: $what still matches '$pattern'" >&2
        fail=1
    fi
}

check_contains "android.applicationId=$package" gradle.properties "new application ID"
check_contains "rootProject.name = \"$project\"" settings.gradle.kts "new project name"
check_contains "$new_jni" app/src/main/cpp/jni_bridge.c "new JNI symbol"
if [[ "$old_jni" != "$new_jni" ]]; then
    check_absent "$old_jni" "app/src/main/cpp" "native sources"
fi
if [[ "$old_package" != "$package" ]]; then
    check_absent "package $old_package;" "app/src" "Java sources"
    check_absent_regex "^[[:space:]]*package[[:space:]]+${old_package//./\\.}[[:space:]]*$" \
        "app/src" "Kotlin sources"
fi
check_contains "package $package;" \
    "app/src/main/java/${package//.//}/MainActivity.java" "new Java package"
if [[ -f "app/src/main/java/${package//.//}/KotlinSmoke.kt" ]]; then
    check_contains "package $package" \
        "app/src/main/java/${package//.//}/KotlinSmoke.kt" "new Kotlin package"
fi
if [[ -f "app/src/test/java/${package//.//}/KotlinSmokeTest.kt" ]]; then
    check_contains "package $package" \
        "app/src/test/java/${package//.//}/KotlinSmokeTest.kt" "new Kotlin test package"
fi
check_contains "System.loadLibrary(\"$lib_name\")" \
    "app/src/main/java/${package//.//}/NativeGreeting.java" "new native library name"
check_contains ">$(xml_escape "$display_name")<" \
    app/src/main/res/values/strings.xml "new app label"

if (( fail )); then
    echo >&2
    echo "error: rename is incomplete; inspect 'git diff' and fix the files above" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
echo "Renamed project"
echo "  name:      $display_name"
echo "  package:   $package"
echo "  project:   $project"
echo "  log tag:   $log_tag"
echo "  native:    lib$lib_name.so"
echo "  JNI:       $new_jni"
if (( ${#moved_dirs[@]} )); then
    echo "  moved:"
    printf '    %s\n' "${moved_dirs[@]}"
fi
echo
echo "Next steps:"
echo "  git diff"
echo "  make doctor"
echo "  make test"
echo "  make apk"

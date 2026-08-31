#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="${1:-$ROOT_DIR/output/mlp1/yabasanshiro}"
MANIFEST="$PACKAGE_DIR/manifest.json"

for required_path in \
    "$PACKAGE_DIR/bin/yabasanshiro" \
    "$PACKAGE_DIR/launch.sh" \
    "$PACKAGE_DIR/defaults/config.version" \
    "$PACKAGE_DIR/defaults/es_temporaryinput.cfg" \
    "$PACKAGE_DIR/licenses/DISTRIBUTION-BASIS.md" \
    "$PACKAGE_DIR/licenses/upstream-LICENSE.txt" \
    "$PACKAGE_DIR/licenses/Yabause-GPL-2.0.txt" \
    "$PACKAGE_DIR/licenses/NanoGUI-BSD-3-Clause.txt" \
    "$PACKAGE_DIR/licenses/pugixml-MIT.txt" \
    "$PACKAGE_DIR/licenses/nlohmann-json-MIT.txt" \
    "$PACKAGE_DIR/licenses/libchdr-BSD-3-Clause.txt" \
    "$PACKAGE_DIR/provenance/build-manifest.json" \
    "$PACKAGE_DIR/provenance/build-flags.env" \
    "$PACKAGE_DIR/provenance/elf-dynamic.txt" \
    "$PACKAGE_DIR/provenance/patches.sha256" \
    "$MANIFEST"; do
    if [ ! -f "$required_path" ]; then
        echo "missing required emulator package file: $required_path" >&2
        exit 1
    fi
done

if [ ! -x "$PACKAGE_DIR/bin/yabasanshiro" ] ||
   [ ! -x "$PACKAGE_DIR/launch.sh" ]; then
    echo "binary and launch wrapper must be executable" >&2
    exit 1
fi
if find "$PACKAGE_DIR" -type l -print -quit | grep -q .; then
    echo "package is not FAT32-safe: symlink found" >&2
    exit 1
fi
for excluded_term in \
    "$PACKAGE_DIR/licenses/RELEASE-BLOCKED.txt" \
    "$PACKAGE_DIR/licenses/upstream-EULA.txt"; do
    if [ -e "$excluded_term" ]; then
        echo "contradictory distribution term found: $excluded_term" >&2
        exit 1
    fi
done

bash -n "$PACKAGE_DIR/launch.sh"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$PACKAGE_DIR/defaults/es_temporaryinput.cfg"
fi
file "$PACKAGE_DIR/bin/yabasanshiro" |
    grep -q 'ELF 64-bit LSB.*ARM aarch64'

jq -e '
  .id == "yabasanshiro_standalone" and
  .platform == "mlp1" and
  .kind == "standalone-emulator" and
  .license == "GPL-2.0" and
  .distribution_status == "release-owner-approved-gpl-2.0-basis" and
  .distribution_basis == "licenses/DISTRIBUTION-BASIS.md" and
  (.corresponding_source | type == "object") and
  (.corresponding_source.url | type == "string" and length > 0) and
  .corresponding_source.archive == "yabasanshiro-standalone-1.11.beta3-mlp1-source.tar.gz" and
  (.corresponding_source.sha256 == null or
    (.corresponding_source.sha256 | test("^[0-9a-f]{64}$"))) and
  .package_schema_version == 1 and
  .config_schema_version == 2 and
  (.patches | type == "array" and length > 0) and
  all(.patches[];
    (.sha256 | test("^[0-9a-f]{64}$")) and
    (.path | startswith("patches/")) and
    .upstream_status == "not-submitted") and
  (.files | type == "array" and length > 0)
' "$MANIFEST" >/dev/null

grep -F 'name="select"        type="button" id="10"' \
    "$PACKAGE_DIR/defaults/es_temporaryinput.cfg" >/dev/null

binary_sha="$(shasum -a 256 "$PACKAGE_DIR/bin/yabasanshiro" | awk '{print $1}')"
if [ "$binary_sha" != "$(jq -r '.binary_sha256' "$MANIFEST")" ]; then
    echo "package binary checksum does not match manifest" >&2
    exit 1
fi

expected_files="$(mktemp)"
actual_files="$(mktemp)"
trap 'rm -f "$expected_files" "$actual_files"' EXIT
jq -r '.files[].path' "$MANIFEST" | LC_ALL=C sort >"$expected_files"
(
    cd "$PACKAGE_DIR"
    find . -type f ! -path './manifest.json' -print |
        sed 's#^\./##' | LC_ALL=C sort
) >"$actual_files"
if ! diff -u "$expected_files" "$actual_files"; then
    echo "manifest file inventory does not match package" >&2
    exit 1
fi

while IFS=$'\t' read -r expected_sha relative_path; do
    actual_sha="$(shasum -a 256 "$PACKAGE_DIR/$relative_path" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "package checksum mismatch: $relative_path" >&2
        exit 1
    fi
done < <(jq -r '.files[] | [.sha256, .path] | @tsv' "$MANIFEST")

for forbidden_name in BIOS Roms Saves States backup.bin keymapv2.json '*.yss'; do
    if find "$PACKAGE_DIR" -mindepth 1 -name "$forbidden_name" -print -quit |
        grep -q .; then
        echo "mutable or user-provided content found: $forbidden_name" >&2
        exit 1
    fi
done

printf 'Verified MLP1 emulator package: %s files\n' \
    "$(jq '.files | length' "$MANIFEST")"

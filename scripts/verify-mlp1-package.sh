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
    "$PACKAGE_DIR/licenses/RELEASE-BLOCKED.txt" \
    "$PACKAGE_DIR/licenses/upstream-EULA.txt" \
    "$PACKAGE_DIR/provenance/build-manifest.json" \
    "$PACKAGE_DIR/provenance/build-flags.env" \
    "$PACKAGE_DIR/provenance/elf-dynamic.txt" \
    "$PACKAGE_DIR/provenance/patches.sha256" \
    "$MANIFEST"; do
    if [ ! -f "$required_path" ]; then
        echo "missing required probe package file: $required_path" >&2
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

bash -n "$PACKAGE_DIR/launch.sh"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$PACKAGE_DIR/defaults/es_temporaryinput.cfg"
fi
file "$PACKAGE_DIR/bin/yabasanshiro" |
    grep -q 'ELF 64-bit LSB.*ARM aarch64'

jq -e '
  .id == "yabasanshiro_standalone" and
  .platform == "mlp1" and
  .kind == "standalone-emulator-probe" and
  .distribution_status == "blocked-pending-gpl-eula-review" and
  .package_schema_version == 1 and
  .config_schema_version == 1 and
  (.files | type == "array" and length > 0)
' "$MANIFEST" >/dev/null

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

printf 'Verified internal MLP1 probe package: %s files\n' \
    "$(jq '.files | length' "$MANIFEST")"

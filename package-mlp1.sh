#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/output/mlp1/build"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output/mlp1/yabasanshiro}"
SOURCE_DIR="$ROOT_DIR/workdir/mlp1/yabause"
CMAKE_DIR="$ROOT_DIR/output/mlp1/cmake"

# shellcheck disable=SC1091
. "$ROOT_DIR/upstream.env"

SOURCE_ARCHIVE_NAME="yabasanshiro-standalone-${YABASANSHIRO_UPSTREAM_VERSION}-mlp1-source.tar.gz"
SOURCE_URL="${YABASANSHIRO_SOURCE_URL:-https://github.com/Utility-Muffin-Research-Kitchen/Yabasanshiro-standalone}"
SOURCE_SHA256="${YABASANSHIRO_SOURCE_SHA256:-}"
# The corresponding-source release this build's archive was published under, and
# the commit it was cut from. They are recorded separately from the URL so a
# source revision tag that differs from the Leaf release tag is unambiguous in
# the manifest rather than something a reader has to parse back out of a URL.
SOURCE_TAG="${YABASANSHIRO_SOURCE_TAG:-}"
SOURCE_COMMIT="${YABASANSHIRO_SOURCE_COMMIT:-}"
if [ -n "$SOURCE_SHA256" ] && [[ ! "$SOURCE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "invalid YABASANSHIRO_SOURCE_SHA256" >&2
    exit 1
fi
if [ -n "$SOURCE_COMMIT" ] && [[ ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "invalid YABASANSHIRO_SOURCE_COMMIT" >&2
    exit 1
fi
if [ -n "$SOURCE_TAG" ] && [[ "$SOURCE_TAG" == */* ]]; then
    echo "invalid YABASANSHIRO_SOURCE_TAG" >&2
    exit 1
fi

for command_name in jq shasum file; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing package command: $command_name" >&2
        exit 1
    fi
done

for required_path in \
    "$BUILD_DIR/bin/yabasanshiro" \
    "$BUILD_DIR/provenance/build-manifest.json" \
    "$ROOT_DIR/config/mlp1/launch.sh" \
    "$ROOT_DIR/config/mlp1/defaults/config.version" \
    "$ROOT_DIR/config/mlp1/defaults/es_temporaryinput.cfg" \
    "$ROOT_DIR/licenses/DISTRIBUTION-BASIS.md" \
    "$SOURCE_DIR/LICENSE" \
    "$SOURCE_DIR/yabause/COPYING.txt" \
    "$SOURCE_DIR/yabause/src/retro_arena/nanogui-sdl/LICENSE.txt" \
    "$SOURCE_DIR/yabause/src/retro_arena/pugixml/pugixml_license.txt" \
    "$CMAKE_DIR/src/retro_arena/Json/src/Json/LICENSE.MIT" \
    "$CMAKE_DIR/src/libchdr-prefix/src/libchdr/LICENSE.txt"; do
    if [ ! -f "$required_path" ]; then
        echo "missing required package input: $required_path" >&2
        exit 1
    fi
done

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/bin" "$OUTPUT_DIR/defaults" \
    "$OUTPUT_DIR/licenses" "$OUTPUT_DIR/provenance"

install -m 0755 "$BUILD_DIR/bin/yabasanshiro" \
    "$OUTPUT_DIR/bin/yabasanshiro"
install -m 0755 "$ROOT_DIR/config/mlp1/launch.sh" "$OUTPUT_DIR/launch.sh"
install -m 0644 "$ROOT_DIR/config/mlp1/defaults/config.version" \
    "$OUTPUT_DIR/defaults/config.version"
install -m 0644 "$ROOT_DIR/config/mlp1/defaults/es_temporaryinput.cfg" \
    "$OUTPUT_DIR/defaults/es_temporaryinput.cfg"
install -m 0644 "$ROOT_DIR/licenses/DISTRIBUTION-BASIS.md" \
    "$OUTPUT_DIR/licenses/DISTRIBUTION-BASIS.md"
install -m 0644 "$SOURCE_DIR/LICENSE" \
    "$OUTPUT_DIR/licenses/upstream-LICENSE.txt"
install -m 0644 "$SOURCE_DIR/yabause/COPYING.txt" \
    "$OUTPUT_DIR/licenses/Yabause-GPL-2.0.txt"
install -m 0644 "$SOURCE_DIR/yabause/src/retro_arena/nanogui-sdl/LICENSE.txt" \
    "$OUTPUT_DIR/licenses/NanoGUI-BSD-3-Clause.txt"
install -m 0644 "$SOURCE_DIR/yabause/src/retro_arena/pugixml/pugixml_license.txt" \
    "$OUTPUT_DIR/licenses/pugixml-MIT.txt"
install -m 0644 "$CMAKE_DIR/src/retro_arena/Json/src/Json/LICENSE.MIT" \
    "$OUTPUT_DIR/licenses/nlohmann-json-MIT.txt"
install -m 0644 "$CMAKE_DIR/src/libchdr-prefix/src/libchdr/LICENSE.txt" \
    "$OUTPUT_DIR/licenses/libchdr-BSD-3-Clause.txt"

cp -R "$BUILD_DIR/provenance/." "$OUTPUT_DIR/provenance/"

cat >"$OUTPUT_DIR/README.txt" <<EOF
YabaSanshiro standalone emulator for Leaf on MLP1.

This package contains no BIOS or game content. The GPL-covered program is
distributed under GPLv2 without imposing the conflicting upstream EULA. See
licenses/DISTRIBUTION-BASIS.md for the recorded distribution basis. RetroArch
remains the Saturn default; this standalone build is an optional faster route.

Corresponding source: $SOURCE_URL
Archive name: $SOURCE_ARCHIVE_NAME

The archive includes the exact patched source, dependency source, build
scripts, licences, provenance, and checksums used for this build.

The MLP1 port forces the native renderer and menu into the panel's landscape
orientation. HLE BIOS is still the default. Leaf's Saturn BIOS picker selects a
specific staged image and passes it as YABASANSHIRO_BIOS_FILE with
YABASANSHIRO_BIOS_MODE=external; that file is checked and used exactly as given,
and never copied or renamed. A direct caller that sets no file keeps the older
YABASANSHIRO_BIOS_MODE=hle|external|auto behavior over BIOS/saturn_bios.bin.
No BIOS is bundled, downloaded, or redistributed.

Configuration is private app data. Backup RAM is stored below
Saves/YabaSanshiro and native .yss states below States/YabaSanshiro for the
ROM source selected by Jawaka.

The physical Menu button opens YabaSanshiro's native menu. Down three times and
A chooses Exit and returns to Leaf.
EOF

config_version="$(tr -d '[:space:]' <"$OUTPUT_DIR/defaults/config.version")"
checksums_file="$(mktemp)"
trap 'rm -f "$checksums_file"' EXIT
(
    cd "$OUTPUT_DIR"
    find . -type f ! -path './manifest.json' -print | LC_ALL=C sort |
        while IFS= read -r relative_path; do
            relative_path="${relative_path#./}"
            checksum="$(shasum -a 256 "$relative_path" | awk '{print $1}')"
            printf '%s\t%s\n' "$checksum" "$relative_path"
        done
) >"$checksums_file"

files_json="$(
    jq -Rn '[inputs | split("\t") | {sha256: .[0], path: .[1]}]' \
        <"$checksums_file"
)"
jq \
    --argjson package_schema_version 1 \
    --argjson config_schema_version "$config_version" \
    --arg source_url "$SOURCE_URL" \
    --arg source_archive "$SOURCE_ARCHIVE_NAME" \
    --arg source_sha256 "$SOURCE_SHA256" \
    --arg source_tag "$SOURCE_TAG" \
    --arg source_commit "$SOURCE_COMMIT" \
    --argjson files "$files_json" \
    '. + {
      package_schema_version: $package_schema_version,
      config_schema_version: $config_schema_version,
      corresponding_source: {
        url: $source_url,
        archive: $source_archive,
        sha256: (if $source_sha256 == "" then null else $source_sha256 end),
        tag: (if $source_tag == "" then null else $source_tag end),
        commit: (if $source_commit == "" then null else $source_commit end)
      },
      files: $files
    }' "$BUILD_DIR/provenance/build-manifest.json" >"$OUTPUT_DIR/manifest.json"

"$ROOT_DIR/scripts/verify-mlp1-package.sh" "$OUTPUT_DIR"
printf 'Packaged MLP1 emulator: %s\n' "$OUTPUT_DIR"

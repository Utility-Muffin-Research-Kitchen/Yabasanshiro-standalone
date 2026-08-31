#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/output/mlp1/build"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output/mlp1/yabasanshiro}"
SOURCE_DIR="$ROOT_DIR/workdir/mlp1/yabause"
CMAKE_DIR="$ROOT_DIR/output/mlp1/cmake"

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

cat >"$OUTPUT_DIR/README.txt" <<'EOF'
YabaSanshiro standalone performance probe for Leaf on MLP1.

This package contains no BIOS or game content. The GPL-covered program is
distributed under GPLv2 without imposing the conflicting upstream EULA. See
licenses/DISTRIBUTION-BASIS.md for the recorded distribution basis. RetroArch
remains the Saturn default while the remaining technical and product gates are
evaluated.

The corresponding source is distributed as a separate
yabasanshiro-standalone-*-source.tar.gz archive beside this binary package.
It includes the exact patched source, dependency source, build scripts,
licences, provenance, and checksums used for this build.

The MLP1 port forces the native renderer and menu into the panel's landscape
orientation. HLE BIOS is the tested default; an external BIOS remains available
as an explicit YABASANSHIRO_BIOS_MODE=external compatibility override.

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
    --argjson files "$files_json" \
    '. + {
      package_schema_version: $package_schema_version,
      config_schema_version: $config_schema_version,
      files: $files
    }' "$BUILD_DIR/provenance/build-manifest.json" >"$OUTPUT_DIR/manifest.json"

"$ROOT_DIR/scripts/verify-mlp1-package.sh" "$OUTPUT_DIR"
printf 'Packaged MLP1 probe: %s\n' "$OUTPUT_DIR"

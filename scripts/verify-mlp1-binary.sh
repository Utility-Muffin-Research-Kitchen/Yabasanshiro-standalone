#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
TOOLCHAIN_IMAGE="${TOOLCHAIN_IMAGE:-ghcr.io/utility-muffin-research-kitchen/mlp1-toolchain:local}"
BINARY="${MLP1_BINARY:-$ROOT_DIR/output/mlp1/build/bin/yabasanshiro}"
PROVENANCE_DIR="$(dirname "$(dirname "$BINARY")")/provenance"

if [ ! -x "$BINARY" ]; then
    echo "missing MLP1 YabaSanshiro binary: $BINARY" >&2
    exit 1
fi

file "$BINARY"
file "$BINARY" | grep -q 'ELF 64-bit LSB.*ARM aarch64'

# The target-tool variables intentionally expand inside the container.
# shellcheck disable=SC2016
"$DOCKER" run --rm \
    -v "$ROOT_DIR":/build:ro \
    "$TOOLCHAIN_IMAGE" \
    bash -lc '
        set -euo pipefail
        binary=/build/output/mlp1/build/bin/yabasanshiro
        "$CROSS_TRIPLE-readelf" -h "$binary" >/tmp/yaba-elf-header
        "$CROSS_TRIPLE-readelf" -l "$binary" >/tmp/yaba-elf-program
        "$CROSS_TRIPLE-readelf" -d "$binary" >/tmp/yaba-elf-dynamic
        "$CROSS_TRIPLE-nm" -C "$binary" >/tmp/yaba-symbols
        grep -q "Machine:.*AArch64" /tmp/yaba-elf-header
        grep -q "/lib/ld-linux-aarch64.so.1" /tmp/yaba-elf-program
        ! grep -Eq "RPATH|RUNPATH" /tmp/yaba-elf-dynamic
        grep -q "DynarecSh2" /tmp/yaba-symbols
    '

expected_dependencies="$(mktemp)"
actual_dependencies="$(mktemp)"
trap 'rm -f "$expected_dependencies" "$actual_dependencies"' EXIT

cat >"$expected_dependencies" <<'EOF'
ld-linux-aarch64.so.1
libEGL.so.1
libGLESv2.so.2
libSDL2-2.0.so.0
libc.so.6
libgcc_s.so.1
libm.so.6
libpng16.so.16
libstdc++.so.6
libz.so.1
EOF

awk -F'[][]' '/Shared library:/ { print $2 }' \
    "$PROVENANCE_DIR/elf-dynamic.txt" | LC_ALL=C sort >"$actual_dependencies"
if ! diff -u "$expected_dependencies" "$actual_dependencies"; then
    echo "unexpected direct dynamic dependency" >&2
    exit 1
fi

if grep -Eiq 'openal|boost|libx11|wayland|qt|glfw' "$actual_dependencies"; then
    echo "desktop-only dependency leaked into the binary" >&2
    exit 1
fi
if strings "$BINARY" | grep -Eq '/build/|/Volumes/|workdir/'; then
    echo "host build path leaked into the binary" >&2
    exit 1
fi

if command -v adb >/dev/null 2>&1; then
    if [ -n "${ADB_SERIAL:-}" ]; then
        serial="$ADB_SERIAL"
    else
        serial="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
    fi
    if [ -n "$serial" ]; then
        remote=/data/local/tmp/umrk-yabasanshiro-abi-check
        adb -s "$serial" push "$BINARY" "$remote" >/dev/null
        adb -s "$serial" shell \
            "chmod 755 '$remote' && LD_TRACE_LOADED_OBJECTS=1 '$remote'"
        adb -s "$serial" shell "rm -f '$remote'"
    fi
fi

printf 'Verified dependency-clean MLP1 binary: %s\n' \
    "$(shasum -a 256 "$BINARY" | awk '{print $1}')"

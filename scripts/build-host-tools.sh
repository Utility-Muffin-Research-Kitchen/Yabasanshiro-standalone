#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/workdir/mlp1/yabause"
OUTPUT_DIR="$ROOT_DIR/workdir/mlp1/host-tools"
DOCKER="${DOCKER:-docker}"
HOST_TOOLS_IMAGE="${HOST_TOOLS_IMAGE:-gcc@sha256:3e239a5ea77200b9163c825a0a5ebc17ca99f3bbb4d08241ee0fb9c174325880}"

if [ ! -f "$SOURCE_DIR/yabause/src/musashi/m68kmake.c" ]; then
    echo "missing fetched source; run scripts/fetch-upstream.sh" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

"$DOCKER" run --rm --platform linux/arm64 \
    -v "$ROOT_DIR":/build \
    -w /build \
    "$HOST_TOOLS_IMAGE" \
    sh -lc '
        set -eu
        cc -O2 -o /build/workdir/mlp1/host-tools/m68kmake \
            /build/workdir/mlp1/yabause/yabause/src/musashi/m68kmake.c
        cc -O2 -o /build/workdir/mlp1/host-tools/bin2c \
            /build/workdir/mlp1/yabause/yabause/src/retro_arena/nanogui-sdl/resources/bin2c.c
        cc --version > /build/workdir/mlp1/host-tools/cc-version.txt
    '

host_image_id="$("$DOCKER" image inspect "$HOST_TOOLS_IMAGE" --format '{{.Id}}')"
printf '%s\n' "$HOST_TOOLS_IMAGE" >"$OUTPUT_DIR/image.txt"
printf '%s\n' "$host_image_id" >"$OUTPUT_DIR/image-id.txt"

for tool_path in "$OUTPUT_DIR/m68kmake" "$OUTPUT_DIR/bin2c"; do
    file "$tool_path" | grep -q 'ELF 64-bit LSB.*ARM aarch64'
done

printf 'Built pinned Linux/AArch64 host generators: %s\n' "$host_image_id"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER="${DOCKER:-docker}"
TOOLCHAIN_IMAGE="${TOOLCHAIN_IMAGE:-ghcr.io/utility-muffin-research-kitchen/mlp1-toolchain:local}"
HOST_TOOLS_IMAGE="${HOST_TOOLS_IMAGE:-gcc@sha256:3e239a5ea77200b9163c825a0a5ebc17ca99f3bbb4d08241ee0fb9c174325880}"
BUILD_JOBS="${BUILD_JOBS:-}"
MLP1_BUILD_PROFILE="${MLP1_BUILD_PROFILE:-perf}"
FLAGS_DIR="${MLP1_FLAGS_DIR:-}"
SOURCE_DIR="$ROOT_DIR/workdir/mlp1/yabause"
ARTIFACT_DIR="$ROOT_DIR/output/mlp1/build"

for command_name in git jq shasum; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing build command: $command_name" >&2
        exit 1
    fi
done
if [ -z "$FLAGS_DIR" ]; then
    for candidate in \
        "$ROOT_DIR/../mlp1-toolchain/flags" \
        "$ROOT_DIR/../../mlp1-toolchain/flags"; do
        if [ -f "$candidate/mlp1-build-flags.env" ]; then
            FLAGS_DIR="$candidate"
            break
        fi
    done
fi
if [ ! -f "${FLAGS_DIR:-}/mlp1-build-flags.env" ]; then
    echo "missing shared MLP1 flags: $FLAGS_DIR/mlp1-build-flags.env" >&2
    exit 1
fi
if ! "$DOCKER" image inspect "$TOOLCHAIN_IMAGE" >/dev/null 2>&1; then
    echo "missing Docker image: $TOOLCHAIN_IMAGE" >&2
    echo "build it with: make -C ../mlp1-toolchain image" >&2
    exit 1
fi

"$ROOT_DIR/scripts/fetch-upstream.sh"
DOCKER="$DOCKER" HOST_TOOLS_IMAGE="$HOST_TOOLS_IMAGE" \
    "$ROOT_DIR/scripts/build-host-tools.sh"

mkdir -p "$ROOT_DIR/output/mlp1"
"$DOCKER" run --rm \
    -v "$ROOT_DIR":/build \
    -v "$FLAGS_DIR":/umrk-flags:ro \
    -w /build \
    -e BUILD_JOBS="$BUILD_JOBS" \
    -e MLP1_BUILD_PROFILE="$MLP1_BUILD_PROFILE" \
    "$TOOLCHAIN_IMAGE" \
    bash /build/scripts/build-mlp1-in-docker.sh

# shellcheck disable=SC1091
. "$ROOT_DIR/upstream.env"

source_sha="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
source_date_epoch="$(git -C "$SOURCE_DIR" show -s --format=%ct HEAD)"
binary="$ARTIFACT_DIR/bin/yabasanshiro"
binary_sha="$(shasum -a 256 "$binary" | awk '{print $1}')"
if binary_size="$(stat -f '%z' "$binary" 2>/dev/null)"; then
    :
else
    binary_size="$(stat -c '%s' "$binary")"
fi
toolchain_image_id="$("$DOCKER" image inspect "$TOOLCHAIN_IMAGE" --format '{{.Id}}')"
host_image_id="$(tr -d '\r\n' <"$ROOT_DIR/workdir/mlp1/host-tools/image-id.txt")"
dynamic_dependencies="$(
    awk -F'[][]' '/Shared library:/ { print $2 }' \
        "$ARTIFACT_DIR/provenance/elf-dynamic.txt" |
        jq -Rsc 'split("\n") | map(select(length > 0))'
)"
patches="$(
    awk '{ print $1 "\t" $2 "\tnot-submitted" }' \
        "$ARTIFACT_DIR/provenance/patches.sha256" |
        jq -Rsc '
          split("\n") |
          map(select(length > 0) | split("\t") | {
            sha256: .[0], path: .[1], upstream_status: .[2]
          })
        '
)"
submodules="$(
    sed 's/^[ +-]//' "$ARTIFACT_DIR/provenance/submodules.txt" |
        jq -Rsc 'split("\n") | map(select(length > 0))'
)"

jq -n \
    --arg id "yabasanshiro_standalone" \
    --arg upstream_url "$YABASANSHIRO_UPSTREAM_URL" \
    --arg upstream_branch "$YABASANSHIRO_UPSTREAM_BRANCH" \
    --arg upstream_version "$YABASANSHIRO_UPSTREAM_VERSION" \
    --arg upstream_sha "$source_sha" \
    --argjson source_date_epoch "$source_date_epoch" \
    --arg toolchain_image "$TOOLCHAIN_IMAGE" \
    --arg toolchain_image_id "$toolchain_image_id" \
    --arg host_tools_image "$HOST_TOOLS_IMAGE" \
    --arg host_tools_image_id "$host_image_id" \
    --arg build_profile "$MLP1_BUILD_PROFILE" \
    --arg binary_sha256 "$binary_sha" \
    --argjson binary_size "$binary_size" \
    --argjson dynamic_dependencies "$dynamic_dependencies" \
    --argjson patches "$patches" \
    --argjson submodules "$submodules" \
    '{
      id: $id,
      name: "YabaSanshiro Standalone",
      platform: "mlp1",
      kind: "standalone-emulator-probe",
      upstream_url: $upstream_url,
      upstream_branch: $upstream_branch,
      upstream_version: $upstream_version,
      upstream_sha: $upstream_sha,
      source_date_epoch: $source_date_epoch,
      toolchain_image: $toolchain_image,
      toolchain_image_id: $toolchain_image_id,
      host_tools_image: $host_tools_image,
      host_tools_image_id: $host_tools_image_id,
      target_soc: "rk3566",
      target_cpu: "cortex-a55",
      build_profile: $build_profile,
      frontend: "retro_arena",
      renderer: "opengles3-egl",
      dynarec: "devmiyax-aarch64",
      sound: "sdl2",
      hle_bios_supported: true,
      binary: "bin/yabasanshiro",
      binary_sha256: $binary_sha256,
      binary_size: $binary_size,
      dynamic_dependencies: $dynamic_dependencies,
      patches: $patches,
      submodules: $submodules,
      timestamp_policy: "SOURCE_DATE_EPOCH equals the pinned source commit time; no wall-clock timestamp is recorded",
      distribution_status: "blocked-pending-gpl-eula-review"
    }' >"$ARTIFACT_DIR/provenance/build-manifest.json"

printf 'Built YabaSanshiro %s for MLP1: %s\n' \
    "$YABASANSHIRO_UPSTREAM_VERSION" "$binary_sha"

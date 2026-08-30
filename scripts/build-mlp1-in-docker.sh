#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=/build/workdir/mlp1/yabause
SOURCE_ROOT=$SOURCE_DIR/yabause
HOST_TOOLS_DIR=/build/workdir/mlp1/host-tools
BUILD_DIR=/build/output/mlp1/cmake
ARTIFACT_DIR=/build/output/mlp1/build

# shellcheck source=/dev/null
. /umrk-flags/mlp1-build-flags.env

jobs="${BUILD_JOBS:-}"
if [ -z "$jobs" ]; then
    jobs="$(nproc)"
fi

SOURCE_DATE_EPOCH="$(git -C "$SOURCE_DIR" show -s --format=%ct HEAD)"
export SOURCE_DATE_EPOCH

rm -rf "$BUILD_DIR" "$ARTIFACT_DIR"
mkdir -p "$BUILD_DIR" "$ARTIFACT_DIR/bin" "$ARTIFACT_DIR/provenance"

/usr/bin/cmake -S "$SOURCE_ROOT" -B "$BUILD_DIR" --fresh \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$UMRK_MLP1_PROFILE_CFLAGS -D_GNU_SOURCE" \
    -DCMAKE_CXX_FLAGS="$UMRK_MLP1_PROFILE_CXXFLAGS -D_GNU_SOURCE" \
    -DCMAKE_EXE_LINKER_FLAGS="$UMRK_MLP1_PROFILE_LDFLAGS" \
    -DCMAKE_PROJECT_INCLUDE="$SOURCE_ROOT/src/retro_arena/n2.cmake" \
    -DCMAKE_SKIP_RPATH=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DYAB_PORTS=retro_arena \
    -DYAB_WANT_DYNAREC_DEVMIYAX=ON \
    -DYAB_WANT_ARM7=ON \
    -DYAB_WANT_OPENGL=ON \
    -DYAB_WANT_OPENAL=OFF \
    -DYAB_WANT_VULKAN=OFF \
    -DUSE_EGL=ON \
    -DSH2_TRACE=OFF \
    -DYAB_USE_SSF=OFF \
    -DYABASANSHIRO_HOST_M68KMAKE="$HOST_TOOLS_DIR/m68kmake" \
    -DYABASANSHIRO_HOST_BIN2C="$HOST_TOOLS_DIR/bin2c"

/usr/bin/cmake --build "$BUILD_DIR" --parallel "$jobs"
install -m 0755 "$BUILD_DIR/src/retro_arena/yabasanshiro" \
    "$ARTIFACT_DIR/bin/yabasanshiro"

/usr/bin/cmake -LAH -N "$BUILD_DIR" >"$ARTIFACT_DIR/provenance/cmake-cache.txt"
git -C "$SOURCE_DIR" submodule status --recursive \
    >"$ARTIFACT_DIR/provenance/submodules.txt"
find /build/patches -maxdepth 1 -type f -name '*.patch' -print0 |
    LC_ALL=C sort -z |
    while IFS= read -r -d '' patch_path; do
        printf '%s  %s\n' \
            "$(sha256sum "$patch_path" | awk '{print $1}')" \
            "${patch_path#/build/}"
    done >"$ARTIFACT_DIR/provenance/patches.sha256"

"$CC" --version >"$ARTIFACT_DIR/provenance/cc-version.txt"
"$CXX" --version >"$ARTIFACT_DIR/provenance/cxx-version.txt"
/usr/bin/cmake --version >"$ARTIFACT_DIR/provenance/cmake-version.txt"
"$CROSS_TRIPLE-readelf" -h "$ARTIFACT_DIR/bin/yabasanshiro" \
    >"$ARTIFACT_DIR/provenance/elf-header.txt"
"$CROSS_TRIPLE-readelf" -d "$ARTIFACT_DIR/bin/yabasanshiro" \
    >"$ARTIFACT_DIR/provenance/elf-dynamic.txt"
"$CROSS_TRIPLE-readelf" --version-info "$ARTIFACT_DIR/bin/yabasanshiro" \
    >"$ARTIFACT_DIR/provenance/elf-version-info.txt"

sha256sum "$HOST_TOOLS_DIR/m68kmake" "$HOST_TOOLS_DIR/bin2c" \
    >"$ARTIFACT_DIR/provenance/host-tools.sha256"
cp "$HOST_TOOLS_DIR/cc-version.txt" \
    "$ARTIFACT_DIR/provenance/host-cc-version.txt"
cp "$HOST_TOOLS_DIR/image.txt" "$ARTIFACT_DIR/provenance/host-image.txt"
cp "$HOST_TOOLS_DIR/image-id.txt" "$ARTIFACT_DIR/provenance/host-image-id.txt"

cat >"$ARTIFACT_DIR/provenance/build-flags.env" <<EOF
UMRK_MLP1_BUILD_PROFILE=$UMRK_MLP1_BUILD_PROFILE
UMRK_MLP1_TARGET_SOC=$UMRK_MLP1_TARGET_SOC
UMRK_MLP1_TARGET_CPU=$UMRK_MLP1_TARGET_CPU
UMRK_MLP1_PROFILE_CFLAGS=$UMRK_MLP1_PROFILE_CFLAGS
UMRK_MLP1_PROFILE_CXXFLAGS=$UMRK_MLP1_PROFILE_CXXFLAGS
UMRK_MLP1_PROFILE_LDFLAGS=$UMRK_MLP1_PROFILE_LDFLAGS
SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH
EOF

cat >"$ARTIFACT_DIR/provenance/configure-options.txt" <<'EOF'
YAB_PORTS=retro_arena
YAB_WANT_DYNAREC_DEVMIYAX=ON
YAB_WANT_ARM7=ON
YAB_WANT_OPENGL=ON
YAB_WANT_OPENAL=OFF
YAB_WANT_VULKAN=OFF
USE_EGL=ON
SH2_TRACE=OFF
YAB_USE_SSF=OFF
CMAKE_SKIP_RPATH=ON
EOF

cat >"$ARTIFACT_DIR/provenance/external-dependencies.txt" <<'EOF'
nlohmann/json 359f98d14065bf4e53eeb274f5987fd08f16e5bf
devmiyax/libchdr 074ff1614f2a685f2b5a95b0e788bff6297d5680
EOF

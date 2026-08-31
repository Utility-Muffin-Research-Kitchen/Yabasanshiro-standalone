# YabaSanshiro standalone for Leaf

This repository builds the non-libretro `retro_arena` YabaSanshiro frontend for
the Miniloong Pocket 1 (RK3566/Cortex-A55). The reference probe is pinned to the
revision carried by ROCKNIX and builds with the shared UMRK MLP1 toolchain,
GLES 3, SDL2, and the AArch64 devMiyax dynarec.

```sh
make build-mlp1
make verify-mlp1
make package-release
```

`workdir/` contains the ignored, patched upstream checkout. Build products and
provenance are written below `output/mlp1/`.

`make package-release` produces both the MLP1 binary package and a GPL source
archive. The source archive contains the exact patched upstream tree, recursive
submodules, the pinned nlohmann/json and libchdr sources, this repository's
build and packaging code, build provenance, licence texts, and `SHA256SUMS`.
Publish that archive and its `.sha256` file beside every binary download; the
public repository alone is not treated as the release's self-contained source
artifact.

The MLP1 wrapper forces YabaSanshiro's native 90-degree gameplay rotation and
uses a small NanoGUI-only transform for the native menu. Normal gameplay does
not incur a framebuffer rotation copy. HLE BIOS is the default because the
pinned reference revision black-screens Shining Force III with the tested
external BIOS; set `YABASANSHIRO_BIOS_MODE=external` for an explicit
compatibility test.

Configuration stays below `$USERDATA_PATH/yabasanshiro`; the wrapper exports
the source patch's backup and state overrides so `backup.bin` is written to
`$SAVES_PATH/YabaSanshiro` and native `.yss` files to
`$STATES_PATH/YabaSanshiro`.

This remains a performance probe and RetroArch remains Leaf's default Saturn
emulator. The release owner has approved distribution of the GPL-covered
program under GPLv2 without imposing the conflicting upstream EULA; see
`licenses/DISTRIBUTION-BASIS.md`. Publication still depends on the remaining
source/asset inventory, technical, and product gates.

The MIT license in this repository covers UMRK's build and packaging code, not
the separately fetched emulator source or the resulting binary.

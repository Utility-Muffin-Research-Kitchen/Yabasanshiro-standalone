# YabaSanshiro standalone for Leaf

This repository builds the non-libretro `retro_arena` YabaSanshiro frontend for
the Miniloong Pocket 1 (RK3566/Cortex-A55). The reference probe is pinned to the
revision carried by ROCKNIX and builds with the shared UMRK MLP1 toolchain,
GLES 3, SDL2, and the AArch64 devMiyax dynarec.

```sh
make build-mlp1
make verify-mlp1
```

`workdir/` contains the ignored, patched upstream checkout. Build products and
provenance are written below `output/mlp1/`.

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

This is currently an internal performance probe. Public binary distribution is
blocked while the upstream GPL/EULA ambiguity is reviewed; see `licenses/`.
The MIT license in this repository covers UMRK's build and packaging code, not
the separately fetched emulator source or the resulting binary.

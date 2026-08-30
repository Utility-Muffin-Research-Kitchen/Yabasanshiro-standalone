#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PACKAGE_DIR="$TMP_ROOT/package with spaces"
SDCARD_PATH_TEST="$TMP_ROOT/sd card's root"
USERDATA_PATH_TEST="$SDCARD_PATH_TEST/.userdata/mlp1"
BIOS_PATH_TEST="$SDCARD_PATH_TEST/BIOS"
LOGS_PATH_TEST="$USERDATA_PATH_TEST/logs"
RUNTIME_PATH_TEST="$TMP_ROOT/runtime root"
ROM_PATH="$SDCARD_PATH_TEST/Roms/SATURN/Shining Force III's \${cash}; [USA], v1.chd"

mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/defaults" \
    "$(dirname "$ROM_PATH")" "$BIOS_PATH_TEST"
cp "$ROOT_DIR/config/mlp1/launch.sh" "$PACKAGE_DIR/launch.sh"
cp "$ROOT_DIR/config/mlp1/defaults/config.version" "$PACKAGE_DIR/defaults/"
cp "$ROOT_DIR/config/mlp1/defaults/es_temporaryinput.cfg" "$PACKAGE_DIR/defaults/"
touch "$ROM_PATH" "$BIOS_PATH_TEST/saturn_bios.bin"

cat >"$PACKAGE_DIR/bin/yabasanshiro" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for name in HOME TMPDIR SDL_VIDEODRIVER SDL_KMSDRM_REQUIRE_DRM_MASTER \
    SDL_AUDIODRIVER PULSE_SERVER; do
    printf '%s=<%s>\n' "$name" "${!name-}"
done
index=0
for argument in "$@"; do
    printf 'arg_%d=<%s>\n' "$index" "$argument"
    index=$((index + 1))
done
EOF
chmod 0755 "$PACKAGE_DIR/bin/yabasanshiro" "$PACKAGE_DIR/launch.sh"

run_wrapper() {
    env -u UMRK_ENV_FILE \
        PLATFORM=mlp1 \
        SDCARD_PATH="$SDCARD_PATH_TEST" \
        USERDATA_PATH="$USERDATA_PATH_TEST" \
        BIOS_PATH="$BIOS_PATH_TEST" \
        LOGS_PATH="$LOGS_PATH_TEST" \
        UMRK_RUNTIME_PATH="$RUNTIME_PATH_TEST" \
        JAWAKA_INPUT_ROSTER_COUNT=1 \
        JAWAKA_RETROARCH_JOYPAD_INDEX=0 \
        "$PACKAGE_DIR/launch.sh" "$ROM_PATH"
}

run_wrapper
APP_STATE_ROOT="$USERDATA_PATH_TEST/yabasanshiro/probe-sr0"
LOG_FILE="$LOGS_PATH_TEST/yabasanshiro/sr0.log"
for expected_path in \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" \
    "$APP_STATE_ROOT/.umrk-defaults-version" \
    "$LOG_FILE"; do
    if [ ! -f "$expected_path" ]; then
        echo "wrapper did not create expected file: $expected_path" >&2
        exit 1
    fi
done

grep -F "HOME=<$APP_STATE_ROOT/home>" "$LOG_FILE" >/dev/null
grep -F 'SDL_VIDEODRIVER=<kmsdrm>' "$LOG_FILE" >/dev/null
grep -F 'SDL_KMSDRM_REQUIRE_DRM_MASTER=<1>' "$LOG_FILE" >/dev/null
grep -F 'SDL_AUDIODRIVER=<pulseaudio>' "$LOG_FILE" >/dev/null
grep -F 'arg_0=<-r>' "$LOG_FILE" >/dev/null
grep -F 'arg_1=<3>' "$LOG_FILE" >/dev/null
grep -F 'arg_2=<-i>' "$LOG_FILE" >/dev/null
grep -F "arg_3=<$ROM_PATH>" "$LOG_FILE" >/dev/null
grep -F 'arg_4=<-b>' "$LOG_FILE" >/dev/null
grep -F "arg_5=<$BIOS_PATH_TEST/saturn_bios.bin>" "$LOG_FILE" >/dev/null

printf '\n<!-- user edit -->\n' >>\
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg"
input_sha_before="$(shasum -a 256 \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" | awk '{print $1}')"
run_wrapper
input_sha_after="$(shasum -a 256 \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" | awk '{print $1}')"
if [ "$input_sha_before" != "$input_sha_after" ]; then
    echo "wrapper overwrote a user-edited input config" >&2
    exit 1
fi

if env -u UMRK_ENV_FILE \
    PLATFORM=mlp1 \
    SDCARD_PATH="$SDCARD_PATH_TEST" \
    USERDATA_PATH="$USERDATA_PATH_TEST" \
    BIOS_PATH="$BIOS_PATH_TEST" \
    LOGS_PATH="$LOGS_PATH_TEST" \
    UMRK_RUNTIME_PATH="$RUNTIME_PATH_TEST" \
    JAWAKA_INPUT_ROSTER_COUNT=2 \
    JAWAKA_RETROARCH_JOYPAD_INDEX=1 \
    "$PACKAGE_DIR/launch.sh" "$ROM_PATH" >/dev/null 2>&1; then
    echo "wrapper accepted an unstable multi-controller probe roster" >&2
    exit 1
fi

if "$PACKAGE_DIR/launch.sh" "$TMP_ROOT/missing.chd" >/dev/null 2>&1; then
    echo "wrapper accepted a missing ROM" >&2
    exit 1
fi

printf 'Verified probe wrapper quoting, input seed, roster, and BIOS policy\n'

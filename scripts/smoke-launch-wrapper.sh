#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PACKAGE_DIR="$TMP_ROOT/package with spaces"
SDCARD_PATH_TEST="$TMP_ROOT/sd card's root"
USERDATA_PATH_TEST="$SDCARD_PATH_TEST/.userdata/mlp1"
SAVES_PATH_TEST="$SDCARD_PATH_TEST/Saves"
STATES_PATH_TEST="$SDCARD_PATH_TEST/States"
BIOS_PATH_TEST="$SDCARD_PATH_TEST/BIOS"
SATURN_BIOS_DIR="$BIOS_PATH_TEST/SATURN"
LOGS_PATH_TEST="$USERDATA_PATH_TEST/logs"
RUNTIME_PATH_TEST="$TMP_ROOT/runtime root"
ROM_PATH="$SDCARD_PATH_TEST/Roms/SATURN/Shining Force III's \${cash}; [USA], v1.chd"

mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/defaults" \
    "$(dirname "$ROM_PATH")" "$SATURN_BIOS_DIR"
cp "$ROOT_DIR/config/mlp1/launch.sh" "$PACKAGE_DIR/launch.sh"
cp "$ROOT_DIR/config/mlp1/defaults/config.version" "$PACKAGE_DIR/defaults/"
cp "$ROOT_DIR/config/mlp1/defaults/es_temporaryinput.cfg" "$PACKAGE_DIR/defaults/"
touch "$ROM_PATH" "$SATURN_BIOS_DIR/saturn_bios.bin" \
    "$BIOS_PATH_TEST/saturn_bios.bin"

cat >"$PACKAGE_DIR/bin/yabasanshiro" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for name in HOME TMPDIR SDL_VIDEODRIVER SDL_KMSDRM_REQUIRE_DRM_MASTER \
    SDL_AUDIODRIVER PULSE_SERVER YABASANSHIRO_BACKUP_PATH \
    YABASANSHIRO_STATE_DIR YABASANSHIRO_MLP1_ROTATE_90; do
    printf '%s=<%s>\n' "$name" "${!name-}"
done
index=0
for argument in "$@"; do
    printf 'arg_%d=<%s>\n' "$index" "$argument"
    index=$((index + 1))
done
EOF
chmod 0755 "$PACKAGE_DIR/bin/yabasanshiro" "$PACKAGE_DIR/launch.sh"

APP_STATE_ROOT="$USERDATA_PATH_TEST/yabasanshiro"
mkdir -p "$APP_STATE_ROOT/home/.emulationstation"
cp "$PACKAGE_DIR/defaults/es_temporaryinput.cfg" \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg"
legacy_input="$TMP_ROOT/legacy-es_temporaryinput.cfg"
sed 's/name="select"        type="button" id="10"/name="select"        type="button" id="8"/' \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" >"$legacy_input"
mv "$legacy_input" "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg"
printf '\n<!-- edited v1 config -->\n' >>\
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg"
printf '1\n' >"$APP_STATE_ROOT/.umrk-defaults-version"

# Any NAME=VALUE arguments are handed to env verbatim, so a case can set the
# BIOS contract variables -- or deliberately leave one unset.
run_wrapper() {
    local -a bios_env=("$@")
    env -u UMRK_ENV_FILE \
        PLATFORM=mlp1 \
        SDCARD_PATH="$SDCARD_PATH_TEST" \
        USERDATA_PATH="$USERDATA_PATH_TEST" \
        SAVES_PATH="$SAVES_PATH_TEST" \
        STATES_PATH="$STATES_PATH_TEST" \
        BIOS_PATH="$BIOS_PATH_TEST" \
        LOGS_PATH="$LOGS_PATH_TEST" \
        UMRK_RUNTIME_PATH="$RUNTIME_PATH_TEST" \
        JAWAKA_INPUT_ROSTER_COUNT=1 \
        JAWAKA_RETROARCH_JOYPAD_INDEX=0 \
        "${bios_env[@]}" \
        "$PACKAGE_DIR/launch.sh" "$ROM_PATH"
}

run_wrapper
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

grep -F 'name="select"        type="button" id="10"' \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" >/dev/null
grep -F '<!-- edited v1 config -->' \
    "$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg" >/dev/null
grep -Fx '2' "$APP_STATE_ROOT/.umrk-defaults-version" >/dev/null

for expected_dir in \
    "$SAVES_PATH_TEST/YabaSanshiro" \
    "$STATES_PATH_TEST/YabaSanshiro"; do
    if [ ! -d "$expected_dir" ]; then
        echo "wrapper did not create expected directory: $expected_dir" >&2
        exit 1
    fi
done

grep -F "HOME=<$APP_STATE_ROOT/home>" "$LOG_FILE" >/dev/null
grep -F 'SDL_VIDEODRIVER=<kmsdrm>' "$LOG_FILE" >/dev/null
grep -F 'SDL_KMSDRM_REQUIRE_DRM_MASTER=<1>' "$LOG_FILE" >/dev/null
grep -F 'SDL_AUDIODRIVER=<pulseaudio>' "$LOG_FILE" >/dev/null
grep -F "YABASANSHIRO_BACKUP_PATH=<$SAVES_PATH_TEST/YabaSanshiro/backup.bin>" \
    "$LOG_FILE" >/dev/null
grep -F "YABASANSHIRO_STATE_DIR=<$STATES_PATH_TEST/YabaSanshiro>" \
    "$LOG_FILE" >/dev/null
grep -F 'YABASANSHIRO_MLP1_ROTATE_90=<1>' "$LOG_FILE" >/dev/null
grep -F 'rotation=mlp1-native-90' "$LOG_FILE" >/dev/null
grep -F 'resolution_cli_default=original' "$LOG_FILE" >/dev/null
grep -F 'bios_mode=hle' "$LOG_FILE" >/dev/null
grep -F "backup_path=$SAVES_PATH_TEST/YabaSanshiro/backup.bin" "$LOG_FILE" >/dev/null
grep -F "state_dir=$STATES_PATH_TEST/YabaSanshiro" "$LOG_FILE" >/dev/null
grep -F 'arg_0=<-r>' "$LOG_FILE" >/dev/null
grep -F 'arg_1=<3>' "$LOG_FILE" >/dev/null
grep -F 'arg_2=<-i>' "$LOG_FILE" >/dev/null
grep -F "arg_3=<$ROM_PATH>" "$LOG_FILE" >/dev/null
if grep -F 'arg_4=<' "$LOG_FILE" >/dev/null ||
   grep -F 'bios_path=' "$LOG_FILE" >/dev/null; then
    echo "default HLE launch unexpectedly selected an external BIOS" >&2
    exit 1
fi

run_wrapper YABASANSHIRO_BIOS_MODE=external
grep -F 'arg_4=<-b>' "$LOG_FILE" >/dev/null
grep -F "arg_5=<$SATURN_BIOS_DIR/saturn_bios.bin>" "$LOG_FILE" >/dev/null
grep -F "bios_path=$SATURN_BIOS_DIR/saturn_bios.bin" "$LOG_FILE" >/dev/null
grep -F 'bios_source=standard' "$LOG_FILE" >/dev/null

# auto is legacy-caller-only: present here, never produced by the Leaf picker.
run_wrapper YABASANSHIRO_BIOS_MODE=auto
grep -F "bios_path=$SATURN_BIOS_DIR/saturn_bios.bin" "$LOG_FILE" >/dev/null
grep -F 'bios_source=standard' "$LOG_FILE" >/dev/null

# ── Explicit selected-file contract (the Leaf picker's caller shape) ────────
# A regional, non-standard name in a subfolder, carrying spaces, quotes and
# shell metacharacters. It must reach the emulator as one unchanged argument.
SELECTED_DIR="$SATURN_BIOS_DIR/Saturn's dumps"
SELECTED_BIOS="$SELECTED_DIR/Sega Saturn BIOS \$(reboot) \`x\` ;rm -rf [JP].bin"
OTHER_BIOS="$SELECTED_DIR/Sega Saturn BIOS [EU].bin"
mkdir -p "$SELECTED_DIR"
for image in "$SELECTED_BIOS" "$OTHER_BIOS"; do
    dd if=/dev/zero of="$image" bs=1024 count=512 status=none
done

run_wrapper YABASANSHIRO_BIOS_MODE=external \
    YABASANSHIRO_BIOS_FILE="$SELECTED_BIOS"
grep -F 'arg_4=<-b>' "$LOG_FILE" >/dev/null
grep -F "arg_5=<$SELECTED_BIOS>" "$LOG_FILE" >/dev/null
grep -F 'bios_mode=external' "$LOG_FILE" >/dev/null
grep -F 'bios_source=explicit' "$LOG_FILE" >/dev/null
grep -F "bios_path=$SELECTED_BIOS" "$LOG_FILE" >/dev/null
if grep -F 'arg_6=<' "$LOG_FILE" >/dev/null; then
    echo "explicit BIOS selection added stray emulator arguments" >&2
    exit 1
fi
if [ ! -f "$SELECTED_BIOS" ]; then
    echo "wrapper moved or renamed the user's BIOS file" >&2
    exit 1
fi
# A valid explicit file wins over the standard filename, which is still staged.
if grep -F "arg_5=<$SATURN_BIOS_DIR/saturn_bios.bin>" "$LOG_FILE" >/dev/null; then
    echo "explicit BIOS selection lost to the legacy standard filename" >&2
    exit 1
fi

# Two consecutive launches with different choices: no state carries over.
run_wrapper YABASANSHIRO_BIOS_MODE=external \
    YABASANSHIRO_BIOS_FILE="$OTHER_BIOS"
grep -F "arg_5=<$OTHER_BIOS>" "$LOG_FILE" >/dev/null
if grep -F "$SELECTED_BIOS" "$LOG_FILE" >/dev/null; then
    echo "a previous BIOS selection leaked into the next launch" >&2
    exit 1
fi

# Explicit HLE clears a previous file: no FILE, no -b, no bios_path.
run_wrapper YABASANSHIRO_BIOS_MODE=hle
grep -F 'bios_mode=hle' "$LOG_FILE" >/dev/null
if grep -F 'arg_4=<' "$LOG_FILE" >/dev/null ||
   grep -F 'bios_path=' "$LOG_FILE" >/dev/null; then
    echo "explicit HLE still passed a BIOS file" >&2
    exit 1
fi

expect_rejected() {
    local description="$1"
    local expected_status="$2"
    shift 2
    local status=0
    run_wrapper "$@" >/dev/null 2>&1 || status=$?
    if [ "$status" -ne "$expected_status" ]; then
        echo "wrapper did not reject $description (exit $status)" >&2
        exit 1
    fi
}

expect_rejected "an empty explicit BIOS path" 2 \
    YABASANSHIRO_BIOS_MODE=external YABASANSHIRO_BIOS_FILE=
expect_rejected "an explicit BIOS path with a conflicting HLE mode" 2 \
    YABASANSHIRO_BIOS_MODE=hle YABASANSHIRO_BIOS_FILE="$SELECTED_BIOS"
expect_rejected "an explicit BIOS path with no mode at all" 2 \
    YABASANSHIRO_BIOS_FILE="$SELECTED_BIOS"
expect_rejected "a removed explicit BIOS file" 1 \
    YABASANSHIRO_BIOS_MODE=external \
    YABASANSHIRO_BIOS_FILE="$SELECTED_DIR/never staged.bin"

dd if=/dev/zero of="$SELECTED_DIR/wrong-size.bin" bs=1024 count=256 status=none
expect_rejected "a wrong-sized explicit BIOS image" 1 \
    YABASANSHIRO_BIOS_MODE=external \
    YABASANSHIRO_BIOS_FILE="$SELECTED_DIR/wrong-size.bin"

expect_rejected "a directory named as an explicit BIOS file" 1 \
    YABASANSHIRO_BIOS_MODE=external YABASANSHIRO_BIOS_FILE="$SELECTED_DIR"

ln -s "$SELECTED_BIOS" "$SELECTED_DIR/link.bin"
expect_rejected "a symlinked explicit BIOS file" 1 \
    YABASANSHIRO_BIOS_MODE=external \
    YABASANSHIRO_BIOS_FILE="$SELECTED_DIR/link.bin"

chmod 000 "$OTHER_BIOS"
if [ ! -r "$OTHER_BIOS" ]; then   # skipped when the smoke runs as root
    expect_rejected "an unreadable explicit BIOS file" 1 \
        YABASANSHIRO_BIOS_MODE=external YABASANSHIRO_BIOS_FILE="$OTHER_BIOS"
fi
chmod 644 "$OTHER_BIOS"

# Back to the default caller shape for the input-config cases below.
run_wrapper

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

input_config="$APP_STATE_ROOT/home/.emulationstation/es_temporaryinput.cfg"
cp "$input_config" "$TMP_ROOT/valid-input.cfg"
sed 's/name="select"        type="button" id="10"/name="select"        type="button" id="8"/' \
    "$input_config" >"$TMP_ROOT/invalid-input.cfg"
mv "$TMP_ROOT/invalid-input.cfg" "$input_config"
if run_wrapper >/dev/null 2>&1; then
    echo "wrapper accepted a config that would strand Menu forwarding" >&2
    exit 1
fi
mv "$TMP_ROOT/valid-input.cfg" "$input_config"

if env -u UMRK_ENV_FILE \
    PLATFORM=mlp1 \
    SDCARD_PATH="$SDCARD_PATH_TEST" \
    USERDATA_PATH="$USERDATA_PATH_TEST" \
    SAVES_PATH="$SAVES_PATH_TEST" \
    STATES_PATH="$STATES_PATH_TEST" \
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

printf 'Verified wrapper quoting, input seed, roster, and BIOS selection contract\n'

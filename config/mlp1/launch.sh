#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${UMRK_ENV_FILE:-}" ] && [ -f "$UMRK_ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$UMRK_ENV_FILE"
elif [ -n "${SDCARD_PATH:-}" ] && [ -n "${PLATFORM:-}" ] &&
     [ -f "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh" ]; then
    # shellcheck source=/dev/null
    . "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh"
fi

if [ "$#" -ne 1 ]; then
    echo "usage: $0 ROM" >&2
    exit 2
fi
ROM_PATH="$1"
if [ ! -f "$ROM_PATH" ]; then
    echo "YabaSanshiro ROM not found: $ROM_PATH" >&2
    exit 1
fi

: "${PLATFORM:=mlp1}"
: "${SDCARD_PATH:=/mnt/sdcard}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/$PLATFORM}"
: "${BIOS_PATH:=$SDCARD_PATH/BIOS}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"
: "${UMRK_RUNTIME_PATH:=${TMPDIR:-/tmp}/jawaka-runtime}"

APP_STATE_ROOT="$USERDATA_PATH/yabasanshiro/probe-sr0"
HOME_DIR="$APP_STATE_ROOT/home"
ES_CONFIG_DIR="$HOME_DIR/.emulationstation"
YABA_CONFIG_DIR="$HOME_DIR/.yabasanshiro"
LOG_DIR="$LOGS_PATH/yabasanshiro"
LOG_FILE="$LOG_DIR/sr0.log"
RUNTIME_DIR="$UMRK_RUNTIME_PATH/yabasanshiro"
DEFAULT_INPUT="$ROOT_DIR/defaults/es_temporaryinput.cfg"
DEFAULT_VERSION_FILE="$ROOT_DIR/defaults/config.version"
INSTALLED_VERSION_FILE="$APP_STATE_ROOT/.umrk-defaults-version"

for required_path in \
    "$ROOT_DIR/bin/yabasanshiro" \
    "$DEFAULT_INPUT" \
    "$DEFAULT_VERSION_FILE"; do
    if [ ! -f "$required_path" ]; then
        echo "YabaSanshiro package input missing: $required_path" >&2
        exit 1
    fi
done

default_version="$(tr -d '[:space:]' <"$DEFAULT_VERSION_FILE")"
case "$default_version" in
    ''|*[!0-9]*)
        echo "invalid YabaSanshiro defaults version: $default_version" >&2
        exit 1
        ;;
esac

# Phase-2 is intentionally embedded-controller-only. Jawaka's private input
# namespace keeps the physical and virtual Loong devices (same name/GUID) from
# colliding, while this assertion prevents an unstable SDL instance mapping.
if [ "${JAWAKA_INPUT_ROSTER_COUNT:-}" != "1" ] ||
   [ "${JAWAKA_RETROARCH_JOYPAD_INDEX:-}" != "0" ]; then
    echo "YabaSanshiro SR0 requires the one-device calibrated Jawaka roster" >&2
    exit 1
fi

mkdir -p "$ES_CONFIG_DIR" "$YABA_CONFIG_DIR" "$LOG_DIR" "$RUNTIME_DIR"
if [ ! -f "$ES_CONFIG_DIR/es_temporaryinput.cfg" ]; then
    cp "$DEFAULT_INPUT" "$ES_CONFIG_DIR/es_temporaryinput.cfg"
fi
if [ ! -f "$INSTALLED_VERSION_FILE" ]; then
    printf '%s\n' "$default_version" >"$INSTALLED_VERSION_FILE"
fi

export HOME="$HOME_DIR"
export TMPDIR="$RUNTIME_DIR"
export SDL_VIDEODRIVER=kmsdrm
export SDL_KMSDRM_REQUIRE_DRM_MASTER=1
export SDL_AUDIODRIVER=pulseaudio
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/pulse-socket}"

bios_args=()
bios_mode="${YABASANSHIRO_BIOS_MODE:-auto}"
case "$bios_mode" in
    auto|external)
        if [ -f "$BIOS_PATH/saturn_bios.bin" ]; then
            bios_args=(-b "$BIOS_PATH/saturn_bios.bin")
            selected_bios=external
        elif [ "$bios_mode" = external ]; then
            echo "external Saturn BIOS not found: $BIOS_PATH/saturn_bios.bin" >&2
            exit 1
        else
            selected_bios=hle
        fi
        ;;
    hle)
        selected_bios=hle
        ;;
    *)
        echo "unsupported YABASANSHIRO_BIOS_MODE: $bios_mode" >&2
        exit 2
        ;;
esac

cd "$RUNTIME_DIR"
: >"$LOG_FILE"
{
    printf 'probe=sr0\n'
    printf 'resolution=original\n'
    printf 'frameskip=upstream-default-enabled\n'
    printf 'bios_mode=%s\n' "$selected_bios"
    printf 'roster_count=%s\n' "$JAWAKA_INPUT_ROSTER_COUNT"
    printf 'joypad_index=%s\n' "$JAWAKA_RETROARCH_JOYPAD_INDEX"
    printf 'rom=%s\n' "$ROM_PATH"
} >>"$LOG_FILE"

exec "$ROOT_DIR/bin/yabasanshiro" \
    -r 3 -i "$ROM_PATH" "${bios_args[@]}" >>"$LOG_FILE" 2>&1

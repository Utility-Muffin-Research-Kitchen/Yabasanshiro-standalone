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
: "${SAVES_PATH:=$SDCARD_PATH/Saves}"
: "${STATES_PATH:=$SDCARD_PATH/States}"
: "${BIOS_PATH:=$SDCARD_PATH/BIOS}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"
: "${UMRK_RUNTIME_PATH:=${TMPDIR:-/tmp}/jawaka-runtime}"

APP_STATE_ROOT="$USERDATA_PATH/yabasanshiro"
HOME_DIR="$APP_STATE_ROOT/home"
ES_CONFIG_DIR="$HOME_DIR/.emulationstation"
YABA_CONFIG_DIR="$HOME_DIR/.yabasanshiro"
BACKUP_DIR="$SAVES_PATH/YabaSanshiro"
STATE_DIR="$STATES_PATH/YabaSanshiro"
LOG_DIR="$LOGS_PATH/yabasanshiro"
LOG_FILE="$LOG_DIR/sr0.log"
RUNTIME_DIR="$UMRK_RUNTIME_PATH/yabasanshiro"
DEFAULT_INPUT="$ROOT_DIR/defaults/es_temporaryinput.cfg"
DEFAULT_VERSION_FILE="$ROOT_DIR/defaults/config.version"
INSTALLED_VERSION_FILE="$APP_STATE_ROOT/.umrk-defaults-version"
INPUT_CONFIG="$ES_CONFIG_DIR/es_temporaryinput.cfg"

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

mkdir -p "$ES_CONFIG_DIR" "$YABA_CONFIG_DIR" "$BACKUP_DIR" "$STATE_DIR" \
    "$LOG_DIR" "$RUNTIME_DIR"
if [ ! -f "$INPUT_CONFIG" ]; then
    cp "$DEFAULT_INPUT" "$INPUT_CONFIG"
fi

installed_version=0
if [ -f "$INSTALLED_VERSION_FILE" ]; then
    installed_version="$(tr -d '[:space:]' <"$INSTALLED_VERSION_FILE")"
    case "$installed_version" in
        ''|*[!0-9]*)
            echo "invalid installed YabaSanshiro defaults version: $installed_version" >&2
            exit 1
            ;;
    esac
fi
if [ "$installed_version" -lt "$default_version" ]; then
    if [ "$installed_version" -lt 2 ]; then
        input_tmp="$INPUT_CONFIG.tmp.$$"
        sed '/name="select"/s/id="[0-9][0-9]*"/id="10"/' \
            "$INPUT_CONFIG" >"$input_tmp"
        mv "$input_tmp" "$INPUT_CONFIG"
    fi
    if ! grep -Eq 'name="select"[^>]*id="10"' "$INPUT_CONFIG"; then
        echo "YabaSanshiro input config does not bind Leaf Menu to button 10" >&2
        exit 1
    fi
    printf '%s\n' "$default_version" >"$INSTALLED_VERSION_FILE"
fi
if ! grep -Eq 'name="select"[^>]*id="10"' "$INPUT_CONFIG"; then
    echo "YabaSanshiro input config does not bind Leaf Menu to button 10" >&2
    exit 1
fi

export HOME="$HOME_DIR"
export TMPDIR="$RUNTIME_DIR"
export SDL_VIDEODRIVER=kmsdrm
export SDL_KMSDRM_REQUIRE_DRM_MASTER=1
export SDL_AUDIODRIVER=pulseaudio
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/pulse-socket}"
export YABASANSHIRO_BACKUP_PATH="$BACKUP_DIR/backup.bin"
export YABASANSHIRO_STATE_DIR="$STATE_DIR"
export YABASANSHIRO_MLP1_ROTATE_90=1

# BIOS selection. Two callers, one behavior each:
#
#   Leaf's launcher resolves the user's choice and hands over an explicit
#   YABASANSHIRO_BIOS_FILE with MODE=external. That exact path is used, whatever
#   it is named and wherever on either card it lives, and it is only ever
#   quoted into bios_args -- never evaluated as shell.
#
#   A direct caller that sets no FILE keeps the original hle|external|auto mode
#   semantics over the standard $BIOS_PATH/SATURN/saturn_bios.bin. auto exists only for
#   those callers; the Leaf picker never offers it and never resolves to it.
#
# An explicit FILE is checked immediately before exec because a card can be
# pulled after the launcher validated it. Nothing here falls back: a selection
# the user made and cannot be honored is an error, not a silent switch to HLE
# or to some other image.
bios_args=()
bios_mode="${YABASANSHIRO_BIOS_MODE:-hle}"
selected_bios_path=""
selected_bios_source=standard
standard_bios_path="$BIOS_PATH/SATURN/saturn_bios.bin"

if [ -n "${YABASANSHIRO_BIOS_FILE+x}" ]; then
    explicit_bios="$YABASANSHIRO_BIOS_FILE"
    if [ -z "$explicit_bios" ]; then
        echo "YABASANSHIRO_BIOS_FILE is set but empty" >&2
        exit 2
    fi
    if [ "$bios_mode" != external ]; then
        echo "YABASANSHIRO_BIOS_FILE requires YABASANSHIRO_BIOS_MODE=external, got: $bios_mode" >&2
        exit 2
    fi
    if [ -L "$explicit_bios" ] || [ ! -f "$explicit_bios" ]; then
        echo "selected Saturn BIOS is not a regular file: $explicit_bios" >&2
        exit 1
    fi
    if [ ! -r "$explicit_bios" ]; then
        echo "selected Saturn BIOS is not readable: $explicit_bios" >&2
        exit 1
    fi
    # A raw Saturn BIOS is exactly 512 KiB: the emulator loads 0x80000 bytes.
    # Size is a shape check, not proof of authenticity or game compatibility.
    explicit_bios_size="$(wc -c <"$explicit_bios" | tr -d '[:space:]')"
    if [ "$explicit_bios_size" != 524288 ]; then
        echo "selected Saturn BIOS is not a 512 KiB image (${explicit_bios_size} bytes): $explicit_bios" >&2
        exit 1
    fi
    selected_bios_path="$explicit_bios"
    selected_bios_source=explicit
    selected_bios=external
    bios_args=(-b "$selected_bios_path")
else
    if [ -f "$standard_bios_path" ]; then
        selected_bios_path="$standard_bios_path"
    fi
    case "$bios_mode" in
        auto|external)
            if [ -n "$selected_bios_path" ]; then
                bios_args=(-b "$selected_bios_path")
                selected_bios=external
            elif [ "$bios_mode" = external ]; then
                echo "external Saturn BIOS not found: $standard_bios_path" >&2
                exit 1
            else
                selected_bios=hle
                selected_bios_path=""
            fi
            ;;
        hle)
            selected_bios=hle
            selected_bios_path=""
            ;;
        *)
            echo "unsupported YABASANSHIRO_BIOS_MODE: $bios_mode" >&2
            exit 2
            ;;
    esac
fi

cd "$RUNTIME_DIR"
: >"$LOG_FILE"
{
    printf 'probe=sr0\n'
    printf 'resolution_cli_default=original\n'
    printf 'rotation=mlp1-native-90\n'
    printf 'frameskip=upstream-default-enabled\n'
    printf 'bios_mode=%s\n' "$selected_bios"
    printf 'backup_path=%s\n' "$YABASANSHIRO_BACKUP_PATH"
    printf 'state_dir=%s\n' "$YABASANSHIRO_STATE_DIR"
    if [ "$selected_bios" = external ]; then
        printf 'bios_source=%s\n' "$selected_bios_source"
        printf 'bios_path=%s\n' "$selected_bios_path"
    fi
    printf 'roster_count=%s\n' "$JAWAKA_INPUT_ROSTER_COUNT"
    printf 'joypad_index=%s\n' "$JAWAKA_RETROARCH_JOYPAD_INDEX"
    printf 'rom=%s\n' "$ROM_PATH"
} >>"$LOG_FILE"

exec "$ROOT_DIR/bin/yabasanshiro" \
    -r 3 -i "$ROM_PATH" "${bios_args[@]}" >>"$LOG_FILE" 2>&1

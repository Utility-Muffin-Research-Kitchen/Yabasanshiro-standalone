#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/workdir/mlp1/yabause"
BUILD_MANIFEST="$ROOT_DIR/output/mlp1/build/provenance/build-manifest.json"
BUILD_PROVENANCE_DIR="$ROOT_DIR/output/mlp1/build/provenance"
JSON_DIR="$ROOT_DIR/output/mlp1/cmake/src/retro_arena/Json/src/Json"
LIBCHDR_DIR="$ROOT_DIR/output/mlp1/cmake/src/libchdr-prefix/src/libchdr"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output/mlp1/source}"

# shellcheck disable=SC1091
. "$ROOT_DIR/upstream.env"

for command_name in git jq python3 shasum tar; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing source-package command: $command_name" >&2
        exit 1
    fi
done

for required_path in \
    "$BUILD_MANIFEST" \
    "$SOURCE_DIR/LICENSE" \
    "$SOURCE_DIR/yabause/COPYING.txt" \
    "$JSON_DIR/LICENSE.MIT" \
    "$LIBCHDR_DIR/LICENSE.txt"; do
    if [ ! -f "$required_path" ]; then
        echo "missing source-package input: $required_path" >&2
        echo "run make build-mlp1 first" >&2
        exit 1
    fi
done

copy_tracked_tree() {
    local repository="$1"
    local destination="$2"

    mkdir -p "$destination"
    (
        cd "$repository"
        git ls-files --recurse-submodules -z |
            tar --null -T - -cf -
    ) | (
        cd "$destination"
        tar -xf -
    )
}

verify_commit() {
    local repository="$1"
    local expected="$2"
    local label="$3"
    local actual

    actual="$(git -C "$repository" rev-parse HEAD)"
    if [ "$actual" != "$expected" ]; then
        echo "$label source mismatch: expected $expected, found $actual" >&2
        exit 1
    fi
}

verify_commit "$SOURCE_DIR" "$YABASANSHIRO_UPSTREAM_SHA" "YabaSanshiro"
verify_commit "$JSON_DIR" "$NLOHMANN_JSON_SHA" "nlohmann/json"
verify_commit "$LIBCHDR_DIR" "$LIBCHDR_SHA" "libchdr"

manifest_source_sha="$(jq -r '.upstream_sha' "$BUILD_MANIFEST")"
if [ "$manifest_source_sha" != "$YABASANSHIRO_UPSTREAM_SHA" ]; then
    echo "build manifest does not describe the pinned source" >&2
    exit 1
fi

if ! git -C "$SOURCE_DIR" diff --check; then
    echo "patched upstream source failed git diff --check" >&2
    exit 1
fi
for dependency_dir in "$JSON_DIR" "$LIBCHDR_DIR"; do
    if [ -n "$(git -C "$dependency_dir" status --porcelain --untracked-files=all)" ]; then
        echo "dependency source is dirty: $dependency_dir" >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/yabasanshiro-source.XXXXXX")"
trap 'rm -rf -- "$staging_root"' EXIT

archive_base="yabasanshiro-standalone-${YABASANSHIRO_UPSTREAM_VERSION}-mlp1-source"
bundle_root="$staging_root/$archive_base"
mkdir -p "$bundle_root/dependencies" "$bundle_root/provenance"

copy_tracked_tree "$ROOT_DIR" "$bundle_root/umrk-port"
copy_tracked_tree "$SOURCE_DIR" "$bundle_root/upstream"
copy_tracked_tree "$JSON_DIR" "$bundle_root/dependencies/nlohmann-json"
copy_tracked_tree "$LIBCHDR_DIR" "$bundle_root/dependencies/libchdr"
cp -R "$BUILD_PROVENANCE_DIR/." "$bundle_root/provenance/"

printf '%s\n' \
    '# YabaSanshiro standalone corresponding source' \
    '' \
    'This archive accompanies the Leaf MLP1 binary package and contains the' \
    'complete machine-readable source selected for that build:' \
    '' \
    "- patched YabaSanshiro upstream: $YABASANSHIRO_UPSTREAM_SHA" \
    "- nlohmann/json: $NLOHMANN_JSON_SHA" \
    "- devmiyax/libchdr: $LIBCHDR_SHA" \
    '- recursive upstream submodules at their pinned commits' \
    '- UMRK patches, build scripts, packaging scripts, and licence records' \
    '- the binary build provenance manifest' \
    '' \
    "The source under \`upstream/\` already has the patches from" \
    "\`umrk-port/patches/\` applied. The normal build entry point and documented" \
    "toolchain inputs are in \`umrk-port/README.md\` and \`umrk-port/Makefile\`." \
    'No BIOS or game content is included.' \
    >"$bundle_root/SOURCE-BUNDLE.md"

checksum_inventory="$staging_root/SHA256SUMS"
python3 - "$bundle_root" "$checksum_inventory" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
inventory = Path(sys.argv[2])
with inventory.open("w", encoding="utf-8", newline="\n") as output:
    for path in sorted(root.rglob("*"), key=lambda value: value.as_posix()):
        if not path.is_file():
            continue
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        relative = "./" + path.relative_to(root).as_posix()
        output.write(f"{digest.hexdigest()}  {relative}\n")
PY
install -m 0644 "$checksum_inventory" "$bundle_root/SHA256SUMS"

archive_path="$OUTPUT_DIR/$archive_base.tar.gz"
source_date_epoch="$(jq -r '.source_date_epoch' "$BUILD_MANIFEST")"
case "$source_date_epoch" in
    ''|*[!0-9]*)
        echo "build manifest has an invalid source_date_epoch" >&2
        exit 1
        ;;
esac
python3 - "$bundle_root" "$archive_path" "$source_date_epoch" <<'PY'
import gzip
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
archive = Path(sys.argv[2])
epoch = int(sys.argv[3])
paths = [root, *sorted(root.rglob("*"), key=lambda path: path.as_posix())]

with archive.open("wb") as output:
    with gzip.GzipFile(
        filename="", mode="wb", fileobj=output, compresslevel=6, mtime=0
    ) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as bundle:
            for path in paths:
                arcname = path.relative_to(root.parent).as_posix()
                info = bundle.gettarinfo(str(path), arcname)
                info.uid = 0
                info.gid = 0
                info.uname = "root"
                info.gname = "root"
                info.mtime = epoch
                info.pax_headers = {}
                if info.isfile():
                    with path.open("rb") as source:
                        bundle.addfile(info, source)
                else:
                    bundle.addfile(info)
PY
archive_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$(basename "$archive_path")" \
    >"$archive_path.sha256"

archive_members="$staging_root/archive-members.txt"
tar -tzf "$archive_path" >"$archive_members"
if grep -E '(^|/)\.git(/|$)' "$archive_members" >/dev/null; then
    echo "source archive unexpectedly contains Git metadata" >&2
    exit 1
fi
for required_member in \
    "$archive_base/SOURCE-BUNDLE.md" \
    "$archive_base/SHA256SUMS" \
    "$archive_base/umrk-port/scripts/package-source.sh" \
    "$archive_base/umrk-port/patches/0004-mlp1-native-rotation.patch" \
    "$archive_base/upstream/yabause/COPYING.txt" \
    "$archive_base/upstream/yabause/src/retro_arena/main.cpp" \
    "$archive_base/dependencies/nlohmann-json/LICENSE.MIT" \
    "$archive_base/dependencies/libchdr/LICENSE.txt" \
    "$archive_base/provenance/build-manifest.json"; do
    if ! grep -Fx "$required_member" "$archive_members" >/dev/null; then
        echo "source archive is missing: $required_member" >&2
        exit 1
    fi
done

printf 'Packaged corresponding source: %s\n' "$archive_path"
printf 'Source archive checksum: %s\n' "$archive_path.sha256"

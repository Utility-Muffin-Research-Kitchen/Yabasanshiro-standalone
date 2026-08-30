#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${YABASANSHIRO_SOURCE_DIR:-$ROOT_DIR/workdir/mlp1/yabause}"
PATCH_DIR="$ROOT_DIR/patches"

# shellcheck disable=SC1091
. "$ROOT_DIR/upstream.env"

mkdir -p "$(dirname "$SOURCE_DIR")"

if [ ! -d "$SOURCE_DIR/.git" ]; then
    git clone --filter=blob:none --no-checkout \
        "$YABASANSHIRO_UPSTREAM_URL" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --force origin \
    "refs/heads/$YABASANSHIRO_UPSTREAM_BRANCH:refs/remotes/origin/$YABASANSHIRO_UPSTREAM_BRANCH"

if ! git -C "$SOURCE_DIR" merge-base --is-ancestor \
    "$YABASANSHIRO_UPSTREAM_SHA" \
    "refs/remotes/origin/$YABASANSHIRO_UPSTREAM_BRANCH"; then
    echo "pinned source is not on the expected upstream branch" >&2
    exit 1
fi

PATCHES=()
while IFS= read -r patch_path; do
    PATCHES[${#PATCHES[@]}]="$patch_path"
done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort)

# A completed build leaves only this repository's deterministic patches
# applied. Reverse that exact set, then refuse to overwrite any other edit.
if [ -n "$(git -C "$SOURCE_DIR" status --short --untracked-files=no)" ]; then
    for ((index=${#PATCHES[@]} - 1; index >= 0; index--)); do
        patch_path="${PATCHES[$index]}"
        if git -C "$SOURCE_DIR" apply --reverse --check \
                "$patch_path" >/dev/null 2>&1; then
            git -C "$SOURCE_DIR" apply --reverse "$patch_path"
        fi
    done
    if [ -n "$(git -C "$SOURCE_DIR" status --short --untracked-files=no)" ]; then
        echo "upstream checkout has non-package changes: $SOURCE_DIR" >&2
        echo "refusing to overwrite an edited source tree" >&2
        exit 1
    fi
fi

git -C "$SOURCE_DIR" checkout --detach "$YABASANSHIRO_UPSTREAM_SHA"
git -C "$SOURCE_DIR" submodule sync --recursive
git -C "$SOURCE_DIR" submodule update --init --recursive

actual_sha="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [ "$actual_sha" != "$YABASANSHIRO_UPSTREAM_SHA" ]; then
    echo "source checkout mismatch: $actual_sha" >&2
    exit 1
fi

for patch_path in "${PATCHES[@]}"; do
    git -C "$SOURCE_DIR" apply --check "$patch_path"
    git -C "$SOURCE_DIR" apply "$patch_path"
done

git -C "$SOURCE_DIR" diff --check
printf 'YabaSanshiro source ready: %s (%s, %s patches)\n' \
    "$YABASANSHIRO_UPSTREAM_VERSION" "$actual_sha" "${#PATCHES[@]}"

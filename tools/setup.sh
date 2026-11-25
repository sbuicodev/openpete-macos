#!/usr/bin/env bash
# Prepare work/openpete: upstream OpenPete at the pinned commit, with this
# repo's patches applied and overlay files copied in.
#
#   tools/setup.sh           # once; does nothing if already set up
#   tools/setup.sh --force   # throw work/openpete away and redo it
#
# Upstream pins its PsyCross fork at a URL that is not public; the same
# commit is published as tyscorp/psycross-archive, which is used instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$ROOT/work/openpete"
MARK="$W/.macos-patches-applied"
PSYCROSS_URL="https://github.com/tyscorp/psycross-archive.git"
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1
if [[ -f "$MARK" && $FORCE -eq 0 ]]; then
    say "work/openpete is ready (tools/setup.sh --force to redo it)"
    exit 0
fi

cd "$ROOT"
git submodule update --init upstream
PIN="$(git rev-parse HEAD:upstream)"

if [[ -e "$W" ]]; then
    [[ $FORCE -eq 1 ]] || die "work/openpete exists but is incomplete; rerun with --force"
    say "Removing the old work/openpete"
    rm -rf -- "$ROOT/work/openpete"
fi

say "Checking out upstream OpenPete ${PIN:0:10}"
mkdir -p "$ROOT/work"
git clone --quiet --no-checkout "$ROOT/upstream" "$W"
git -C "$W" remote set-url origin "$(git -C "$ROOT/upstream" remote get-url origin)"
git -C "$W" checkout --quiet -b macos "$PIN"

say "Submodules (PsyCross from the public archive)"
git -C "$W" submodule init third_party/PsyCross
git -C "$W" config submodule.third_party/PsyCross.url "$PSYCROSS_URL"
git -C "$W" submodule update third_party/PsyCross
# This commit names the decomp by an SSH URL, which needs GitHub SSH keys;
# HTTPS works for everyone. Its own nested submodule (the maspsx compiler
# wrapper) is only for building the decomp, which the disc-carved build skips.
git -C "$W" submodule init games/spyro-1/spyro-1
git -C "$W" config submodule.games/spyro-1/spyro-1.url \
    "https://github.com/TheMobyCollective/spyro-1.git"
git -C "$W" submodule update games/spyro-1/spyro-1
git -C "$W" submodule update --init --recursive -- \
    third_party/SDL third_party/glslang third_party/imgui

# git am records a committer; supply one only if the user has none configured.
ID=()
git config user.email >/dev/null 2>&1 || ID=(-c user.name=openpete-macos -c user.email=openpete-macos@localhost)

say "Applying patches"
git -C "$W" ${ID[@]+"${ID[@]}"} am --quiet "$ROOT"/patches/openpete/*.patch
git -C "$W/third_party/PsyCross" checkout --quiet -b arm64-fixes
git -C "$W/third_party/PsyCross" ${ID[@]+"${ID[@]}"} am --quiet "$ROOT"/patches/psycross/*.patch

say "Copying overlay files"
cp -R "$ROOT/overlay/." "$W/"

touch "$MARK"
say "Ready: work/openpete ($(git -C "$W" rev-list --count "$PIN"..macos) patches on top of upstream)"

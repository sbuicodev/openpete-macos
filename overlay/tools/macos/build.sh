#!/usr/bin/env bash
# One-shot build of OpenPete (Spyro the Dragon) for Apple Silicon macOS.
#
#   tools/macos/build.sh "/path/to/Spyro the Dragon (USA).cue"
#
# Needs Homebrew and the user's own NTSC-U disc image (SCUS-94228, .cue+.bin).
# No Docker, no PSYQ SDK, no decompilation build: PSX.EXE and the overlays are
# carved from the disc and verified against the decomp's sha256sum.txt, then
# recompiled to C and built with the macos-arm64 preset (full recompiled
# path, OPENPETE_SKIP_DECOMP=ON). Nothing derived from the disc leaves this
# machine: every output lands in gitignored directories.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREW=/opt/homebrew

# The repo's scripts need bash >= 4; re-exec under Homebrew's bash if needed.
if (( BASH_VERSINFO[0] < 4 )) && [[ -x "$BREW/bin/bash" ]]; then
    exec "$BREW/bin/bash" "$0" "$@"
fi

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

DISC="${1:-}"
[[ -n "$DISC" ]] || die "usage: tools/macos/build.sh /path/to/disc.cue"
[[ -f "$DISC" ]] || die "disc image not found: $DISC"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || die "Apple Silicon macOS only"
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"

say "Homebrew packages"
PKGS=(cmake ninja glslang spirv-tools openal-soft molten-vk python bash
      gnu-sed coreutils findutils grep gawk)
missing=()
for p in "${PKGS[@]}"; do brew list --formula "$p" >/dev/null 2>&1 || missing+=("$p"); done
if (( ${#missing[@]} )); then brew install "${missing[@]}"; fi

cd "$ROOT"
say "Python tools environment"
if [[ ! -x .venv-macos/bin/python3 ]]; then
    "$BREW/bin/python3" -m venv .venv-macos
fi
.venv-macos/bin/pip install --quiet --disable-pip-version-check tomli

say "Submodules"
git submodule update --init --recursive -- \
    third_party/SDL third_party/glslang third_party/imgui games/spyro-1/spyro-1

# shellcheck source=env.sh
source tools/macos/env.sh

say "Carving PSX.EXE and overlays from the disc"
python3 tools/macos/carve_disc.py "$DISC"

say "Building the PSXRecomp recompiler"
cmake -S third_party/psxrecomp/recompiler -B third_party/psxrecomp/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-DFMT_CONSTEVAL= >/dev/null
cmake --build third_party/psxrecomp/build

say "Recompiling the game to C (about a minute)"
mkdir -p build
GAME=spyro-1 bash scripts/regen-recomp.sh > build/regen.log 2>&1 \
    || die "recompile failed; see build/regen.log"

say "Building OpenPete"
cmake --preset macos-arm64 >/dev/null
cmake --build --preset macos-arm64

BIN="$ROOT/build/macos/games/spyro-1/openpete-spyro1"
say "Done. Run:"
printf '  "%s" --disc "%s"\n' "$BIN" "$(cd "$(dirname "$DISC")" && pwd)/$(basename "$DISC")"

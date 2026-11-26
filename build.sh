#!/usr/bin/env bash
# Build OpenPete for Apple Silicon from your own Spyro the Dragon (NTSC-U) disc.
#   ./build.sh "/path/to/Spyro the Dragon (USA).cue"
#   ./build.sh            (no disc: set up the toolchain for ./make-app.sh only)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/tools/setup.sh"
exec "$ROOT/work/openpete/tools/macos/build.sh" "$@"

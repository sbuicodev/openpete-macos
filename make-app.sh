#!/usr/bin/env bash
# Make OpenPete.app (no game code inside; it recompiles the player's disc on
# first launch). Needs ./build.sh to have run once.
#   ./make-app.sh [output.app]      (default: build/OpenPete.app)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/tools/setup.sh"
mkdir -p "$ROOT/build"
exec "$ROOT/work/openpete/tools/macos/make_app.sh" "${1:-$ROOT/build/OpenPete.app}"

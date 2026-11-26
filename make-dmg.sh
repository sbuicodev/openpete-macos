#!/usr/bin/env bash
# Make a release disk image of OpenPete.app (no disc needed).
#   ./make-dmg.sh [output.dmg]      (default: build/OpenPete-<version>.dmg)
# OPENPETE_SIGN_IDENTITY and OPENPETE_NOTARY_PROFILE: see the README.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/tools/setup.sh"
mkdir -p "$ROOT/build"
V="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo dev)"
export OPENPETE_VERSION="${OPENPETE_VERSION:-${V#v}}"
exec "$ROOT/work/openpete/tools/macos/make_dmg.sh" "${1:-$ROOT/build/OpenPete-$V.dmg}"

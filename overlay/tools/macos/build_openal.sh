#!/usr/bin/env bash
# Build OpenAL Soft for the .app's minimum macOS. Homebrew's bottle targets the
# macOS it was built on, so the app would refuse to start on older systems.
# The source is Homebrew's (same version, SHA-256 checked by `brew fetch`).
#
#   tools/macos/build_openal.sh        prints the install prefix on stdout
#
# Output: build/openal-macos<target>/{include,lib} (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
PREFIX="$ROOT/build/openal-macos$TARGET"
say() { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }

if [[ -f "$PREFIX/lib/libopenal.1.dylib" ]]; then
    echo "$PREFIX"
    exit 0
fi

say "Building OpenAL Soft for macOS $TARGET"
brew fetch --quiet --build-from-source openal-soft >&2
TARBALL="$(brew --cache --build-from-source openal-soft)"
[[ -f "$TARBALL" ]] || { echo "OpenAL Soft source not found: $TARBALL" >&2; exit 1; }

SRC="$ROOT/build/openal-src"
rm -rf -- "$SRC" "$ROOT/build/openal-build"
mkdir -p "$SRC"
tar -xjf "$TARBALL" -C "$SRC" --strip-components=1

# Same feature set as Homebrew's formula: CoreAudio only, no tools/examples.
# HAVE_WFUNCTION_EFFECTS=OFF: with -Werror=function-effects, newer clang
# rejects two casts in the CoreAudio backend.
cmake -S "$SRC" -B "$ROOT/build/openal-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DHAVE_WFUNCTION_EFFECTS=OFF \
    -DALSOFT_BACKEND_PORTAUDIO=OFF \
    -DALSOFT_BACKEND_PULSEAUDIO=OFF \
    -DALSOFT_BACKEND_PIPEWIRE=OFF \
    -DALSOFT_BACKEND_JACK=OFF \
    -DALSOFT_BACKEND_SDL2=OFF \
    -DALSOFT_BACKEND_SDL3=OFF \
    -DALSOFT_UTILS=OFF \
    -DALSOFT_EXAMPLES=OFF \
    -DALSOFT_TESTS=OFF \
    -DALSOFT_INSTALL_CONFIG=OFF \
    -DALSOFT_INSTALL_HRTF_DATA=OFF \
    -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF >&2
cmake --build "$ROOT/build/openal-build" >&2
cmake --install "$ROOT/build/openal-build" >&2
cp "$SRC/COPYING" "$PREFIX/COPYING"
VER="$(basename "$TARBALL" | sed -E 's/.*openal-soft-([0-9.]+)\.tar\.bz2$/\1/')"
printf 'OpenAL Soft %s (GNU LGPL; see OpenAL-Soft-COPYING.txt), built unmodified from\nhttps://openal-soft.org/openal-releases/openal-soft-%s.tar.bz2\nSource: https://github.com/kcat/openal-soft\n' "$VER" "$VER" > "$PREFIX/SOURCE"
echo "$PREFIX"

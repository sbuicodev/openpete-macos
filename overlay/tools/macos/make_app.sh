#!/usr/bin/env bash
# Build OpenPete.app: a double-clickable macOS (Apple Silicon) app that
# contains NO game code or data. On first launch it asks for the player's own
# Spyro the Dragon (NTSC-U) disc image, copies it into the library, recompiles
# the game into a module on that Mac (about 30 s, needs Apple's Command Line
# Tools), and plays. Later launches start straight away.
#
#   tools/macos/make_app.sh [output.app]      (default: build/OpenPete.app)
#
# Prerequisite: tools/macos/build.sh has run once on this machine (it builds
# PSXRecomp and the generated sources the CMake configure step requires).
# Nothing derived from the disc goes into the bundle: the engine is built with
# shared recomp linkage, and only the recompile kit (function lists, the
# module source kit, PSXRecomp) is staged.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if (( BASH_VERSINFO[0] < 4 )) && [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
fi
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$ROOT"
APP="${1:-$ROOT/build/OpenPete.app}"
[[ "$APP" == *.app ]] || die "output must end in .app: $APP"
[[ -f games/spyro-1/generated/PSX.EXE_full.c ]] \
    || die "run tools/macos/build.sh <disc.cue> once first"
[[ -x third_party/psxrecomp/build/PSXRecomp ]] \
    || die "PSXRecomp is not built; run tools/macos/build.sh first"

# shellcheck source=env.sh
source tools/macos/env.sh

say "Building the engine (shared recomp linkage, no game code)"
cmake --preset macos-arm64-app >/dev/null
cmake --build --preset macos-arm64-app

B=build/macos-app/games/spyro-1
EXE=openpete-spyro1
BREW=/opt/homebrew

say "Assembling $(basename "$APP")"
if [[ -d "$APP" ]]; then rm -rf -- "$APP"; fi
C="$APP/Contents"
mkdir -p "$C/MacOS" "$C/Frameworks" "$C/Resources/licences" "$C/Resources/recomp/tools"

cp "$B/$EXE" "$C/MacOS/$EXE"
cp "$BREW/opt/openal-soft/lib/libopenal.1.dylib" "$C/Frameworks/"
cp "$BREW/opt/molten-vk/lib/libMoltenVK.dylib" "$C/Frameworks/"
chmod u+w "$C/Frameworks/"*.dylib
install_name_tool -id @rpath/libopenal.1.dylib "$C/Frameworks/libopenal.1.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$C/Frameworks/libMoltenVK.dylib"
install_name_tool -change "$BREW/opt/openal-soft/lib/libopenal.1.dylib" \
    @executable_path/../Frameworks/libopenal.1.dylib "$C/MacOS/$EXE"
if otool -L "$C/MacOS/$EXE" | grep -q /opt/homebrew; then
    die "the engine still references Homebrew libraries:
$(otool -L "$C/MacOS/$EXE" | grep /opt/homebrew)"
fi

# Shipped read-only data: openpete_exe_dir() is Contents/Resources in a bundle.
R="$C/Resources"
cp -R "$B/recomp/manifest" "$B/recomp/src" "$R/recomp/"
python3 scripts/strip-comments.py "$R"/recomp/src/*
cp "$B/recomp/tools/PSXRecomp" "$R/recomp/tools/"
cp -R "$B/assets" "$R/"
cp gamecontrollerdb.txt "$R/"
cp docs/openpete-dist.toml "$R/openpete.toml"
cp LICENSE NOTICE.md "$R/"
cp "$BREW/opt/openal-soft/COPYING" "$R/licences/OpenAL-Soft-COPYING.txt"
cp "$BREW/opt/molten-vk/LICENSE" "$R/licences/MoltenVK-LICENSE.txt"
cp third_party/psxrecomp/LICENSE "$R/licences/PSXRecomp-LICENSE.txt"

say "Icon"
ICONSET="$(mktemp -d)/OpenPete.iconset"
mkdir -p "$ICONSET"
python3 tools/gen_dist_icon.py --png "$ICONSET/base.png" --png-size 1024 >/dev/null
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$R/OpenPete.icns"

VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
cat > "$C/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>OpenPete</string>
    <key>CFBundleDisplayName</key>         <string>OpenPete</string>
    <key>CFBundleIdentifier</key>          <string>local.openpete.spyro1</string>
    <key>CFBundleExecutable</key>          <string>$EXE</string>
    <key>CFBundleIconFile</key>            <string>OpenPete</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION#v}</string>
    <key>CFBundleVersion</key>             <string>${VERSION#v}</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>LSArchitecturePriority</key>      <array><string>arm64</string></array>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>GCSupportsControllerUserInteraction</key> <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>      <string>PlayStation disc image</string>
            <key>CFBundleTypeRole</key>      <string>Viewer</string>
            <key>LSHandlerRank</key>         <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>cue</string><string>bin</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

say "Signing (ad-hoc)"
for f in "$C/Frameworks/"*.dylib "$R/recomp/tools/PSXRecomp" "$C/MacOS/$EXE"; do
    codesign --force --sign - "$f"
done
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

du -sh "$APP" | awk '{print "==> " $2 ": " $1}'
say "Done. Open it with:  open \"$APP\""

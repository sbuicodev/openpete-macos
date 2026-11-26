#!/usr/bin/env bash
# Build OpenPete.app: a double-clickable macOS (Apple Silicon) app that
# contains NO game code or data. On first launch it asks for the player's own
# Spyro the Dragon (NTSC-U) disc image, copies it into the library, recompiles
# the game into a module on that Mac (about 30 s, needs Apple's Command Line
# Tools), and plays. Later launches start straight away.
#
#   tools/macos/make_app.sh [output.app]      (default: build/OpenPete.app)
#
# No disc is needed here. If tools/macos/build.sh has not run yet, it is run
# without a disc to set up the toolchain, PSXRecomp and the disc-free sources.
# Nothing derived from the disc goes into the bundle: the engine is built with
# shared recomp linkage, and only the recompile kit (function lists, the
# module source kit, PSXRecomp) is staged.
#
# Every binary targets macOS $MACOSX_DEPLOYMENT_TARGET (13.0 by default, set in
# env.sh); OpenAL Soft is built for it by build_openal.sh, since Homebrew's
# bottle only runs on the macOS it was built for.
#
# Signing: ad-hoc unless OPENPETE_SIGN_IDENTITY names a "Developer ID
# Application: ..." certificate in the keychain, in which case every binary is
# signed with it, the hardened runtime and a secure timestamp, ready for
# notarization (tools/macos/make_dmg.sh). OPENPETE_SIGN_IDENTITY=- signs ad-hoc
# with the hardened runtime, to test the entitlements without a certificate.
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
# shellcheck source=env.sh
source tools/macos/env.sh
TARGET="$MACOSX_DEPLOYMENT_TARGET"

minos() { otool -l "$1" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}'; }
newer_than_target() {   # true when the Mach-O at $1 needs a newer macOS
    [[ "$(printf '%s\n%s\n' "$(minos "$1")" "$TARGET" | sort -V | tail -1)" != "$TARGET" ]]
}

if [[ ! -x third_party/psxrecomp/build/PSXRecomp \
      || ! -f games/spyro-1/generated/psyq_stubs.c \
      || ! -f games/spyro-1/generated/channel_sites.txt ]] \
   || newer_than_target third_party/psxrecomp/build/PSXRecomp; then
    say "Preparing the toolchain (tools/macos/build.sh, no disc)"
    tools/macos/build.sh
fi

OAL="$(tools/macos/build_openal.sh)"

say "Building the engine (shared recomp linkage, no game code)"
cmake --preset macos-arm64-app \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
    -DOPENAL_INCLUDE_DIR="$OAL/include" \
    -DOPENAL_LIBRARY="$OAL/lib/libopenal.1.dylib" >/dev/null
cmake --build --preset macos-arm64-app

B=build/macos-app/games/spyro-1
EXE=openpete-spyro1
BREW=/opt/homebrew

say "Assembling $(basename "$APP")"
if [[ -d "$APP" ]]; then rm -rf -- "$APP"; fi
C="$APP/Contents"
mkdir -p "$C/MacOS" "$C/Frameworks" "$C/Resources/licences" "$C/Resources/recomp/tools"

cp "$B/$EXE" "$C/MacOS/$EXE"
cp "$OAL/lib/libopenal.1.dylib" "$C/Frameworks/"
cp "$BREW/opt/molten-vk/lib/libMoltenVK.dylib" "$C/Frameworks/"
chmod u+w "$C/Frameworks/"*.dylib "$C/MacOS/$EXE"
install_name_tool -id @rpath/libopenal.1.dylib "$C/Frameworks/libopenal.1.dylib" 2>/dev/null
install_name_tool -id @rpath/libMoltenVK.dylib "$C/Frameworks/libMoltenVK.dylib" 2>/dev/null
OAL_REF="$(otool -L "$C/MacOS/$EXE" | awk '/libopenal/{print $1; exit}')"
install_name_tool -change "$OAL_REF" \
    @executable_path/../Frameworks/libopenal.1.dylib "$C/MacOS/$EXE" 2>/dev/null
# Build-tree rpaths name this machine's directories: drop every absolute one.
otool -l "$C/MacOS/$EXE" | awk '/LC_RPATH/{r=1} r&&/ path /{print $2; r=0}' \
    | grep '^/' | while IFS= read -r rp; do
        install_name_tool -delete_rpath "$rp" "$C/MacOS/$EXE" 2>/dev/null
    done
if otool -L "$C/MacOS/$EXE" | grep -q -e /opt/homebrew -e "$ROOT"; then
    die "the engine still references libraries outside the bundle:
$(otool -L "$C/MacOS/$EXE" | grep -e /opt/homebrew -e "$ROOT")"
fi

# Shipped read-only data: openpete_exe_dir() is Contents/Resources in a bundle.
R="$C/Resources"
cp -R "$B/recomp/manifest" "$B/recomp/src" "$R/recomp/"
python3 scripts/strip-comments.py "$R"/recomp/src/*
cp "$B/recomp/tools/PSXRecomp" "$R/recomp/tools/"
cp -R "$B/assets" "$R/"
cp -R "$B/sdk" "$R/"   # mod SDK: the loader compiles code mods against it
cp gamecontrollerdb.txt "$R/"
cp docs/openpete-dist.toml "$R/openpete.toml"
cp LICENSE NOTICE.md "$R/"
cp "$OAL/COPYING" "$R/licences/OpenAL-Soft-COPYING.txt"
cp "$OAL/SOURCE" "$R/licences/OpenAL-Soft-SOURCE.txt"
cp "$BREW/opt/molten-vk/LICENSE" "$R/licences/MoltenVK-LICENSE.txt"
cp third_party/psxrecomp/LICENSE "$R/licences/PSXRecomp-LICENSE.txt"
cp third_party/imgui/LICENSE.txt "$R/licences/DearImGui-LICENSE.txt"
cp third_party/dear_bindings/LICENSE.txt "$R/licences/dear_bindings-LICENSE.txt"

say "Icon"
# tools/macos/OpenPete.icon is the Icon Composer source. actool (full Xcode 26+)
# compiles it to Assets.car (the layered icon) plus OpenPete.icns for older
# macOS. With only the Command Line Tools, fall back to a flat .icns made from
# the pixel-art mark.
ICON_NAME_KEY=""
if xcrun --find actool >/dev/null 2>&1 \
    && xcrun actool tools/macos/OpenPete.icon --compile "$R" --app-icon OpenPete \
        --platform macosx --minimum-deployment-target 13.0 \
        --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null 2>&1 \
    && [[ -f "$R/Assets.car" && -f "$R/OpenPete.icns" ]]; then
    ICON_NAME_KEY="<key>CFBundleIconName</key>            <string>OpenPete</string>"
else
    say "actool unavailable (needs Xcode 26+); using the flat icon"
    rm -f "$R/Assets.car"
    ICONSET="$(mktemp -d)/OpenPete.iconset"
    mkdir -p "$ICONSET"
    python3 tools/gen_dist_icon.py --png "$ICONSET/base.png" --png-size 1024 >/dev/null
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    rm "$ICONSET/base.png"
    iconutil -c icns "$ICONSET" -o "$R/OpenPete.icns"
fi

# OPENPETE_VERSION: this repo's release (set by ./make-app.sh / ./make-dmg.sh).
VERSION="${OPENPETE_VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
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
    $ICON_NAME_KEY
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION#v}</string>
    <key>CFBundleVersion</key>             <string>${VERSION#v}</string>
    <key>LSMinimumSystemVersion</key>      <string>$TARGET</string>
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

say "Checking every binary runs on macOS $TARGET"
BINS=("$C/Frameworks/"*.dylib "$R/recomp/tools/PSXRecomp" "$C/MacOS/$EXE")
for f in "${BINS[@]}"; do
    if newer_than_target "$f"; then
        die "${f#"$C/"} needs macOS $(minos "$f"), newer than $TARGET"
    fi
done

IDENTITY="${OPENPETE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    say "Signing (ad-hoc)"
    for f in "${BINS[@]}"; do codesign --force --sign - "$f"; done
    codesign --force --sign - "$APP"
else
    say "Signing with the hardened runtime ($IDENTITY)"
    # The engine dlopens the game module and code mods that are compiled on
    # the player's Mac, so library validation has to be off for it.
    SIGN=(codesign --force --options runtime --sign "$IDENTITY")
    [[ "$IDENTITY" == "-" ]] || SIGN+=(--timestamp)
    for f in "$C/Frameworks/"*.dylib "$R/recomp/tools/PSXRecomp"; do "${SIGN[@]}" "$f"; done
    "${SIGN[@]}" --entitlements tools/macos/OpenPete.entitlements "$C/MacOS/$EXE"
    "${SIGN[@]}" --entitlements tools/macos/OpenPete.entitlements "$APP"
fi
codesign --verify --strict --deep "$APP"

du -sh "$APP" | awk '{print "==> " $2 ": " $1}'
say "Done. Open it with:  open \"$APP\""

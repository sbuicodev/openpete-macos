#!/usr/bin/env bash
# Build a release disk image: a freshly built OpenPete.app (never one that has
# been run, which may hold local state) next to an Applications shortcut.
#
#   tools/macos/make_dmg.sh [output.dmg]   (default: build/OpenPete-<version>.dmg)
#
# Without a certificate the app is signed ad-hoc and Gatekeeper asks the player
# to allow it once (see the README). For a release that opens without that:
#   OPENPETE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#       signs the app (hardened runtime) and the image with that certificate;
#   OPENPETE_NOTARY_PROFILE=<profile>
#       also notarizes the image and staples the ticket. Create the profile
#       once with: xcrun notarytool store-credentials <profile>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if (( BASH_VERSINFO[0] < 4 )) && [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
fi
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$ROOT"
IDENTITY="${OPENPETE_SIGN_IDENTITY:-}"
PROFILE="${OPENPETE_NOTARY_PROFILE:-}"
if [[ -n "$PROFILE" && ( -z "$IDENTITY" || "$IDENTITY" == "-" ) ]]; then
    die "notarization needs OPENPETE_SIGN_IDENTITY set to a Developer ID certificate"
fi

STAGE="$(mktemp -d)/OpenPete"
trap 'rm -rf -- "$(dirname "$STAGE")"' EXIT
mkdir -p "$STAGE"
tools/macos/make_app.sh "$STAGE/OpenPete.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$STAGE/OpenPete.app/Contents/Info.plist")"
DMG="${1:-$ROOT/build/OpenPete-$VERSION.dmg}"
[[ "$DMG" == *.dmg ]] || die "output must end in .dmg: $DMG"
mkdir -p "$(dirname "$DMG")"

ln -s /Applications "$STAGE/Applications"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    cat > "$STAGE/If macOS blocks OpenPete.txt" <<'TXT'
OpenPete is not notarized by Apple, so the first time you open it macOS
says it cannot check it for malicious software. To allow it once:

1. Drag OpenPete into Applications and open it. Click Done (or OK).
2. Open System Settings > Privacy & Security, scroll down to the message
   about OpenPete and click Open Anyway. Confirm with your password or
   Touch ID, then click Open Anyway again.

On macOS 13 and 14 you can instead Control-click OpenPete in Applications,
choose Open, then click Open in the dialog.

After that it opens normally.
TXT
fi

say "Creating $(basename "$DMG")"
rm -f -- "$DMG"
hdiutil create -quiet -volname "OpenPete" -srcfolder "$STAGE" \
    -fs HFS+ -format ULFO -ov "$DMG"

if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    say "Signing the disk image"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if [[ -n "$PROFILE" ]]; then
    say "Notarizing (this uploads the image to Apple and waits)"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

hdiutil verify -quiet "$DMG"
du -h "$DMG" | awk '{print "==> " $2 ": " $1}'

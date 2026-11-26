#!/usr/bin/env bash
# Print the release notes for one version: its CHANGELOG.md section, plus an
# install footer. Used by .github/workflows/release.yml for the release body.
#
#   tools/release-notes.sh v0.1.0 [CHANGELOG.md]
#
# Fails when the changelog has no "## [0.1.0]" section or it is empty, so a
# release is never published without notes.
set -euo pipefail

TAG="${1:?usage: tools/release-notes.sh <tag> [CHANGELOG.md]}"
FILE="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"
VER="${TAG#v}"

NOTES="$(awk -v ver="$VER" '
    /^## \[/ {
        if (found) exit
        if (index($0, "## [" ver "]") == 1) { found = 1; next }
    }
    /^\[[^]]+\]: / { if (found) exit }   # link references at the end
    found { print }
' "$FILE" | sed -e '/./,$!d')"   # drop leading blank lines

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    echo "release-notes: no \"## [$VER]\" section with content in $FILE" >&2
    exit 1
fi

printf '%s\n' "$NOTES"
cat <<EOF

---

**Install:** download \`OpenPete-$TAG.dmg\` below, open it and drag OpenPete
to Applications. You need an Apple Silicon Mac with macOS 13 or later and your
own *Spyro the Dragon* (NTSC-U) disc image. If macOS says it cannot verify
OpenPete, see [allowing it past Gatekeeper](https://github.com/${GITHUB_REPOSITORY:-sbuicodev/openpete-macos}/blob/$TAG/README.md#if-macos-says-it-cant-verify-openpete).

Full history: [CHANGELOG.md](https://github.com/${GITHUB_REPOSITORY:-sbuicodev/openpete-macos}/blob/$TAG/CHANGELOG.md)
EOF

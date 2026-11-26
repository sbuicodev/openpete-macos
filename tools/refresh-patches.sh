#!/usr/bin/env bash
# After editing work/openpete: commit there (branch `macos`, or `arm64-fixes`
# inside third_party/PsyCross), then run this to re-export patches/ and copy
# edited overlay files back. Review with `git diff`, then commit this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$ROOT/work/openpete"
[[ -d "$W/.git" ]] || { echo "no work/openpete; run tools/setup.sh first" >&2; exit 1; }
PIN="$(git -C "$ROOT" rev-parse HEAD:upstream)"
PSY_PIN="$(git -C "$W" rev-parse "$PIN:third_party/PsyCross")"

rm -f "$ROOT"/patches/openpete/*.patch "$ROOT"/patches/psycross/*.patch
git -C "$W" format-patch --quiet --zero-commit --no-numbered "$PIN"..macos -o "$ROOT/patches/openpete"
git -C "$W/third_party/PsyCross" format-patch --quiet --zero-commit --no-numbered "$PSY_PIN"..arm64-fixes \
    -o "$ROOT/patches/psycross"

# Overlay files are new files, not patches: copy each one back.
(cd "$ROOT/overlay" && find . -type f) | while IFS= read -r f; do
    cp "$W/$f" "$ROOT/overlay/$f"
done

echo "patches: $(ls "$ROOT"/patches/openpete | wc -l | tr -d ' ') openpete," \
     "$(ls "$ROOT"/patches/psycross | wc -l | tr -d ' ') psycross; overlay refreshed"

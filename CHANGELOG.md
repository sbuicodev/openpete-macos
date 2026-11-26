# Changelog

All notable changes to OpenPete for macOS. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

Each `## [x.y.z]` section becomes the notes of the GitHub release tagged
`vx.y.z` (see "Releasing" in the README), so write it for players: what changed
for them, in Markdown. Add new entries under `[Unreleased]`, then rename that
heading to the version and date when you release.

## [Unreleased]

## [0.1.0] - 2026-11-26

First release: OpenPete, the PC port of Spyro the Dragon, running natively on
Apple Silicon Macs, packaged as a double-clickable app that rebuilds the game
from your own disc.

### Added

- **OpenPete.app** for macOS 13 or later on Apple Silicon. It contains no game
  code or data: on first launch it asks for your own *Spyro the Dragon*
  (NTSC-U) disc image and rebuilds the game for your Mac in about 30 seconds.
- Rendering through Vulkan on Metal (MoltenVK), including the GPU terrain path
  with macOS-specific shader variants.
- Mod API 13, the same as upstream OpenPete: code mods (`src/*.c`) are compiled
  on your Mac the first time they load, with the mod SDK shipped in the app.
  Backports upstream's `pad_read`, `pad_rumble` for players 2-4, `disc_path`
  and `read_sector`.
- A layered macOS app icon that stays in the Dock while the game runs.
- `./make-dmg.sh` builds the release disk image, with optional Developer ID
  signing and notarization.
- `./build.sh` builds a standalone developer build from your disc, or with no
  disc just the toolchain the app needs.

### Fixed

- Setup works without GitHub SSH keys, with macOS's built-in bash 3.2, and
  applies the patches to CRLF sources correctly.
- The launcher says "Mac" instead of "PC".
- The app no longer writes into its own bundle, which broke its code signature.

[Unreleased]: https://github.com/sbuicodev/openpete-macos/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sbuicodev/openpete-macos/releases/tag/v0.1.0

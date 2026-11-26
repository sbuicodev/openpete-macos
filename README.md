# OpenPete for macOS (Apple Silicon)

Native Apple Silicon support for [OpenPete](https://github.com/tyscorp/openpete),
the PC port of Spyro the Dragon, kept as a **patch series** on top of an
unmodified upstream checkout. This repository holds only the macOS work:
patches, a few new files, and build scripts. Upstream is a submodule pinned at
the commit the patches target.

Rendering is Vulkan on Metal through MoltenVK. Intel Macs are not supported.

> [!WARNING]
> **This port was made with AI assistance.** The patches, scripts and
> documentation were written largely by an AI coding assistant and have only
> been tested on one Mac with one disc. It is an experiment, not a stable or
> reliable release: expect bugs, crashes and breakage, and keep backups of your
> save files. It is not reviewed or supported by the OpenPete authors; please
> don't report problems with this port upstream.

## What you need

- An Apple Silicon Mac, [Homebrew](https://brew.sh) and Git.
- Your own disc image of **Spyro the Dragon, NTSC-U (SCUS-94228)** as a
  `.cue` + `.bin` pair, to play. Other regions and the Spyro 2 / 3 discs do
  not work; the disc is checked and refused if it is the wrong one. No build
  step needs it: the app asks for it on first launch, and `build.sh` takes it
  only if you give it.

No PSYQ SDK, Docker or MIPS toolchain is needed.

```bash
git clone --recursive https://github.com/sbuicodev/openpete-macos.git
cd openpete-macos
```

## Make the app

```bash
./make-app.sh            # -> build/OpenPete.app (about 19 MB)
```

On a fresh clone this first runs `./build.sh` without a disc (below) to set up
the toolchain, then builds the app.

The app contains **no game code or data**: just the engine, MoltenVK, OpenAL
Soft, the recompile kit (PSXRecomp, per-overlay function-address lists, a
six-file module source kit), the mod SDK, a generated icon and licence texts.

1. **First launch:** a splash asks for the disc image. Drag the `.cue`/`.bin`
   onto the window or the app icon, or press Space to browse.
2. The disc is copied into the library (`~/.local/share/openpete/library/`);
   the original file is not needed after that.
3. The game is recompiled into a module on that Mac (about 30 seconds). This
   needs Apple's Command Line Tools; if they are missing, macOS offers to
   install them and the app asks to be relaunched.
4. **Later launches** start the game directly.

Settings save to `~/.config/openpete/openpete.toml`; memory cards and logs
live in `~/.local/state/openpete/`. The app is ad-hoc signed, not notarized:
on another Mac, the first launch of a downloaded copy needs right-click →
**Open** (or allow it under System Settings → Privacy & Security).

## Build from the command line

```bash
./build.sh                                          # toolchain only
./build.sh "/path/to/Spyro the Dragon (USA).cue"    # and the game itself
```

`build.sh` runs `tools/setup.sh` (below), installs the Homebrew packages it
needs (CMake, Ninja, glslang, SPIRV-Tools, OpenAL Soft, MoltenVK, Python, GNU
bash/sed/grep/find/awk) and builds the PSXRecomp recompiler.

- **Without a disc** it stops there, after writing the two generated sources
  that come from the repo's manifests. That is everything `./make-app.sh`
  needs.
- **With a disc** it goes on to carve `PSX.EXE` and the 37 code overlays from
  it, check them against the decompilation's `sha256sum.txt`, translate the
  game's MIPS code to C and build a standalone game binary (the developer
  build: no app bundle, game code linked in). It prints the command to run
  it. Everything derived from your disc stays under `work/` (gitignored).

Default keys: arrow keys or a gamepad to move, **C** jump, **X** charge,
**V** flame, **Z** look, **Return** start, **O** settings menu, **F7** pause,
**Alt+Enter** fullscreen, **Escape** quit (in the app, Escape opens the menu
instead).

## Mods

Mod API **13**, the same version upstream OpenPete uses now: mods written for
upstream at API 13 or earlier load here. Code mods (`src/*.c`) are compiled on
the Mac the first time they load, with Apple's Command Line Tools, against
the mod SDK shipped in the app; asset-only mods need nothing. Put each mod in
its own folder under `~/.local/share/openpete/mods/`. Mods that depend on
engine features added upstream after the pinned commit may still not work.

## How this repository works

```
upstream/        submodule: tyscorp/openpete at the pinned commit (untouched)
patches/openpete changes to existing upstream files, one topic per patch
patches/psycross arm64 fixes to upstream's PsyCross
overlay/         new files, copied into the tree at their relative paths
tools/setup.sh   builds work/openpete: upstream + patches + overlay
tools/refresh-patches.sh   re-exports patches/ and overlay/ from work/openpete
work/            the patched checkout and its builds (gitignored)
```

`tools/setup.sh` clones `upstream/` into `work/openpete`, fetches the
submodules the build needs, applies `patches/openpete` with `git am` (each
patch becomes a commit on branch `macos`), applies `patches/psycross` inside
`third_party/PsyCross`, and copies `overlay/` in. Upstream pins its PsyCross
fork at a URL that is not public; the same commit is published as
[tyscorp/psycross-archive](https://github.com/tyscorp/psycross-archive), which
setup uses instead.

To change something: edit in `work/openpete`, commit there (on `macos`, or on
`arm64-fixes` inside `third_party/PsyCross`), run `tools/refresh-patches.sh`,
and commit the updated `patches/` and `overlay/` here.

| Patch | Topic |
|---|---|
| 0001 | psxrecomp: rename a colliding `BasicBlock` struct (crashed on macOS) |
| 0002 | core: macOS executable path; inside an `.app` the install directory is `Contents/Resources` |
| 0003 | runtime: no `clock_nanosleep` on macOS |
| 0004 | rhi: load MoltenVK directly, enable `VK_KHR_portability_subset`, allow the GPU terrain path on Apple |
| 0005 | rhi: build fp32 variants of the terrain shaders (Metal has no fp64) with `overlay/tools/macos/fp32_shader.py` |
| 0006 | first launch on macOS: module link flags, Command Line Tools check, free-camera call through the dispatcher |
| 0007 | build: `macos-arm64` and `macos-arm64-app` CMake presets |
| 0008 | mods: `pad_read` (upstream, API 12) |
| 0009 | mods: `pad_rumble` for players 2-4 (upstream, API 12; without its test mod and script) |
| 0010 | mods: `disc_path` (upstream, API 12) |
| 0011 | mods: `read_sector`, API 13 (upstream's call, implemented without upstream's disc-reader rework) |
| 0012 | mods: compile code mods on macOS; build-time mod compile on; SDK in the `.app` |
| 0013 | runtime: inside an `.app` keep the bundle's Dock icon (`SDL_SetWindowIcon` would replace it) |
| 0014 | build: a shared-linkage (`.app`) build configures without recompiled output, so it needs no disc |
| 0015 | first launch: on macOS the splash and build progress say "Mac", not "PC" |
| psycross 0001 | arm64 primitive layout, `<stdlib.h>`, a half-float cast |

Notes on the port:

- **fp32 terrain:** upstream's GPU terrain shaders compute in `double` to match
  the CPU terrain walk bit for bit. The macOS variants keep the uniform layout
  (offsets pinned from the original SPIR-V) and convert in the shader; they
  match the CPU walk visually rather than bit-exactly (at most 0.01% of pixels
  differ in A/B captures). `--terrain-cache 0` falls back to the CPU walk.
- **Fully recompiled path:** builds use upstream's release configuration,
  `OPENPETE_SKIP_DECOMP=ON`, where every game function runs as recompiled
  MIPS code.

## Licensing

- **Noncommercial only.** OpenPete at the pinned commit and PSXRecomp are under
  PolyForm Noncommercial 1.0.0. The patches here modify that code, so this
  repository is under the same licence (`LICENSE`). It is a personal,
  noncommercial project and may not be sold or used commercially.
- **No game content.** This repository contains no data from any game disc:
  no executable, overlays, textures, audio or video, and no recompiled game
  code. The two symbol manifests in `overlay/` hold only symbol names from the
  CC0 decompilation plus addresses and sizes. Every user supplies their own
  legally obtained disc.
- **No prebuilt game binaries.** A built game executable embeds code
  recompiled from the disc, so it is never published. `OpenPete.app` contains
  no game code and recompiles the player's own disc on first launch.
- **No PSYQ SDK** is included or required.
- Third-party components keep their own licences; see upstream's `NOTICE.md`.
  The app bundles OpenAL Soft (LGPL, dynamically linked and replaceable),
  MoltenVK (Apache-2.0) and PSXRecomp, with their licence texts.

*Spyro the Dragon* and related marks are trademarks of their respective owners
and are used only to identify the game this software is compatible with. This
project is not affiliated with or endorsed by Sony Interactive Entertainment,
Insomniac Games, Activision, or the OpenPete authors.

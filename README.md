# OpenPete for macOS (Apple Silicon)

Native Apple Silicon support for [OpenPete](https://github.com/tyscorp/openpete),
the PC port of Spyro the Dragon, kept as a **patch series** on top of an
unmodified upstream checkout. This repository holds only the macOS work:
patches, a few new files, and build scripts. Upstream is a submodule pinned at
the commit the patches target.

Rendering is Vulkan on Metal through MoltenVK. Intel Macs are not supported.

## What you need

- An Apple Silicon Mac, [Homebrew](https://brew.sh) and Git.
- Your own disc image of **Spyro the Dragon, NTSC-U (SCUS-94228)** as a
  `.cue` + `.bin` pair. Other regions and the Spyro 2 / 3 discs do not work;
  the build checks the disc and stops if it is the wrong one.

No PSYQ SDK, Docker or MIPS toolchain is needed.

## Build and play

```bash
git clone --recursive https://github.com/<you>/openpete-macos.git
cd openpete-macos
./build.sh "/path/to/Spyro the Dragon (USA).cue"
```

`build.sh` runs `tools/setup.sh` (below), then:

1. installs the Homebrew packages it needs (CMake, Ninja, glslang,
   SPIRV-Tools, OpenAL Soft, MoltenVK, Python, GNU bash/sed/grep/find/awk);
2. carves `PSX.EXE` and the 37 code overlays from your disc and checks them
   against the decompilation's `sha256sum.txt`;
3. builds the PSXRecomp recompiler, translates the game's MIPS code to C and
   builds the game.

It prints the command to run the game. Everything derived from your disc stays
under `work/` (gitignored).

Default keys: arrow keys or a gamepad to move, **C** jump, **X** charge,
**V** flame, **Z** look, **Return** start, **O** settings menu, **F7** pause,
**Alt+Enter** fullscreen, **Escape** quit (the app below opens the menu
instead).

## Make a double-clickable app

```bash
./make-app.sh            # -> build/OpenPete.app (about 19 MB)
```

The app contains **no game code or data**: just the engine, MoltenVK, OpenAL
Soft, the recompile kit (PSXRecomp, per-overlay function-address lists, a
six-file module source kit), a generated icon and licence texts.

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

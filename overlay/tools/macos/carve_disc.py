#!/usr/bin/env python3
"""Carve the recompiler's inputs out of the user's own Spyro 1 disc.

Writes PSX.EXE and every code overlay into the decompilation's build layout
(games/spyro-1/spyro-1/build/PSX.EXE, build/wad/<name>.ovl), so the recompile
pipeline runs without building the decompilation (no Docker, no MIPS
toolchain). The bytes are verified against the decomp's sha256sum.txt: a disc
that is not NTSC-U SCUS-94228 fails here instead of producing a broken build.

WAD layout (games/spyro-1/dist/recomp_extract.cpp, spyro-1/include/wad.h):
the header is the first 2048 bytes of WAD.WAD at LBA 37; each entry is
{int32 byte_offset, int32 byte_length}; titlescreen at +16, 36 level slots
{overlay, data} from +72 (16 bytes each), credits at +648.

usage: carve_disc.py <disc.cue|disc.bin> [decomp_dir]
"""
import hashlib
import re
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import iso_extract  # noqa: E402  (ISO9660 reader for MODE2/2352 images)

WAD_SECTOR = 37
TITLESCREEN_OFF, LEVEL_ENTRY_OFF, CREDITS_OFF = 16, 72, 648


def resolve_bin(disc: Path) -> Path:
    if disc.suffix.lower() == ".cue":
        for line in disc.read_text(errors="replace").splitlines():
            if line.strip().upper().startswith("FILE") and '"' in line:
                return disc.parent / line.split('"')[1]
        sys.exit(f"carve: no FILE line in {disc}")
    return disc


def decomp_levels(decomp: Path) -> list:
    """The decomp's LEVELS list (Makefile), in WAD slot order."""
    mk = (decomp / "Makefile").read_text()
    block = re.search(r"^LEVELS\s*=\s*\\\n((?:\s+\S+\s*\\?\n)+)", mk, re.M)
    if not block:
        sys.exit("carve: LEVELS not found in the decomp Makefile")
    return [w for w in block.group(1).split() if w != "\\"]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    disc = resolve_bin(Path(sys.argv[1]).expanduser())
    root = HERE.parents[1]
    decomp = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "games/spyro-1/spyro-1"
    build = decomp / "build"
    (build / "wad").mkdir(parents=True, exist_ok=True)

    levels = decomp_levels(decomp)
    with open(disc, "rb") as f:
        def extent(lba: int, size: int) -> bytes:
            return iso_extract.read_extent(f, lba, size)

        exe = None
        pvd = iso_extract.read_sector(f, 16)
        if pvd[1:6] != b"CD001":
            sys.exit(f"carve: {disc} is not a MODE2/2352 ISO9660 image")
        root_rec = pvd[156:156 + 34]
        rlba, rsize = struct.unpack_from("<I", root_rec, 2)[0], struct.unpack_from("<I", root_rec, 10)[0]
        for path, lba, size, is_dir in iso_extract.walk(f, rlba, rsize):
            if path.upper() == "/SCUS_942.28" and not is_dir:
                exe = extent(lba, size)
        if exe is None:
            sys.exit("carve: SCUS_942.28 not found — this tool needs the NTSC-U disc (SCUS-94228)")
        (build / "PSX.EXE").write_bytes(exe)

        hdr = extent(WAD_SECTOR, 2048)

        def carve(off: int, name: str) -> bool:
            boff, blen = struct.unpack_from("<ii", hdr, off)
            if blen <= 0:
                return False
            (build / "wad" / name).write_bytes(extent(WAD_SECTOR + boff // 2048, blen))
            return True

        for slot, level in enumerate(levels):
            carve(LEVEL_ENTRY_OFF + slot * 16, f"{level}_code.ovl")
        carve(TITLESCREEN_OFF, "titlescreen_code.ovl")
        carve(CREDITS_OFF, "credits.ovl")

    bad = 0
    for line in (decomp / "sha256sum.txt").read_text().splitlines():
        want, rel = line.split()
        got = hashlib.sha256((decomp / rel).read_bytes()).hexdigest()
        if got != want.lower():
            bad += 1
            print(f"carve: MISMATCH {rel}")
    total = len((decomp / "sha256sum.txt").read_text().splitlines())
    print(f"carve: {total - bad}/{total} files match sha256sum.txt -> {build}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

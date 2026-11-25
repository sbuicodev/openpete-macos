#!/usr/bin/env python3
"""Derive an fp32 (Metal-compatible) variant of a GLSL shader that uses fp64.

Metal has no 64-bit floats, so MoltenVK cannot translate shaders that use
`double`. This keeps the CPU side untouched: the uniform block still holds
real doubles at the original std140 offsets. The variant

  * redeclares the block with an explicit `layout(offset = N)` per member,
    taking N from the ORIGINAL shader's SPIR-V (glslangValidator + spirv-dis),
    so the two layouts cannot drift;
  * stores each dvec2 as a uvec4 (16 B) and each dvec4 as two uvec4 (32 B),
    i.e. the raw IEEE-754 bit patterns, and reads them through d2f*();
  * turns every remaining double/dvecN into float/vecN and drops `lf`.

usage: fp32_shader.py <src.glsl> <out.glsl> --block NAME --compile-src FILE
       [--include-dir DIR] [--define X=Y ...]
`--compile-src` is the top-level shader whose SPIR-V carries the block (the
file itself for a stage, the including stage for a .glsl include).
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HELPERS = r"""
/* fp32 port (tools/macos/fp32_shader.py): doubles arrive as raw bit pairs. */
float op_d2f(uvec2 b) {
    uint hi = b.y, lo = b.x;
    uint sgn = hi & 0x80000000u;
    int  e   = int((hi >> 20) & 0x7FFu);
    if (e == 0) return uintBitsToFloat(sgn);                       /* +-0, denormals */
    uint m = ((hi & 0xFFFFFu) << 3) | (lo >> 29);                   /* top 23 bits */
    if (e == 0x7FF) return uintBitsToFloat(sgn | 0x7F800000u | (m != 0u ? 0x400000u : 0u));
    int fe = e - 1023 + 127;
    m += (lo >> 28) & 1u;                                           /* round half up */
    if (m == 0x800000u) { m = 0u; fe += 1; }
    if (fe >= 255) return uintBitsToFloat(sgn | 0x7F800000u);
    if (fe <= 0)   return uintBitsToFloat(sgn);
    return uintBitsToFloat(sgn | (uint(fe) << 23) | m);
}
vec2 op_d2f2(uvec4 v) { return vec2(op_d2f(v.xy), op_d2f(v.zw)); }
vec4 op_d2f4(uvec4 a, uvec4 b) {
    return vec4(op_d2f(a.xy), op_d2f(a.zw), op_d2f(b.xy), op_d2f(b.zw));
}
"""


def spirv_offsets(compile_src: Path, include_dir, defines, block: str):
    with tempfile.TemporaryDirectory() as td:
        spv = Path(td) / "s.spv"
        cmd = ["glslangValidator", "-V", f"-I{include_dir}", str(compile_src), "-o", str(spv)]
        for d in defines:
            cmd.insert(2, f"-D{d}")
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"fp32_shader: glslang failed on {compile_src}:\n{r.stdout}{r.stderr}")
        dis = subprocess.run(["spirv-dis", str(spv)], capture_output=True, text=True, check=True).stdout
    ident = re.search(rf'OpName (%\S+) "{block}"', dis)
    if not ident:
        sys.exit(f"fp32_shader: block {block} not found in {compile_src}")
    tid = re.escape(ident.group(1))
    offs = {int(i): int(o) for i, o in re.findall(rf"OpMemberDecorate {tid} (\d+) Offset (\d+)", dis)}
    return [offs[i] for i in sorted(offs)]


DECL = re.compile(r"^\s*(\w+)\s+(\w+)\s*(?:\[\s*(\d+)\s*\])?\s*$")


def rewrite_block(body: str, offsets):
    """Return (new block body, {member: (kind, count)} for double members)."""
    clean = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    clean = re.sub(r"//[^\n]*", "", clean)
    decls = [d for d in (x.strip() for x in clean.split(";")) if d]
    if len(decls) != len(offsets):
        sys.exit(f"fp32_shader: {len(decls)} members parsed, SPIR-V has {len(offsets)}")
    out, dmembers = [], {}
    for decl, off in zip(decls, offsets):
        m = DECL.match(decl)
        if not m:
            sys.exit(f"fp32_shader: cannot parse block member '{decl}'")
        ty, name, n = m.group(1), m.group(2), m.group(3)
        count = int(n) if n else 0
        if ty == "dvec2":
            dmembers[name] = ("d2", count)
            out.append(f"    layout(offset = {off}) uvec4 {name}" + (f"[{count}]" if count else "") + ";")
        elif ty == "dvec4":
            dmembers[name] = ("d4", count)
            out.append(f"    layout(offset = {off}) uvec4 {name}[{2 * (count or 1)}];")
        elif ty in ("double", "dvec3") or ty.startswith("dmat"):
            sys.exit(f"fp32_shader: unsupported block member type {ty} {name}")
        else:
            out.append(f"    layout(offset = {off}) {decl};")
    return "\n".join(out) + "\n", dmembers


def match_bracket(s: str, i: int) -> int:
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "[":
            depth += 1
        elif s[j] == "]":
            depth -= 1
            if depth == 0:
                return j
    sys.exit("fp32_shader: unbalanced [ in member access")


def rewrite_accesses(src: str, inst: str, dmembers) -> str:
    for name, (kind, count) in dmembers.items():
        pat = re.compile(rf"\b{re.escape(inst)}\.{re.escape(name)}\b")
        out, pos = [], 0
        for m in pat.finditer(src):
            if m.start() < pos:
                continue
            out.append(src[pos:m.start()])
            end = m.end()
            ref = f"{inst}.{name}"
            if count:
                if end >= len(src) or src[end] != "[":
                    sys.exit(f"fp32_shader: array {name} used without index")
                close = match_bracket(src, end)
                idx = src[end + 1:close]
                end = close + 1
                if kind == "d2":
                    out.append(f"op_d2f2({ref}[{idx}])")
                else:
                    out.append(f"op_d2f4({ref}[2*({idx})], {ref}[2*({idx})+1])")
            else:
                out.append(f"op_d2f2({ref})" if kind == "d2" else f"op_d2f4({ref}[0], {ref}[1])")
            pos = end
        out.append(src[pos:])
        src = "".join(out)
    return src


def to_fp32(src: str) -> str:
    src = re.sub(r"^\s*#extension\s+GL_ARB_gpu_shader_fp64\s*:\s*\w+\s*$", "", src, flags=re.M)
    src = re.sub(r"\bdvec([234])\b", r"vec\1", src)
    src = re.sub(r"\bdmat([234])\b", r"mat\1", src)
    src = re.sub(r"\bdouble\b", "float", src)
    src = re.sub(r"(\b\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)(?:lf|LF)\b", r"\1", src)
    return src


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--block", required=True)
    ap.add_argument("--compile-src", required=True)
    ap.add_argument("--include-dir", default=".")
    ap.add_argument("--define", action="append", default=[])
    a = ap.parse_args()

    src = Path(a.src).read_text()
    offsets = spirv_offsets(Path(a.compile_src), a.include_dir, a.define, a.block)
    bm = re.search(rf"(uniform\s+{a.block}\s*\{{)(.*?)(\}}\s*(\w+)\s*;)", src, re.S)
    if not bm:
        sys.exit(f"fp32_shader: uniform block {a.block} not found in {a.src}")
    body, dmembers = rewrite_block(bm.group(2), offsets)
    inst = bm.group(4)
    src = src[:bm.start(2)] + body + src[bm.end(2):]
    # Helpers right after the block declaration (the block's end).
    tail = src.index(bm.group(3), bm.start(1)) + len(bm.group(3))
    src = src[:tail] + "\n" + HELPERS + src[tail:]
    src = rewrite_accesses(src, inst, dmembers)
    src = to_fp32(src)
    Path(a.out).write_text(src)


if __name__ == "__main__":
    main()

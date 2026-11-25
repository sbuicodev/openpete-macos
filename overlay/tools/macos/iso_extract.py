#!/usr/bin/env python3
"""Minimal ISO9660 extractor for a MODE2/2352 PSX .bin (Form 1 data sectors).

usage: iso_extract.py <disc.bin> list
       iso_extract.py <disc.bin> get <ISO_PATH> <out_file>
"""
import struct
import sys

SECTOR = 2352
DATA_OFF = 24  # 12 sync + 4 header + 8 subheader (Mode 2 Form 1)


def read_sector(f, lba):
    f.seek(lba * SECTOR + DATA_OFF)
    return f.read(2048)


def read_extent(f, lba, size):
    out = bytearray()
    n = (size + 2047) // 2048
    for i in range(n):
        out += read_sector(f, lba + i)
    return bytes(out[:size])


def parse_dir(f, lba, size):
    data = read_extent(f, lba, size)
    entries = []
    pos = 0
    while pos < len(data):
        ln = data[pos]
        if ln == 0:
            pos = (pos // 2048 + 1) * 2048
            continue
        rec = data[pos:pos + ln]
        ext = struct.unpack_from('<I', rec, 2)[0]
        sz = struct.unpack_from('<I', rec, 10)[0]
        flags = rec[25]
        nlen = rec[32]
        name = rec[33:33 + nlen]
        if name not in (b'\x00', b'\x01'):
            entries.append((name.decode('ascii').split(';')[0], ext, sz, bool(flags & 2)))
        pos += ln
    return entries


def walk(f, lba, size, prefix=''):
    for name, ext, sz, is_dir in parse_dir(f, lba, size):
        path = prefix + '/' + name
        yield path, ext, sz, is_dir
        if is_dir:
            yield from walk(f, ext, sz, path)


def main():
    disc = sys.argv[1]
    with open(disc, 'rb') as f:
        pvd = read_sector(f, 16)
        assert pvd[1:6] == b'CD001', 'no ISO9660 PVD'
        root = pvd[156:156 + 34]
        rlba = struct.unpack_from('<I', root, 2)[0]
        rsize = struct.unpack_from('<I', root, 10)[0]
        if sys.argv[2] == 'list':
            for path, ext, sz, is_dir in walk(f, rlba, rsize):
                print(f"{'D' if is_dir else 'F'} {ext:8d} {sz:10d} {path}")
        elif sys.argv[2] == 'get':
            want = sys.argv[3].upper().lstrip('/')
            for path, ext, sz, is_dir in walk(f, rlba, rsize):
                if path.lstrip('/').upper() == want and not is_dir:
                    with open(sys.argv[4], 'wb') as o:
                        o.write(read_extent(f, ext, sz))
                    print(f'wrote {sys.argv[4]} ({sz} bytes)')
                    return
            sys.exit(f'not found: {want}')


if __name__ == '__main__':
    main()

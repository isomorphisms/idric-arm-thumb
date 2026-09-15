#!/usr/bin/env python3
"""Independent checks for the structural fields owned by the direct writer."""

import hashlib
import pathlib
import struct
import sys
import zlib


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: check_dex.py classes.dex")
    path = pathlib.Path(sys.argv[1])
    data = path.read_bytes()
    if data[:8] != b"dex\n035\0":
        fail("not deterministic DEX 035 magic")
    if len(data) < 112 or u32(data, 36) != 112:
        fail("invalid header size")
    if u32(data, 32) != len(data):
        fail("declared file size does not match bytes")
    if u32(data, 40) != 0x12345678:
        fail("invalid endian tag")
    if data[12:32] != hashlib.sha1(data[32:]).digest():
        fail("SHA-1 signature mismatch")
    if u32(data, 8) != (zlib.adler32(data[12:]) & 0xFFFFFFFF):
        fail("Adler-32 checksum mismatch")

    file_size = len(data)
    sections = {
        "string_ids": (u32(data, 56), u32(data, 60), 4),
        "type_ids": (u32(data, 64), u32(data, 68), 4),
        "proto_ids": (u32(data, 72), u32(data, 76), 12),
        "field_ids": (u32(data, 80), u32(data, 84), 8),
        "method_ids": (u32(data, 88), u32(data, 92), 8),
        "class_defs": (u32(data, 96), u32(data, 100), 32),
    }
    for name, (size, offset, width) in sections.items():
        if size == 0:
            if offset != 0:
                fail(f"empty {name} has a nonzero offset")
        elif offset < 112 or offset + size * width > file_size:
            fail(f"{name} lies outside the file")

    data_size, data_offset = u32(data, 104), u32(data, 108)
    if data_offset < 112 or data_offset + data_size != file_size:
        fail("data section does not reach the file end")
    map_offset = u32(data, 52)
    if map_offset < data_offset or map_offset + 4 > file_size:
        fail("map list offset lies outside data")
    map_size = u32(data, map_offset)
    if map_offset + 4 + 12 * map_size > file_size:
        fail("map list extends beyond the file")
    map_offsets = [u32(data, map_offset + 4 + 12 * index + 8)
                   for index in range(map_size)]
    if map_offsets != sorted(map_offsets):
        fail("map entries are not ordered by file offset")

    print("DEX magic/version       PASS (035)")
    print("DEX header/layout       PASS")
    print("DEX SHA-1 signature     PASS")
    print("DEX Adler-32 checksum   PASS")


if __name__ == "__main__":
    main()

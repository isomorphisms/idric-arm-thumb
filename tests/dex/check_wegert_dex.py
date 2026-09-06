#!/usr/bin/env python3
import hashlib
import struct
import sys
import zlib
from pathlib import Path

WEGERT = "Lorg/isomorphisms/wegert/WegertActivity;"
NATIVE_ACTIVITY = "Landroid/app/NativeActivity;"
BUNDLE = "Landroid/os/Bundle;"
STRING = "Ljava/lang/String;"
SYSTEM = "Ljava/lang/System;"

def fail(message):
    raise SystemExit("FAIL: " + message)

def u16(data, offset):
    return struct.unpack_from("<H", data, offset)[0]

def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]

def uleb(data, offset):
    value = 0
    shift = 0
    while True:
        if offset >= len(data):
            fail("truncated ULEB128")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7f) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
        if shift > 35:
            fail("oversized ULEB128")

def read_string(data, offset):
    utf16_size, offset = uleb(data, offset)
    end = data.find(b"\0", offset)
    if end < 0:
        fail("unterminated string_data_item")
    raw = data[offset:end]
    try:
        value = raw.decode("ascii")
    except UnicodeDecodeError:
        fail("fixture unexpectedly contains non-ASCII modified UTF-8")
    if len(value) != utf16_size:
        fail("fixture string UTF-16 length mismatch")
    return value

def code_units(data, code_off):
    registers = u16(data, code_off)
    incoming = u16(data, code_off + 2)
    outgoing = u16(data, code_off + 4)
    tries = u16(data, code_off + 6)
    debug_info = u32(data, code_off + 8)
    size = u32(data, code_off + 12)
    if tries != 0 or debug_info != 0:
        fail("fixture code item unexpectedly has tries/debug info")
    units = [u16(data, code_off + 16 + 2 * i) for i in range(size)]
    return (registers, incoming, outgoing, units)

def main(path):
    data = Path(path).read_bytes()
    if data[:8] != b"dex\n035\0":
        fail("DEX 035 magic")
    if u32(data, 32) != len(data):
        fail("file_size does not match bytes on disk")
    if u32(data, 36) != 112:
        fail("header_size is not 112")
    if u32(data, 40) != 0x12345678:
        fail("endian tag")
    if hashlib.sha1(data[32:]).digest() != data[12:32]:
        fail("SHA-1 signature")
    if (zlib.adler32(data[12:]) & 0xffffffff) != u32(data, 8):
        fail("Adler-32 checksum")

    string_count, string_ids_off = u32(data, 56), u32(data, 60)
    type_count, type_ids_off = u32(data, 64), u32(data, 68)
    proto_count, proto_ids_off = u32(data, 72), u32(data, 76)
    field_count = u32(data, 80)
    method_count, method_ids_off = u32(data, 88), u32(data, 92)
    class_count, class_defs_off = u32(data, 96), u32(data, 100)

    if (string_count, type_count, proto_count, field_count, method_count, class_count) != (14, 7, 4, 0, 7, 1):
        fail("unexpected fixed-table counts")

    strings = [
        read_string(data, u32(data, string_ids_off + 4 * i))
        for i in range(string_count)
    ]
    expected_strings = [
        "<clinit>", "<init>", "I", NATIVE_ACTIVITY, BUNDLE, STRING, SYSTEM,
        WEGERT, "V", "VL", "jniProbe", "loadLibrary", "onCreate", "wegert",
    ]
    if strings != expected_strings:
        fail("string pool does not match Wegert oracle")

    types = [strings[u32(data, type_ids_off + 4 * i)] for i in range(type_count)]
    expected_types = ["I", NATIVE_ACTIVITY, BUNDLE, STRING, SYSTEM, WEGERT, "V"]
    if types != expected_types:
        fail("type_ids do not match Wegert oracle")

    protos = []
    for i in range(proto_count):
        off = proto_ids_off + 12 * i
        shorty = strings[u32(data, off)]
        result = types[u32(data, off + 4)]
        params_off = u32(data, off + 8)
        params = []
        if params_off:
            size = u32(data, params_off)
            params = [types[u16(data, params_off + 4 + 2 * j)] for j in range(size)]
        protos.append((shorty, result, tuple(params)))
    expected_protos = [
        ("I", "I", ()),
        ("V", "V", ()),
        ("VL", "V", (BUNDLE,)),
        ("VL", "V", (STRING,)),
    ]
    if protos != expected_protos:
        fail("proto_ids do not match Wegert oracle")

    methods = []
    for i in range(method_count):
        off = method_ids_off + 8 * i
        cls = types[u16(data, off)]
        proto = u16(data, off + 2)
        name = strings[u32(data, off + 4)]
        methods.append((cls, name, proto))
    expected_methods = [
        (NATIVE_ACTIVITY, "<init>", 1),
        (NATIVE_ACTIVITY, "onCreate", 2),
        (SYSTEM, "loadLibrary", 3),
        (WEGERT, "<clinit>", 1),
        (WEGERT, "<init>", 1),
        (WEGERT, "jniProbe", 0),
        (WEGERT, "onCreate", 2),
    ]
    if methods != expected_methods:
        fail("method_ids do not match Wegert oracle")

    class_idx = u32(data, class_defs_off)
    access = u32(data, class_defs_off + 4)
    superclass_idx = u32(data, class_defs_off + 8)
    interfaces_off = u32(data, class_defs_off + 12)
    source_file_idx = u32(data, class_defs_off + 16)
    annotations_off = u32(data, class_defs_off + 20)
    class_data_off = u32(data, class_defs_off + 24)
    static_values_off = u32(data, class_defs_off + 28)
    if types[class_idx] != WEGERT or access != 0x1 or types[superclass_idx] != NATIVE_ACTIVITY:
        fail("class/superclass/access flags")
    if interfaces_off or annotations_off or static_values_off or source_file_idx != 0xffffffff:
        fail("unexpected class metadata")

    offset = class_data_off
    static_fields, offset = uleb(data, offset)
    instance_fields, offset = uleb(data, offset)
    direct_count, offset = uleb(data, offset)
    virtual_count, offset = uleb(data, offset)
    if (static_fields, instance_fields, direct_count, virtual_count) != (0, 0, 3, 1):
        fail("class_data counts")

    def read_methods(count):
        nonlocal offset
        result = []
        previous = 0
        for _ in range(count):
            diff, offset = uleb(data, offset)
            flags, offset = uleb(data, offset)
            code_off, offset = uleb(data, offset)
            method_index = previous + diff
            result.append((method_index, flags, code_off))
            previous = method_index
        return result

    direct = read_methods(3)
    virtual = read_methods(1)
    if [(idx, flags) for idx, flags, _ in direct] != [
        (3, 0x10008), (4, 0x10001), (5, 0x109)
    ]:
        fail("direct method declarations/access flags")
    if [(idx, flags) for idx, flags, _ in virtual] != [(6, 0x4)]:
        fail("virtual method declaration/access flags")
    if direct[2][2] != 0:
        fail("native jniProbe unexpectedly has code")

    clinit = code_units(data, direct[0][2])
    init = code_units(data, direct[1][2])
    oncreate = code_units(data, virtual[0][2])

    if clinit[:3] != (1, 0, 1):
        fail("<clinit> register/in/out counts")
    if clinit[3] != [0x001a, 13, 0x1071, 2, 0, 0x000e]:
        fail("<clinit> is not const-string/invoke-static/return-void")

    if init[:3] != (1, 1, 1):
        fail("<init> register/in/out counts")
    if init[3] != [0x1070, 0, 0, 0x000e]:
        fail("<init> is not NativeActivity invoke-direct/return-void")

    if oncreate[:3] != (2, 2, 2):
        fail("onCreate register/in/out counts")
    if oncreate[3] != [0x0071, 5, 0, 0x206f, 1, 0x0010, 0x000e]:
        fail("onCreate is not jniProbe/invoke-super/return-void")

    print("PASS: Wegert direct DEX structure")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_wegert_dex.py classes.dex")
    main(sys.argv[1])

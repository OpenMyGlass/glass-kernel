#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare a built kernel module (.ko, ELF32 ARM) with the stock one.

Usage: compare_ko.py STOCK.ko BUILT.ko
Exit status: 0 match, 1 differences, 2 unreadable input.
"""
import re
import struct
import sys


class ModuleError(Exception):
    pass


def _cstr(buf, off):
    end = buf.find(b"\0", off)
    if end < 0:
        end = len(buf)
    return buf[off:end].decode("latin-1")


def _sections(data):
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise ModuleError("not an ELF file")
    if data[4] != 1:
        raise ModuleError("not an ELF32 file")
    if data[5] != 1:
        raise ModuleError("not a little-endian ELF file")
    try:
        shoff, = struct.unpack_from("<I", data, 32)
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 46)
        if shoff == 0 or shnum == 0 or shentsize < 40 or shstrndx >= shnum:
            raise ModuleError("missing section headers")
        hdrs = [struct.unpack_from("<IIIIIIIIII", data, shoff + i * shentsize)
                for i in range(shnum)]
    except struct.error:
        raise ModuleError("truncated ELF file")

    def body(h):
        start, size = h[4], h[5]
        if h[1] == 8:  # SHT_NOBITS
            return b""
        if start + size > len(data):
            raise ModuleError("section extends past end of file")
        return data[start:start + size]

    names = body(hdrs[shstrndx])
    return [(_cstr(names, h[0]), h, body(h)) for h in hdrs]


def read_module(data):
    secs = _sections(data)
    by_name = {n: (h, b) for n, h, b in secs}

    modinfo = {}
    if ".modinfo" in by_name:
        for item in by_name[".modinfo"][1].split(b"\0"):
            if b"=" in item:
                k, v = item.decode("latin-1").split("=", 1)
                modinfo.setdefault(k, []).append(v)

    versions = {}
    if "__versions" in by_name:
        blob = by_name["__versions"][1]
        for off in range(0, len(blob) - 63, 64):
            crc, = struct.unpack_from("<I", blob, off)
            versions[_cstr(blob[off + 4:off + 64], 0)] = crc

    undefined = set()
    if ".symtab" in by_name:
        h, blob = by_name[".symtab"]
        if h[6] >= len(secs):
            raise ModuleError("bad .symtab link")
        strs = secs[h[6]][2]
        for off in range(0, len(blob) - 15, 16):
            st_name, _v, _s, info, _o, shndx = struct.unpack_from("<IIIBBH", blob, off)
            if shndx == 0 and (info >> 4) in (1, 2) and st_name:
                undefined.add(_cstr(strs, st_name))

    m = re.search(rb"SGX_DDK_Android[^\0]*", data)
    ddk = m.group(0).decode("latin-1") if m else None
    return {"modinfo": modinfo, "versions": versions,
            "undefined": sorted(undefined), "ddk": ddk}


def _vermagic(mod):
    vals = mod["modinfo"].get("vermagic")
    if not vals:
        return None
    v = vals[0]
    return re.sub(r"^(3\.4\.94)\S*", r"\1", v)


def compare(stock, built):
    diffs = []
    sv, bv = _vermagic(stock), _vermagic(built)
    if sv != bv:
        diffs.append("vermagic differs: stock %r, built %r" % (sv, bv))
    if stock["ddk"] != built["ddk"]:
        diffs.append("DDK string differs: stock %r, built %r" % (stock["ddk"], built["ddk"]))
    s, b = set(stock["undefined"]), set(built["undefined"])
    for n in sorted(s - b):
        diffs.append("undefined symbol only in stock: %s" % n)
    for n in sorted(b - s):
        diffs.append("undefined symbol only in built: %s" % n)
    for n in sorted(set(stock["versions"]) & set(built["versions"])):
        if stock["versions"][n] != built["versions"][n]:
            diffs.append("CRC differs for %s: stock 0x%08x, built 0x%08x"
                         % (n, stock["versions"][n], built["versions"][n]))
    for key in ("parm", "parmtype"):
        def names(m):
            return {v.split(":", 1)[0] for v in m["modinfo"].get(key, [])}
        so, bo = names(stock), names(built)
        for n in sorted(so - bo):
            diffs.append("%s only in stock: %s" % (key, n))
        for n in sorted(bo - so):
            diffs.append("%s only in built: %s" % (key, n))
    return diffs


def main(argv):
    if len(argv) != 2:
        print("usage: compare_ko.py STOCK.ko BUILT.ko", file=sys.stderr)
        return 2
    mods = []
    for path in argv:
        try:
            with open(path, "rb") as f:
                mods.append(read_module(f.read()))
        except (OSError, ModuleError) as e:
            print("%s: %s" % (path, e), file=sys.stderr)
            return 2
    diffs = compare(*mods)
    for d in diffs:
        print(d)
    if not diffs:
        print("modules match")
    return 1 if diffs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

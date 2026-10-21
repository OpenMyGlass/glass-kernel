# SPDX-License-Identifier: GPL-2.0-only
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import compare_ko  # noqa: E402

VM_STOCK = "vermagic=3.4.94-01990-g1cee760235d SMP preempt mod_unload modversions ARMv7 p2v8\0"
VM_BUILT = "vermagic=3.4.94-openmyglass SMP preempt mod_unload modversions ARMv7 p2v8\0"


def make_elf32(sections, symbols):
    """sections: name -> bytes. symbols: list of (name, shndx)."""
    strtab = b"\0"
    symtab = b"\0" * 16
    for name, shndx in symbols:
        off = len(strtab)
        strtab += name.encode() + b"\0"
        info = (1 << 4) | 0
        symtab += struct.pack("<IIIBBH", off, 0, 0, info, 0, shndx)
    allsec = [("", b"", 0)]
    for n, d in sections.items():
        allsec.append((n, d, 1))
    allsec.append((".symtab", symtab, 2))
    allsec.append((".strtab", strtab, 3))
    allsec.append((".shstrtab", b"", 3))
    names = b"\0"
    name_off = {}
    for n, _, _ in allsec:
        if n:
            name_off[n] = len(names)
            names += n.encode() + b"\0"
    allsec[-1] = (".shstrtab", names, 3)
    strtab_idx = len(allsec) - 2
    body = b""
    offs = []
    pos = 52
    for n, d, t in allsec:
        offs.append(pos + len(body))
        body += d
    shoff = pos + len(body)
    shdrs = b""
    for i, (n, d, t) in enumerate(allsec):
        if i == 0:
            shdrs += b"\0" * 40
            continue
        link = strtab_idx if t == 2 else 0
        entsize = 16 if t == 2 else 0
        shdrs += struct.pack("<IIIIIIIIII", name_off[n], t, 0, 0, offs[i],
                             len(d), link, 0, 1, entsize)
    ident = b"\x7fELF" + bytes([1, 1, 1]) + b"\0" * 9
    hdr = ident + struct.pack("<HHIIIIIHHHHHH", 1, 40, 1, 0, 0, shoff, 0,
                              52, 0, 0, 40, len(allsec), len(allsec) - 1)
    return hdr + body + shdrs


def mod(vermagic=VM_STOCK, versions=(), undefined=(), ddk=None):
    ver = b"".join(struct.pack("<I60s", c, n.encode()) for n, c in versions)
    secs = {".modinfo": vermagic.encode(), "__versions": ver}
    if ddk:
        secs[".rodata"] = ddk.encode() + b"\0"
    return compare_ko.read_module(make_elf32(secs, [(u, 0) for u in undefined]))


class CompareKoTest(unittest.TestCase):
    def test_reads_modinfo_versions_symbols(self):
        data = make_elf32(
            {".modinfo": b"vermagic=3.4.94-x SMP preempt\0parm=foo:bar\0",
             "__versions": struct.pack("<I60s", 0x1234, b"printk")},
            [("printk", 0), ("kmalloc", 0), ("local", 1)])
        self.assertEqual(compare_ko.read_module(data), {
            "modinfo": {"vermagic": ["3.4.94-x SMP preempt"], "parm": ["foo:bar"]},
            "versions": {"printk": 0x1234},
            "undefined": ["kmalloc", "printk"],
            "ddk": None})

    def test_ddk_string(self):
        s = "SGX_DDK_Android sgxddk 19 1.9@2166536"
        data = make_elf32({".rodata": b"xx" + s.encode() + b"\0"}, [])
        self.assertEqual(compare_ko.read_module(data)["ddk"], s)

    def test_match_ignores_localversion(self):
        self.assertEqual(compare_ko.compare(mod(VM_STOCK), mod(VM_BUILT)), [])

    def test_vermagic_differs(self):
        a = mod("vermagic=3.4.94-a SMP preempt mod_unload\0")
        b = mod("vermagic=3.4.94-b SMP mod_unload\0")
        d = compare_ko.compare(a, b)
        self.assertEqual(len(d), 1)
        self.assertIn("vermagic", d[0])

    def test_symbol_and_crc_differences(self):
        a = mod(versions=[("shared_sym", 1)], undefined=["only_stock", "shared_sym"])
        b = mod(versions=[("shared_sym", 2)], undefined=["shared_sym"])
        d = compare_ko.compare(a, b)
        self.assertEqual(len(d), 2)
        self.assertTrue(any("only_stock" in x for x in d))
        self.assertTrue(any("shared_sym" in x for x in d))

    def test_rejects_non_elf32(self):
        elf64 = b"\x7fELF" + bytes([2, 1, 1]) + b"\0" * 60
        for bad in (b"not an elf", elf64):
            with self.assertRaises(compare_ko.ModuleError):
                compare_ko.read_module(bad)
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "bad.ko")
            with open(p, "wb") as f:
                f.write(b"not an elf")
            self.assertEqual(compare_ko.main([p, p]), 2)
            q = os.path.join(d, "bad64.ko")
            with open(q, "wb") as f:
                f.write(elf64)
            self.assertEqual(compare_ko.main([q, q]), 2)


if __name__ == "__main__":
    unittest.main()

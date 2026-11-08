#!/usr/bin/env python3
# crew: Android 17 libui skips the HIDL gralloc mappers when
# android_get_device_api_level() > 35. A legacy (Android 12) vendor only has
# HIDL gralloc, so SurfaceFlinger can never map a buffer and the boot stops
# at the Samsung logo. Turn every "bl android_get_device_api_level;
# cmp w0,#35; b.gt" gate into "...; nop" (KotlinRom S9 One UI 9 fix).
# Pure-Python ELF64/AArch64, no dependencies.
# usage: crew_libui_gate.py [--check] <lib64/libui.so>
#   exit 0 = patched / already patched, 3 = no gate found (left untouched), 1 = error
import struct, sys

SYM = b"android_get_device_api_level"
CMP_W0_35 = 0x71008C1F
NOP = 0xD503201F

def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def main(argv):
    check = "--check" in argv
    path = [a for a in argv if a != "--check"][0]
    data = bytearray(open(path, "rb").read())
    if data[:4] != b"\x7fELF" or data[4] != 2 or struct.unpack_from("<H", data, 18)[0] != 183:
        print(f"  ! {path}: not an ELF64 AArch64 file"); return 1
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    secs = []
    for i in range(shnum):
        name, typ, flags, addr, off, size, link, info, align, entsize = \
            struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize)
        secs.append(dict(name=name, type=typ, addr=addr, off=off, size=size, link=link, entsize=entsize))
    strtab = secs[shstrndx]
    def sname(s):
        o = strtab["off"] + s["name"]; return bytes(data[o:data.index(0, o)])
    by = {sname(s): s for s in secs}
    dynsym, dynstr = by.get(b".dynsym"), by.get(b".dynstr")
    rela = by.get(b".rela.plt"); plt = by.get(b".plt"); text = by.get(b".text")
    if not all((dynsym, dynstr, rela, plt, text)):
        print("  ! missing .dynsym/.rela.plt/.plt/.text"); return 1
    symidx = None
    for i in range(dynsym["size"] // 24):
        st_name, = struct.unpack_from("<I", data, dynsym["off"] + i * 24)
        o = dynstr["off"] + st_name
        if bytes(data[o:data.index(0, o)]) == SYM:
            symidx = i; break
    if symidx is None:
        print("  = libui does not import android_get_device_api_level (no gate)"); return 3
    got = None
    for i in range(rela["size"] // 24):
        r_off, r_info, _ = struct.unpack_from("<QQq", data, rela["off"] + i * 24)
        if r_info >> 32 == symidx:
            got = r_off; break
    if got is None:
        print("  ! no PLT relocation for the symbol"); return 1
    stub = None
    for a in range(plt["off"], plt["off"] + plt["size"] - 8, 4):
        i0, i1 = struct.unpack_from("<II", data, a)
        if (i0 & 0x9F00001F) == 0x90000010 and (i1 & 0xFFC003FF) == 0xF9400211:  # adrp x16 / ldr x17,[x16,#]
            pc = plt["addr"] + (a - plt["off"])
            imm = ((i0 >> 29) & 3) | (((i0 >> 5) & 0x7FFFF) << 2)
            page = (pc & ~0xFFF) + (sext(imm, 21) << 12)
            if page + ((i1 >> 10) & 0xFFF) * 8 == got:
                stub = pc; break
    if stub is None:
        print("  ! PLT stub for the symbol not found"); return 1
    hits = done = 0
    t0, ta = text["off"], text["addr"]
    for a in range(t0, t0 + text["size"] - 8, 4):
        bl, cmpw, br = struct.unpack_from("<III", data, a)
        if (bl & 0xFC000000) != 0x94000000 or cmpw != CMP_W0_35:
            continue
        if ta + (a - t0) + sext(bl & 0x3FFFFFF, 26) * 4 != stub:
            continue
        if br == NOP:
            done += 1
        elif (br & 0xFF000010) == 0x54000000 and (br & 0xF) == 0xC:
            hits += 1
            if not check:
                struct.pack_into("<I", data, a + 8, NOP)
    if hits == 0 and done == 0:
        print("  = no 'api_level > 35' gate in this libui (left untouched)"); return 3
    if check:
        print(f"  check: {hits} gate(s) to patch, {done} already patched"); return 0
    if hits:
        open(path, "wb").write(data)
    print(f"  + libui HIDL-mapper gate: {hits} patched, {done} already patched")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

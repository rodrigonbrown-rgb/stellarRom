#!/usr/bin/env python3
# crew: the kernel reports 5.4.x and the API is 37. A17 netd.o's stats variants are
#   *_5_4_25q2 [5.4,5.10) api [3600,3610)   *_5_4_t [5.4,5.10) api [3300,3600)
#   *_4_9_t    [4.9,4.19) api [3300,3500)   (written for kernels like this real 4.14)
# so none matches and netd aborts (prog_netd_egress_stats missing). Retarget only
# {ingress,egress}_stats_4_9_t_def to kver [5.4.0,5.5.0) api [3300,0x10000): unique match.
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
shoff, = struct.unpack_from('<Q', b, 0x28); shent, shnum, shstr = struct.unpack_from('<HHH', b, 0x3A)
S = [struct.unpack_from('<IIQQQQIIQQ', b, shoff + i * shent) for i in range(shnum)]
so = S[shstr][4]; nm = lambda o, base: bytes(b[base + o:b.index(0, base + o)]).decode()
names = [nm(s[0], so) for s in S]
if '.android_progs' not in names: print("  netd.o: no .android_progs section"); sys.exit(3)
pi = names.index('.android_progs'); po = S[pi][4]
symtab = [s for s in S if s[1] == 2][0]; strtab = S[symtab[6]]
want = {'ingress_stats_4_9_t_def', 'egress_stats_4_9_t_def'}; done = 0
for i in range(symtab[5] // 24):
    st_name, info, other, shndx, val, size = struct.unpack_from('<IBBHQQ', b, symtab[4] + i * 24)
    n = nm(st_name, strtab[4])
    if shndx != pi or n not in want: continue
    o = po + val; w = list(struct.unpack_from('<9I', b, o))
    kv_ok = (w[4], w[5]) in ((0x04090000, 0x04130000), (0x05040000, 0x05050000))
    api_ok = w[7] == 0x0ce4 and w[8] in (0x0dac, 0x10000)
    if not (kv_ok and api_ok):
        print(f"  netd.o: {n} unexpected fields {[hex(x) for x in w]}: refusing"); sys.exit(3)
    w[4], w[5], w[8] = 0x05040000, 0x05050000, 0x10000
    struct.pack_into('<9I', b, o, *w); done += 1
    print(f"  netd.o: {n} -> kver [5.4.0,5.5.0) api [3300,65536)")
if done != 2: print(f"  netd.o: found {done}/2 stats_4_9_t defs: refusing"); sys.exit(3)
open(p, 'wb').write(b)

#!/usr/bin/env python3
# crew: keep Android 17 init off the hardware watchdog (KotlinRom S9 fix):
# "/dev/watchdog" -> "/dev/watchdoz" in /system/bin/init, so init's watchdog
# open fails harmlessly instead of arming a reset during a slow first boot.
# usage: crew_init_wdt.py <init>   exit 0 = patched/already, 3 = string not found
import sys
p = sys.argv[1]; d = open(p, "rb").read()
old, new = b"\x00/dev/watchdog\x00", b"\x00/dev/watchdoz\x00"
if d.count(new) and not d.count(old):
    print("  = init watchdog already disabled"); sys.exit(0)
n = d.count(old)
if n != 1:
    print(f"  = init: '/dev/watchdog' found {n} time(s), left untouched"); sys.exit(3)
open(p, "wb").write(d.replace(old, new))
print("  + init: /dev/watchdog -> /dev/watchdoz")

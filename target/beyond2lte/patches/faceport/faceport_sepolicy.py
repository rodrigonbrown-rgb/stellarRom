#!/usr/bin/env python3
# crew: SELinux for faced (permissive domain) + BioFaceService "samsung.face"; secilc A/B check when available
import sys, os, re, glob, shutil, subprocess, tempfile
W, rules = sys.argv[1], sys.argv[2]
def die(m): print('faceport_sepolicy: ERROR ' + m); sys.exit(1)
def first(*c):
    for p in c:
        if os.path.exists(p): return p
    return None
SEP = os.path.join(W, 'system/system/etc/selinux')
plat = os.path.join(SEP, 'plat_sepolicy.cil')
if not os.path.isfile(plat): die('missing ' + plat)
if ';; crew face' in open(plat).read(): print('faceport_sepolicy: already applied'); sys.exit(0)
SEXT = first(os.path.join(W, 'system/system/system_ext/etc/selinux'), os.path.join(W, 'system_ext/etc/selinux'))
PROD = first(os.path.join(W, 'product/etc/selinux'), os.path.join(W, 'system/system/product/etc/selinux'))
VEN = first(os.path.join(W, 'vendor/etc/selinux'))
ODM = first(os.path.join(W, 'odm/etc/selinux'), os.path.join(W, 'vendor/odm/etc/selinux'))
ver = None
if VEN and os.path.exists(os.path.join(VEN, 'plat_sepolicy_vers.txt')): ver = open(os.path.join(VEN, 'plat_sepolicy_vers.txt')).read().strip()
def opt(d, n): return os.path.join(d, n) if d and os.path.isfile(os.path.join(d, n)) else None
def args_for(p):
    if not ver: return None
    a = [p, '-m', '-M', 'true', '-G', '-N', '-c', '30', opt(SEP, 'mapping/%s.cil' % ver)]
    if a[-1] is None: return None
    a += [x for x in (opt(SEP, 'mapping/%s.compat.cil' % ver), opt(SEXT, 'system_ext_sepolicy.cil'), opt(SEXT, 'mapping/%s.cil' % ver),
                      opt(PROD, 'product_sepolicy.cil'), opt(PROD, 'mapping/%s.cil' % ver), opt(VEN, 'plat_pub_versioned.cil'),
                      opt(VEN, 'vendor_sepolicy.cil'), opt(ODM, 'odm_sepolicy.cil')) if x]
    return a
def compile_ok(p):
    sc = shutil.which('secilc'); a = args_for(p)
    if not sc or not a: return None
    r = subprocess.run([sc] + a + ['-o', os.devnull, '-f', os.devnull], capture_output=True, text=True)
    return (r.returncode == 0, (r.stdout + r.stderr).strip()[-1500:])
allcil = ''.join(open(f, errors='ignore').read() for d in (SEP, SEXT, PROD, VEN, ODM) if d for f in glob.glob(os.path.join(d, '*.cil')))
def has(rx): return re.search(rx, allcil) is not None
def declared(t): return has(r'\(type %s\)' % re.escape(t))
# existing service/file contexts win (servicemanager reads plat first) -> grant on whatever type they map to
def ctx_files(fn): return [os.path.join(SEP, fn)] + ([os.path.join(SEXT, fn.replace('plat_', 'system_ext_'))] if SEXT else [])
def lookup(fn, key):
    for f in ctx_files(fn):
        if not os.path.exists(f): continue
        m = re.search(r'(?m)^' + re.escape(key) + r'\s+u:object_r:([A-Za-z0-9_]+):s0', open(f).read())
        if m: return m.group(1)
    return None
SF = lookup('plat_service_contexts', 'samsung.face'); SF_new = SF is None; SF = SF or 'crew_samsungface_service'
FD = lookup('plat_service_contexts', 'com.samsung.android.bio.face.IFaceDaemon'); FD_new = FD is None; FD = FD or 'faced_service'
FE = lookup('plat_file_contexts', '/system/bin/faced'); FE_new = FE is None; FE = FE or 'faced_exec'
add = [';; crew face']
if not declared('faced'):
    add += ['(type faced)', '(roletype object_r faced)', '(typeattributeset domain (faced))', '(typeattributeset coredomain (faced))']
for t, attrs in ((FE, ('exec_type', 'file_type', 'system_file_type')), ('faced_exec', ('exec_type', 'file_type', 'system_file_type')),
                 (FD, ('service_manager_type',)), ('faced_service', ('service_manager_type',))):
    if not declared(t) and '(type %s)' % t not in add:
        add += ['(type %s)' % t, '(roletype object_r %s)' % t] + ['(typeattributeset %s (%s))' % (a, t) for a in attrs]
if not has(r'\(typetransition init %s process faced\)' % re.escape(FE)):
    add += ['(typetransition init %s process faced)' % FE]
add += [l.rstrip() for l in open(rules) if l.strip() and not l.startswith(';')]
if SF != 'crew_samsungface_service' and not declared(SF):
    add += ['(type %s)' % SF, '(roletype object_r %s)' % SF, '(typeattributeset service_manager_type (%s))' % SF]
for r in ('(allow system_app %s (service_manager (add find)))' % SF, '(allow appdomain %s (service_manager (find)))' % SF,
          '(allow faced %s (service_manager (add find)))' % FD, '(allow system_app %s (service_manager (find)))' % FD,
          '(allow init %s (file (read getattr map execute open)))' % FE, '(allow faced %s (file (read getattr map execute open entrypoint)))' % FE):
    if r not in add: add.append(r)
base = compile_ok(plat)
tmp = tempfile.NamedTemporaryFile('w', suffix='.cil', delete=False)
tmp.write(open(plat).read() + '\n' + '\n'.join(add) + '\n'); tmp.close()
if base is None:
    print('faceport_sepolicy: WARNING secilc check skipped (%s)' % ('secilc not installed' if not shutil.which('secilc') else 'vendor/mapping cil not found'))
elif not base[0]:
    print('faceport_sepolicy: WARNING host secilc cannot build the stock policy either, check skipped:\n' + base[1][-400:])
else:
    new = compile_ok(tmp.name)
    if not new[0]: os.unlink(tmp.name); die('patched policy does not compile, nothing written:\n' + new[1])
    print('faceport_sepolicy: secilc check OK (stock + patched policy compile, vendor %s)' % ver)
shutil.copyfile(tmp.name, plat); os.unlink(tmp.name)
def append(fn, line):
    p = os.path.join(SEP, fn); s = open(p).read() if os.path.exists(p) else ''
    open(p, 'a').write(('' if not s or s.endswith('\n') else '\n') + line + '\n')
if SF_new: append('plat_service_contexts', 'samsung.face u:object_r:%s:s0' % SF)
if FD_new: append('plat_service_contexts', 'com.samsung.android.bio.face.IFaceDaemon u:object_r:%s:s0' % FD)
if FE_new: append('plat_file_contexts', '/system/bin/faced u:object_r:%s:s0' % FE)
st = lambda n, t: '%s (%s)' % (t, 'added' if n else 'ROM')
print('faceport_sepolicy: %d cil lines | samsung.face -> %s | IFaceDaemon -> %s | faced -> %s' % (len(add) - 1, st(SF_new, SF), st(FD_new, FD), st(FE_new, FE)))

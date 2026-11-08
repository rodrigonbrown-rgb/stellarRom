#!/usr/bin/env python3
# crew: One UI 9 framework.jar face port (legacy SemBioFaceManager + FaceManager facade)
# payload is merged into an existing smali tree (scripts/apktool.sh requires the original dex count)
import sys, os, re, glob, shutil, struct, zipfile
fw, add = sys.argv[1], sys.argv[2]
orig = sys.argv[3] if len(sys.argv) > 3 else None
def die(m): print('faceport_fw: ERROR ' + m); sys.exit(1)
def trees(): return sorted(d for d in glob.glob(os.path.join(fw, 'smali*')) if os.path.isdir(d) and re.fullmatch(r'smali(_classes\d+)?', os.path.basename(d)))
def rel_files(d): return {os.path.relpath(os.path.join(r, f), d) for r, _, fs in os.walk(d) for f in fs}
def dex_counts():
    res = {}
    try:
        with zipfile.ZipFile(orig) as z:
            for n in z.namelist():
                m = re.fullmatch(r'classes(\d*)\.dex', n)
                if not m: continue
                h = z.open(n).read(0x70); u = lambda o: struct.unpack_from('<I', h, o)[0]
                res['smali' if m.group(1) in ('', '1') else 'smali_classes' + m.group(1)] = (u(0x58), u(0x50), u(0x40))
    except Exception as e:
        print('faceport_fw: WARNING cannot read dex headers from %s (%s), picking smallest tree' % (orig, e))
    return res
def pick(exclude):
    cnt = dex_counts(); best = None
    for d in trees():
        if d == exclude: continue
        n = os.path.basename(d)
        if n in cnt:
            m, f, t = cnt[n]
            if m + 3000 > 65535 or f + 2500 > 65535 or t + 2500 > 65535: continue
            key = m
        elif cnt: continue
        else: key = sum(1 for _ in glob.iglob(os.path.join(d, '**/*.smali'), recursive=True))
        if best is None or key < best[0]: best = (key, d)
    if not best: die('no smali tree with enough method/field headroom for the face payload')
    print('faceport_fw: payload -> %s (%s refs before)' % (os.path.basename(best[1]), best[0]))
    if cnt and len(cnt) != len(trees()) - (1 if exclude else 0): print('faceport_fw: WARNING %d smali trees vs %d dex in original jar' % (len(trees()), len(cnt)))
    return best[1]
def merge(src_files, src_root, dst):
    clash = [r for r in src_files if os.path.exists(os.path.join(dst, r))]
    if clash: die('payload clashes with %s: %s' % (os.path.basename(dst), clash[:3]))
    for r in sorted(src_files):
        os.makedirs(os.path.dirname(os.path.join(dst, r)), exist_ok=True)
        shutil.copy2(os.path.join(src_root, r), os.path.join(dst, r))
def compat_stubs():
    # crew: members the S10 BioFaceService calls that One UI 9 dropped (S10 framework had them)
    def cf(rel):
        g = glob.glob(os.path.join(fw, 'smali*', rel))
        if len(g) != 1: die('%s found %d times' % (rel, len(g)))
        return g[0]
    added = []
    for rel, sig, body in (
        # brightnessByNits for low-light face boost; 0 -> BioFaceService falls back to its default (100)
        ('android/hardware/display/DisplayManager.smali', 'convertToBacklight(F)I', '    .locals 1\n\n    const/4 v0, 0x0\n\n    return v0'),
        # isFlipFolderClosed() treats 1 as closed; -1 = no lid
        ('android/hardware/input/InputManager.smali', 'getLidState()I', '    .locals 1\n\n    const/4 v0, -0x1\n\n    return v0'),
        # auto-brightness limit while scanning: no-op
        ('android/os/PowerManager.smali', 'semSetAutoBrightnessLimit(II)V', '    .locals 0\n\n    return-void')):
        p = cf(rel); t = open(p).read()
        if re.search(r'(?m)^\.method [^\n]* ' + re.escape(sig) + r'\n', t): continue
        t = t.rstrip('\n') + '\n\n.method public whitelist %s\n%s\n.end method\n' % (sig, body)
        open(p, 'w').write(t); added.append(sig)
    # Build.VERSION.FIRST_SDK_INT = ro.product.first_api_level (S10 behaviour, gates TA updates)
    p = cf('android/os/Build$VERSION.smali'); t = open(p).read()
    if not re.search(r'(?m)^\.field [^\n]* FIRST_SDK_INT:I', t):
        sm = re.search(r'(?m)^([ \t]*)sput ([vp]\d+), Landroid/os/Build\$VERSION;->SEM_FIRST_SDK_INT:I\n', t)
        if sm:
            # One UI 9 renamed it SEM_FIRST_SDK_INT: mirror the same register right after it is stored
            t = t[:sm.end()] + '\n%ssput %s, Landroid/os/Build$VERSION;->FIRST_SDK_INT:I\n' % (sm.group(1), sm.group(2)) + t[sm.end():]
        else:
            m = re.search(r'(?m)^\.method [^\n]*<clinit>\(\)V\n(\s*)\.locals (\d+)\n', t)
            if not m: die('Build$VERSION <clinit> not found')
            init = ('\n    const-string v0, "ro.product.first_api_level"\n\n    const/4 v1, 0x0\n\n'
                    '    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getInt(Ljava/lang/String;I)I\n\n'
                    '    move-result v0\n\n    sput v0, Landroid/os/Build$VERSION;->FIRST_SDK_INT:I\n')
            t = t[:m.start(2) - len('.locals ')] + '.locals %d\n' % max(int(m.group(2)), 2) + init + t[m.end():]
        fm1 = re.search(r'(?m)^\.method ', t)
        t = t[:fm1.start()] + '.field public static final whitelist FIRST_SDK_INT:I\n\n' + t[fm1.start():]
        open(p, 'w').write(t); added.append('FIRST_SDK_INT')
    print('faceport_fw: S10 compat members %s' % (', '.join(added) if added else 'already present'))
def sync_facade(tree):
    # crew: facade files are ours entirely -> refresh them in an already-patched (persistent) apktool tree
    n = 0
    for r in sorted(payload):
        if not r.startswith('android/hardware/face/CrewFaceFacade'): continue
        src, dst = os.path.join(add, r), os.path.join(tree, r)
        if not os.path.exists(dst) or open(src, 'rb').read() != open(dst, 'rb').read():
            os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst); n += 1
    print('faceport_fw: facade files refreshed: %d' % n)
def daemon_proxy():
    # crew: FACE_REQUEST_GET_CAMERA_INFO (10001) == 1 makes BioFaceService let faced own the camera
    # BufferQueue (GraphicBufferSource), whose S10 libgui vtable calls crash One UI 9's libgui.
    # Report 0 instead: BioFaceService then reads frames itself (ImageReader -> processFrontImage).
    g = glob.glob(os.path.join(fw, 'smali*/com/samsung/android/bio/face/IFaceDaemon$Stub$Proxy.smali'))
    if len(g) != 1: die('IFaceDaemon$Stub$Proxy.smali found %d times' % len(g))
    t = open(g[0]).read()
    if 'crewRequest(' in t: print('faceport_fw: IFaceDaemon camera-info override already present'); return
    t, n = re.subn(r'(?m)^(\.method [^\n]*?) request\(I\[B\[BI\)I$', r'\1 crewRequest(I[B[BI)I', t)
    if n != 1: die('IFaceDaemon$Stub$Proxy.request found %d times' % n)
    t = t.rstrip('\n') + '\n\n.method public request(I[B[BI)I\n    .locals 2\n\n' \
        '    invoke-virtual/range {p0 .. p4}, Lcom/samsung/android/bio/face/IFaceDaemon$Stub$Proxy;->crewRequest(I[B[BI)I\n\n' \
        '    move-result v0\n\n    const/16 v1, 0x2711\n\n    if-ne p1, v1, :cond_crew\n\n    const/4 v1, 0x1\n\n' \
        '    if-ne v0, v1, :cond_crew\n\n    const/4 v0, 0x0\n\n    :cond_crew\n    return v0\n.end method\n'
    open(g[0], 'w').write(t); print('faceport_fw: IFaceDaemon GET_CAMERA_INFO -> app-managed camera surfaces')
if not trees(): die('no smali dirs in ' + fw)
for need in ('com/samsung/android/bio/face/SemBioFaceManager.smali', 'com/samsung/android/bio/face/IFaceDaemon.smali', 'android/hardware/face/CrewFaceFacade.smali'):
    if not os.path.isfile(os.path.join(add, need)): die('module payload missing ' + need)
payload = rel_files(add)
done_f = glob.glob(os.path.join(fw, 'smali*/android/hardware/face/CrewFaceFacade.smali'))
if done_f:
    d = done_f[0][:-len('/android/hardware/face/CrewFaceFacade.smali')]
    if rel_files(d) == payload:
        # leftover extra tree from an older faceport run: fold it into a real tree
        t = pick(d); merge(payload, d, t); shutil.rmtree(d)
        print('faceport_fw: moved earlier payload tree %s into %s' % (os.path.basename(d), os.path.basename(t)))
        sync_facade(t)
    else:
        print('faceport_fw: already applied')
        sync_facade(d)
    compat_stubs()
    daemon_proxy()
    sys.exit(0)
# 1) drop One UI 9's stripped bio/face package
removed = 0
for d in trees():
    p = os.path.join(d, 'com/samsung/android/bio/face')
    if os.path.isdir(p): removed += len(os.listdir(p)); shutil.rmtree(p)
# 2) legacy package + facade into the tree with the most headroom
new = pick(None)
merge(payload, add, new)
# 3) legacy manager must never take the AOSP FaceManager compat path
cp = os.path.join(new, 'com/samsung/android/bio/face/SemBioFaceManager$FaceManagerCompat.smali')
s = open(cp).read()
a = 'invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->hasSystemFeature(Ljava/lang/String;)Z\n\n    move-result v1\n'
if s.count(a) != 1: die('FaceManagerCompat anchor count %d' % s.count(a))
open(cp, 'w').write(s.replace(a, a + '\n    const/4 v1, 0x0\n'))
# 4) FaceManager facade preludes
fm = glob.glob(os.path.join(fw, 'smali*/android/hardware/face/FaceManager.smali'))
if len(fm) != 1: die('FaceManager.smali not found')
fm = fm[0]; s = open(fm).read()
FAC = 'Landroid/hardware/face/CrewFaceFacade;->'
M = [
 ('isHardwareDetected()Z', 'TRUE', None),
 ('hasEnrolledTemplates()Z', 'hasEnrolled', None),
 ('hasEnrolledTemplates(I)Z', 'hasEnrolled', None),
 ('getEnrolledFaces()Ljava/util/List;', 'getEnrolled', None),
 ('getEnrolledFaces(I)Ljava/util/List;', 'getEnrolled', None),
 ('remove(Landroid/hardware/face/Face;ILandroid/hardware/face/FaceManager$RemovalCallback;)V', 'remove', None),
 ('removeAll(ILandroid/hardware/face/FaceManager$RemovalCallback;)V', 'removeAll', None),
 ('generateChallenge(ILandroid/hardware/face/FaceManager$GenerateChallengeCallback;)V', 'genChallenge', None),
 ('generateChallenge(IILandroid/hardware/face/FaceManager$GenerateChallengeCallback;)V', 'genChallenge', None),
 ('revokeChallenge(IIJ)V', 'revoke', None),
 ('enroll(I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;[I)V', 'enroll5', None),
 ('enroll(I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;[ILandroid/view/Surface;ZLandroid/hardware/face/FaceEnrollOptions;)V', 'enroll8', None),
 ('semPauseEnroll()V', 'pause', None),
 ('semResumeEnroll()V', 'resume', None),
 ('semSessionOpen(I)V', 'sessionOpen', None),
 ('semSessionClose(I)V', 'sessionClose', None),
 ('semResetAuthenticationTimeout()Z', 'resetTimeout', None),
 ('semIsEnrollSession()Z', 'isEnrollSession', None),
 ('semGetRemainingLockoutTime(I)I', 'remainingLockout', None),
 ('semShouldRemoveTemplate()Z', 'FALSE', None),
]
def nregs(params):
    n = 0; i = 0
    while i < len(params):
        c = params[i]
        if c in 'JD': n += 2; i += 1
        elif c in 'ZBSCIF': n += 1; i += 1
        elif c == 'L': n += 1; i = params.index(';', i) + 1
        elif c == '[':
            while params[i] == '[': i += 1
            if params[i] == 'L': i = params.index(';', i) + 1
            else: i += 1
            n += 1
        else: die('bad sig ' + params)
    return n
done = 0
for sig, name, _ in M:
    m = re.search(r'(?m)^\.method [^\n]* ' + re.escape(sig) + r'\n', s)
    if not m: die('FaceManager method missing: ' + sig)
    start = m.end()
    end = s.index('.end method', start)
    body = s[start:end]
    lm = re.match(r'(\s*)\.locals (\d+)\n', body)
    if not lm: die('no .locals in ' + sig)
    loc = int(lm.group(2)); pos = lm.end()
    rest = body[pos:]
    # keep leading .param/.annotation blocks before our code
    while True:
        r = re.match(r'(\s*\.(param|annotation)[^\n]*\n(?:(?!\s*\.end (?:param|annotation))[^\n]*\n)*\s*\.end (?:param|annotation)\n|\s*\.param[^\n]*\n)', rest)
        if not r: break
        pos += r.end(); rest = body[pos:]
    params, ret = re.match(r'[^(]*\((.*)\)(.*)', sig).groups()
    ON = '\n    invoke-static/range {p0 .. p0}, ' + FAC + 'on(Landroid/hardware/face/FaceManager;)Z\n\n    move-result v0\n\n    if-eqz v0, :crew_face_orig\n\n'
    if name in ('TRUE', 'FALSE'):
        code = ON + '    const/4 v0, 0x%d\n\n    return v0\n' % (1 if name == 'TRUE' else 0)
    else:
        last = nregs(params)
        desc = FAC + name + '(Landroid/hardware/face/FaceManager;' + params + ')' + ret
        code = ON + '    invoke-static/range {p0 .. p%d}, %s\n\n' % (last, desc)
        if ret == 'V': code += '    return-void\n'
        elif ret[0] in 'L[': code += '    move-result-object v0\n\n    return-object v0\n'
        else: code += '    move-result v0\n\n    return v0\n'
    code += '\n    :crew_face_orig\n'
    newloc = max(loc, 1)
    body = body[:lm.start()] + lm.group(1) + '.locals %d\n' % newloc + body[lm.end():pos] + code + body[pos:]
    s = s[:start] + body + s[end:]
    done += 1
open(fm, 'w').write(s)
# 5) IBiometricService: no-op defaults the S10 BioFaceService calls
ib = glob.glob(os.path.join(fw, 'smali*/android/hardware/biometrics/IBiometricService.smali'))
if len(ib) != 1: die('IBiometricService.smali not found')
ib = ib[0]; s = open(ib).read(); extra = ''
for sig, body in (('onReadyForAuthentication(I)V', 'return-void'), ('semAddFailedAttempt(II)V', 'return-void'),
                  ('semResetFailedAttempts(II)V', 'return-void'), ('semGetFailedAttempts(I)I', 'const/4 v0, 0x0\n\n    return v0')):
    if (' ' + sig) in s: continue
    extra += '\n.method public blacklist %s\n    .locals %d\n\n    %s\n.end method\n' % (sig, 1 if 'const' in body else 0, body)
open(ib, 'w').write(s.rstrip('\n') + '\n' + extra)
print('faceport_fw: removed %d One UI 9 bio/face files, added %s, FaceManager hooks %d, IBiometricService defaults ok' % (removed, os.path.basename(new), done))
compat_stubs()
daemon_proxy()

#!/usr/bin/env python3
# crew: keep source (API 37) cgroup/task-profile descriptors only where the proven
# S711B layout mounts the same controllers; otherwise install proven cgroups.json
# and rewrite/drop task_profiles entries that reference unmounted controllers.
import json, sys
from pathlib import Path


def load(p):
    return json.loads(Path(p).read_text())


def layout(cg):
    out = {}
    for c in cg.get("Cgroups", []):
        out[c["Controller"]] = ("v1", c.get("Path"))
    v2 = cg.get("Cgroups2") or {}
    if v2:
        out["cgroup2"] = ("v2", v2.get("Path"))
        for c in v2.get("Controllers", []):
            out[c["Controller"]] = ("v2", c.get("Path"))
    return out


def main(work_etc, proven_etc):
    work_etc, proven_etc = Path(work_etc), Path(proven_etc)
    wc, pc = load(work_etc / "cgroups.json"), load(proven_etc / "cgroups.json")
    wl, pl = layout(wc), layout(pc)
    if wl == pl:
        print("    cgroups.json: source layout matches the proven layout, kept")
        return 0
    for k in sorted(set(wl) | set(pl)):
        if wl.get(k) != pl.get(k):
            print(f"    cgroups.json: {k}: source={wl.get(k)} proven={pl.get(k)}")
    wt, pt = load(work_etc / "task_profiles.json"), load(proven_etc / "task_profiles.json")
    pattrs = {a["Name"]: a for a in pt.get("Attributes", [])}

    def ok(ctrl):
        return ctrl in pl and (ctrl not in wl or wl[ctrl][0] == pl[ctrl][0])

    attrs, dropped_attrs, swapped = [], set(), 0
    for a in wt.get("Attributes", []):
        if ok(a.get("Controller")):
            attrs.append(a)
        elif a["Name"] in pattrs:
            attrs.append(pattrs[a["Name"]]); swapped += 1
        else:
            dropped_attrs.add(a["Name"])
    names = {a["Name"] for a in attrs}
    for n, a in pattrs.items():
        if n not in names:
            attrs.append(a); names.add(n)
    wt["Attributes"] = attrs

    pprof = {p["Name"]: p for p in pt.get("Profiles", [])}
    dropped_actions = 0
    for prof in wt.get("Profiles", []):
        keep = []
        for act in prof.get("Actions", []):
            prm = act.get("Params", {})
            if act.get("Name") == "SetAttribute" and prm.get("Name") not in names:
                dropped_actions += 1
                continue
            if act.get("Name") == "JoinCgroup" and not ok(prm.get("Controller")):
                rep = [x for x in pprof.get(prof["Name"], {}).get("Actions", [])
                       if x.get("Name") == "JoinCgroup"
                       and x.get("Params", {}).get("Controller") == prm.get("Controller")]
                keep += rep
                dropped_actions += 1 - len(rep)
                continue
            keep.append(act)
        prof["Actions"] = keep
    have = {p["Name"] for p in wt.get("Profiles", [])}
    added = [p for n, p in pprof.items() if n not in have]
    wt.setdefault("Profiles", []).extend(added)

    (work_etc / "cgroups.json").write_text(json.dumps(pc, indent=2) + "\n")
    (work_etc / "task_profiles.json").write_text(json.dumps(wt, indent=2) + "\n")
    print(f"    cgroups.json: proven layout installed; task_profiles: {swapped} attribute(s) "
          f"taken from proven, {len(dropped_attrs)} dropped {sorted(dropped_attrs)}, "
          f"{dropped_actions} action(s) dropped, {len(added)} proven profile(s) added")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))

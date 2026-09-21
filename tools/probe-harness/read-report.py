"""Read a WicksProbe SavedVariables file and print the report(s).

    python WickSuite/tools/probe-harness/read-report.py <WicksProbe.lua> [--out DIR] [--section NAME ...]

Executes the SavedVariables file as Lua via lupa (it is a plain Lua assignment),
writes each stored run to <out>/run-N-<stamp>.txt, and prints a digest:
client identity, feature flags, restriction enum, secret-flagged live calls,
and missing globals/namespaced calls/events, per run.
"""

import argparse
import os
import re
import sys

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed. pip install lupa")


def load(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(src)
    db = L.globals().WicksProbeDB
    if db is None:
        sys.exit("WicksProbeDB not found in file")
    return db


def lua_list(t):
    if t is None:
        return []
    return [t[i] for i in range(1, len(t) + 1)]


def section(text, name):
    out, on = [], False
    for line in text.split("\n"):
        if line.startswith("["):
            on = line.startswith("[" + name)
        if on:
            out.append(line)
    return out


def digest(run, idx):
    r = run.data
    c = r.client
    print("=" * 78)
    print(f"RUN {idx}  {run.stamp}   full={bool(r.full)}")
    print("=" * 78)
    print(f"  version {c.version}  build {c.build}  date {c.date}  interface {c.toc}")
    print(f"  WOW_PROJECT_ID {c.projectID}  -> {c.projectMatch}")
    for p in lua_list(c.projects):
        if p.name != "WOW_PROJECT_ID":
            print(f"      {p.name} = {p.value}")
    print(f"  locale {c.locale}  realm {c.realm}")

    print("\n  FEATURE FLAGS")
    for f in lua_list(r.flags):
        print(f"    {'PRESENT' if f.present else 'absent ':7} {f.name:46} {f.label}")

    print("\n  RESTRICTION ENUM")
    for e in lua_list(r.restrictionEnum):
        print(f"    {e.name} = {e.value}")

    live = lua_list(r.live)
    secret = [l for l in live if l.status == "ok" and l.secret]
    missing = [l for l in live if l.status == "missing"]
    errors = [l for l in live if l.status == "error"]
    print(f"\n  LIVE CALLS  ok={sum(1 for l in live if l.status=='ok')} secret={len(secret)} missing={len(missing)} error={len(errors)}")
    for l in live:
        if l.status == "ok":
            tag = "SECRET" if l.secret else "ok"
            print(f"    {tag:7} {l.label:44} {l.path} -> {l.n}  [{l.types}]")
            if l.preview:
                print(f"            {str(l.preview)[:140]}")
        elif l.status == "missing":
            print(f"    MISSING {l.label:44} {l.path}")
        else:
            print(f"    ERROR   {l.label:44} {l.path}: {l.detail}")

    def dump(title, lst, key="name"):
        items = lua_list(lst)
        print(f"\n  {title} ({len(items)})")
        for m in items:
            used = m.usedBy if m.usedBy else "(probe question)"
            print(f"    {getattr(m, key):46} {used}")

    dump("GLOBALS MISSING", r.globalsMissing)
    dump("NAMESPACED MISSING", r.nsMissing)
    dump("EVENTS INVALID", r.eventsMissing)

    cr = lua_list(r.constCR)
    im = lua_list(r.constItemMod)
    print(f"\n  CR_* constants ({len(cr)}): " + ", ".join(f"{k.name}={k.value}" for k in cr))
    print(f"\n  ITEM_MOD_* ({len(im)}): " + ", ".join(k.name for k in im))
    if r.namespaces is not None:
        ns = lua_list(r.namespaces)
        print(f"\n  C_* NAMESPACES: {len(ns)}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--out", default=None, help="directory to write full run reports")
    ap.add_argument("--section", action="append", default=[], help="print this report section verbatim (latest run)")
    args = ap.parse_args()

    db = load(args.path)
    runs = lua_list(db.runs)
    print(f"{len(runs)} run(s) stored in {args.path}")

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for i, run in enumerate(runs, 1):
            stamp = re.sub(r"[^0-9A-Za-z]+", "-", str(run.stamp))
            p = os.path.join(args.out, f"run-{i}-{stamp}.txt")
            open(p, "w", encoding="utf-8").write(str(run.report))
            print(f"  wrote {p} ({len(str(run.report))} chars)")

    for i, run in enumerate(runs, 1):
        digest(run, i)

    for name in args.section:
        print("-" * 78)
        print("\n".join(section(str(runs[0].report), name)))


if __name__ == "__main__":
    main()

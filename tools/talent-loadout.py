#!/usr/bin/env python
"""Decode and encode Blizzard talent loadout strings (Forever / retail).

The format Blizzard's ClassTalentImportExport writes, confirmed against a
Forever client on 2026-09-18:

    base64 (standard charset), bits packed LSB-first within each 6-bit char
      8   bits  serialization version (2)
     16   bits  spec ID
    128   bits  tree hash (16 bytes, identifies the talent tree revision)
    then per node, in tree order:
      1   bit   selected
      if selected:
        1 bit   partially ranked
        6 bits  ranks purchased      (only when partially ranked)
        1 bit   is a choice node
        2 bits  choice index         (only when a choice node)

Usage:
    python talent-loadout.py <export-string>
"""
import sys

TBL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def to_bits(s):
    bits = []
    for ch in s.strip():
        v = TBL.index(ch)
        for i in range(6):
            bits.append((v >> i) & 1)
    return bits


def decode(s):
    bits, pos = to_bits(s), 0

    def take(w):
        nonlocal pos
        v = 0
        for i in range(w):
            v |= bits[pos + i] << i
        pos += w
        return v

    out = {"version": take(8), "specID": take(16)}
    out["treeHash"] = "".join("%02x" % take(8) for _ in range(16))
    nodes = []
    while pos + 1 <= len(bits):
        if not take(1):
            nodes.append(None)
            continue
        partial = take(1)
        ranks = take(6) if partial else None
        choice = take(1)
        idx = take(2) if choice else None
        nodes.append({"index": len(nodes), "ranks": ranks, "choice": idx})
    out["nodes"] = nodes
    out["selected"] = [n for n in nodes if n]
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    d = decode(sys.argv[1])
    print("version   %d" % d["version"])
    print("spec ID   %d" % d["specID"])
    print("tree hash %s" % d["treeHash"])
    print("selected  %d of %d nodes" % (len(d["selected"]), len(d["nodes"])))
    for n in d["selected"]:
        extra = []
        if n["ranks"] is not None:
            extra.append("%d ranks" % n["ranks"])
        if n["choice"] is not None:
            extra.append("choice %d" % n["choice"])
        print("  node %-3d %s" % (n["index"], ", ".join(extra) or "1 rank"))

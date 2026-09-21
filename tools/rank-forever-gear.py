"""Rank the levelling dungeon loot for a class, using stat weights.

A weighted score rather than a simulation, on purpose. At levelling
levels the stat relationships are close to linear and there are no caps
or proc interactions worth modelling, so a weighted sum is both accurate
enough and explainable, which a simulation would not be.

    python WickSuite/tools/rank-forever-gear.py ROGUE
    python WickSuite/tools/rank-forever-gear.py PRIEST --level 30
    python WickSuite/tools/rank-forever-gear.py --list

Prints the best piece per slot, with what it is worth and where it drops.
"""
import argparse
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.normpath(os.path.join(HERE, "..", "data", "forever"))

WEAPON_SLOTS = {"One-Hand", "Two-Hand", "Main Hand", "Off Hand", "Ranged", "Thrown"}
CASTERS = {"PRIEST", "MAGE", "WARLOCK", "PALADIN_HOLY", "SHAMAN_CASTER", "DRUID_CASTER"}


def load():
    loot = json.loads(io.open(os.path.join(DATA, "dungeon-loot.json"), encoding="utf-8").read())
    weights = json.loads(io.open(os.path.join(DATA, "stat-weights.json"), encoding="utf-8").read())
    return loot, weights


def score(item, w, kind):
    """What one item is worth, in points of the class's primary stat."""
    stats = item.get("stats") or {}
    total = 0.0
    parts = []
    for stat, value in stats.items():
        if not isinstance(value, (int, float)):
            continue
        weight = w.get(stat)
        if not weight:
            continue
        contribution = value * weight
        if contribution:
            total += contribution
            parts.append("%s %g" % (stat, value))

    # A weapon's damage dwarfs its stat line, so it is converted rather
    # than ignored. Casters are the exception: the weapon is a stat stick.
    if item["slot"] in WEAPON_SLOTS and stats.get("dps"):
        rate = w["_dps"]
        total += stats["dps"] * rate
        parts.insert(0, "%.1f dps" % stats["dps"])

    return total, ", ".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("klass", nargs="?", help="class key, eg ROGUE or PRIEST")
    ap.add_argument("--level", type=int, help="only gear you could wear at this level")
    ap.add_argument("--list", action="store_true", help="show the class keys available")
    args = ap.parse_args()

    loot, weights = load()
    table = weights["weights"]

    if args.list or not args.klass:
        print("Class keys:")
        for k in sorted(table):
            note = table[k].get("_note", "")
            print("   %-16s %s" % (k, note[:70]))
        return

    key = args.klass.upper()
    if key not in table:
        sys.exit("No weights for %s. Try --list." % key)

    w = dict(table[key])
    rates = weights["weapons"]["dpsPerPrimaryPoint"]
    w["_dps"] = rates["caster"] if key in CASTERS else (
        rates["hunter"] if key == "HUNTER" else rates["melee"])

    prof = weights.get("proficiency", {}).get(key)

    def usable(item):
        """Could this class wear or wield it at all."""
        if not prof:
            return True
        cls, sub = item.get("itemClass"), item.get("itemSubclass")
        if cls == 4:
            # Wowhead marks cloaks, rings, necks and trinkets with a
            # negative subclass. They carry no armour restriction, so only
            # a positive subclass is a real cloth/leather/mail/plate check.
            if sub is None or sub <= 0:
                return True
            return sub in prof["armor"]
        if cls == 2:
            return sub in prof["weapon"]
        return True   # anything else is not gear we are ranking

    # Every candidate, with where it came from.
    best = {}
    for dungeon, d in loot["dungeons"].items():
        for bucket, label in (("drops", "drop"), ("questRewards", "quest")):
            for item in d.get(bucket, []):
                if args.level and (item.get("reqLevel") or 0) > args.level:
                    continue
                if not usable(item):
                    continue
                pts, why = score(item, w, bucket)
                if pts <= 0:
                    continue
                slot = item["slot"]
                row = (pts, item, why, dungeon, label)
                if slot not in best or pts > best[slot][0]:
                    best[slot] = row

    print("Best levelling pieces for %s%s" % (key, ", usable at %d" % args.level if args.level else ""))
    print("From %d dungeons of Forever data collected %s\n" % (
        len(loot["dungeons"]), loot.get("statsCollected") or loot.get("collected")))

    order = ["Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
             "Legs", "Feet", "Finger", "Trinket", "One-Hand", "Two-Hand", "Main Hand",
             "Off Hand", "Held in Off-hand", "Shield", "Ranged", "Thrown", "Relic"]
    for slot in order:
        if slot not in best:
            continue
        pts, item, why, dungeon, label = best[slot]
        print("  %-12s %-28s %5.1f  req %-2s  %s" % (
            slot, item["name"], pts, item["reqLevel"] or "-",
            "%s, %s%s" % (dungeon, label,
                          " from " + item["droppedBy"][0] if item.get("droppedBy") else "")))
        print("  %-12s   %s" % ("", why))

    missing = [s for s in order if s not in best]
    if missing:
        print("\nNothing scored for: %s" % ", ".join(missing))
        print("Either the data is thin there, or nothing in these dungeons suits the class.")


if __name__ == "__main__":
    main()

"""Collect the loot tables of Forever's levelling dungeons from Wowhead.

Wowhead's Forever database carries real stats and real drop sources, and a
dungeon's zone page embeds its drop list as JSON inside a Listview. That
is far kinder than scraping rendered pages: one request per dungeon, no
browser, and the fields come out typed.

    python WickSuite/tools/scrape-forever-dungeons.py
    python WickSuite/tools/scrape-forever-dungeons.py --one 1581

Writes WickSuite/data/forever/dungeon-loot.json.

Stat values are not in the listview, only on each item's own tooltip, so
this collects the roster: what drops, from whom, at what item level and
for which slot. Stats are a second pass, deliberately separate so this
one stays a single cheap request per dungeon.
"""
import argparse
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "data", "forever")
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.5      # be a good guest; this is someone else's bandwidth

# The levelling run, in the order you would actually do it. Sunken Temple
# is the cut: past it you are in Blackrock and no longer levelling through
# dungeons so much as gearing for them.
DUNGEONS = [
    (2437, "Ragefire Chasm",        "13-18"),
    (1581, "The Deadmines",         "15-21"),
    (718,  "Wailing Caverns",       "15-21"),
    (717,  "The Stockade",          "22-30"),
    (209,  "Shadowfang Keep",       "22-30"),
    (719,  "Blackfathom Deeps",     "24-32"),
    (721,  "Gnomeregan",            "29-38"),
    (491,  "Razorfen Kraul",        "29-38"),
    (796,  "Scarlet Monastery",     "34-45"),
    (722,  "Razorfen Downs",        "37-46"),
    (1337, "Uldaman",               "41-51"),
    (978,  "Zul'Farrak",            "44-54"),
    (2100, "Maraudon",              "46-55"),
    (1477, "Temple of Atal'Hakkar", "50-60"),
]

# Wowhead's slot numbering, for the slots a levelling character cares
# about. Anything not here is a bag, a reagent or similar.
SLOTS = {
    1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist",
    7: "Legs", 8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket",
    13: "One-Hand", 14: "Shield", 15: "Ranged", 16: "Back", 17: "Two-Hand",
    20: "Chest", 21: "Main Hand", 22: "Off Hand", 23: "Held in Off-hand",
    25: "Thrown", 26: "Ranged", 28: "Relic",
}
QUALITY = { 0: "poor", 1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary" }


def fetch(zone_id):
    url = "https://www.wowhead.com/forever/zone=%d" % zone_id
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def extract_json_array(text, start):
    """Read one balanced [...] beginning at start, respecting strings."""
    assert text[start] == "["
    depth, i, in_str, esc = 0, start, False, False
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c in "[{":
                depth += 1
            elif c in "]}":
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        i += 1
    raise ValueError("unterminated array")


def listview(html, want):
    """One item Listview off a zone page, by its id.

    A zone page carries several: 'drops' is what the bosses and trash
    give up, 'quest-rewards' is what you are handed for finishing
    something there. Both are gear you would plan around.
    """
    for m in re.finditer(r"template:\s*'item'", html):
        seg = html[m.start():m.start() + 600]
        if ("id: '%s'" % want) not in seg:
            continue
        d = html.index("data:", m.start())
        bracket = html.index("[", d)
        return json.loads(extract_json_array(html, bracket))
    return []


def tidy(row):
    slot = row.get("slot") or 0
    sources = []
    for sm in row.get("sourcemore") or []:
        if sm.get("n"):
            sources.append(sm["n"])
    return {
        "id": row.get("id"),
        "name": row.get("name") or row.get("displayName"),
        "ilvl": row.get("level"),
        "reqLevel": row.get("reqlevel"),
        "quality": QUALITY.get(row.get("quality"), str(row.get("quality"))),
        "slot": SLOTS.get(slot),
        "slotId": slot,
        "dps": row.get("dps") or None,
        "speed": row.get("speed") or None,
        "droppedBy": sources,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--one", type=int, help="a single zone id, for a quick check")
    args = ap.parse_args()

    targets = [d for d in DUNGEONS if d[0] == args.one] if args.one else DUNGEONS
    if not targets:
        sys.exit("No dungeon with that zone id in the list.")

    out, total, equippable = {}, 0, 0
    for i, (zone, name, levels) in enumerate(targets):
        if i:
            time.sleep(PAUSE)
        try:
            html = fetch(zone)
            drops = [tidy(r) for r in listview(html, "drops")]
            quests = [tidy(r) for r in listview(html, "quest-rewards")]
        except (urllib.error.URLError, ValueError, json.JSONDecodeError) as exc:
            print("  %-24s FAILED: %s" % (name, exc))
            continue
        # Gear only. The rest is cloth, recipes and vendor trash.
        def gear_only(items):
            g = [i for i in items
                 if i["slot"] and i["quality"] in ("uncommon", "rare", "epic", "legendary")]
            g.sort(key=lambda i: (i["slot"], -(i["ilvl"] or 0)))
            return g

        d, q = gear_only(drops), gear_only(quests)
        out[name] = { "zoneId": zone, "levels": levels, "drops": d, "questRewards": q }
        total += len(drops) + len(quests)
        equippable += len(d) + len(q)
        print("  %-24s %3d dropped, %3d from quests" % (name, len(d), len(q)))

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.normpath(os.path.join(OUT_DIR, "dungeon-loot.json"))
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        json.dumps({
            "source": "wowhead.com/forever, zone drop listviews",
            "collected": time.strftime("%Y-%m-%d"),
            "note": ("Roster only; stat values live on each item's tooltip and need a "
                 "second pass. Coverage is uneven, because Wowhead's Forever data "
                 "grows from what players actually see: the early dungeons are well "
                 "filled in and the later ones are thin. Re-run as the beta goes on."),
            "dungeons": out,
        }, indent=2, ensure_ascii=False) + "\n")
    print("\n%d entries across %d dungeons, %d of them gear" % (total, len(out), equippable))
    print("Written to %s" % path)


if __name__ == "__main__":
    main()

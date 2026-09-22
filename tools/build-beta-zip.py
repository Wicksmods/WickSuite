"""Build WicksMods-Forever-beta.zip from the clean addon trees plus a fresh readme.

The package is for other people. It carries what a player needs and nothing
else: no notes, no tools, nothing of Claude's, nothing personal, no
credentials, and none of Wick's own settings, whether as a WicksProfile bake
or as a macro store payload. Anything not on the allowlist is left out and
named; anything forbidden by name or content fails the build.
"""
import io
import os
import re
import zipfile

ADDONS = "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
OUT = "C:/Users/jspli/Projects/Wick/Wicksmods.github.io/download/WicksMods-Forever-beta.zip"
FOLDERS = [
    "WickCore", "WicksBags", "WicksComforts", "WicksGear",
    "WicksTotemsAndThings", "WicksDemonsAndThings", "WicksFormsAndThings",
    "WicksBeastsAndThings", "WicksPoisonsAndThings", "WicksConjuresAndThings",
]
SKIP_DIRS = {".git", ".github", "node_modules"}

# What a player needs and nothing else.
ALLOWED_EXT = {"lua", "toc", "xml", "svg", "png", "tga", "blp"}
ALLOWED_NAMES = {"README.md", "CHANGELOG.md", "LICENSE"}

# Must never appear in a public package, by path.
FORBIDDEN_NAME = re.compile(
    r"claude|memory|settings\.local|wicksmodsinfo|token|secret|password|"
    r"\.bak$|\.orig$|\.py$|\.json$|\.env|wtf|savedvariables|"
    r"wicksprofile|profile\.lua$|macros-cache|^!",
    re.I)

# Must never appear in a public package, by content: personal paths and
# addresses, credentials, Claude's fingerprints, and Wick's own settings
# in either of the two forms they have ever been carried in.
FORBIDDEN_TEXT = [
    r"jspli", r"s-56\.com", r"CLAUDE", r"claude", r"Co-Authored-By",
    r"X-Api-Token", r"api[_ -]?token\s*[:=]", r"CLOUDFLARE", r"C:.Users",
    r"OneDrive", r"Wicksmodsinfo", r"AppData",
    r"WicksProfileData", r"WicksProfileStamp", r"WickCfg\d\d", r"\bWC1D\d+;",
    r"WicksComfortsSaved\s*=\s*\{", r"WicksBagsDB\s*=\s*\{", r"WickCoreDB\s*=\s*\{",
]

README = """Wick's Mods for World of Warcraft: Forever - beta test build
============================================================

Thank you for testing. This is a beta package for the Forever beta
client. It is not on CurseForge yet.

INSTALL
-------
Close the game. Copy every folder in this zip into:

    World of Warcraft\\_classic_beta_\\Interface\\AddOns

Start the game and make sure they are all ticked in the AddOns list.

WickCore is required by all of the others. Do not remove it.


WHAT IS IN HERE
---------------
WickCore         Shared platform. Required. /wickcore
Wick's Bags      Bags and bank, one window. /wbags
Wick's Comforts  Square minimap, tooltip extras, auto loot, auto repair,
                 junk selling, auto quest accept and hand-in, camera
                 zoom, class-coloured health bars. All off until you
                 turn them on. /wcomfort
Wick's Gear      What to chase while levelling, scored for your class
                 against what you have on; a browser for what drops
                 where, twenty-one dungeons; and a paperdoll to try
                 pieces on and see the stat changes. /wgear

Class kits, one per class. Each has talents, a pre-pull checklist,
racials and a cooldown bar:

Wick's Totems and Things     Shaman   /wtt
Wick's Demons and Things     Warlock  /wdt
Wick's Forms and Things      Druid    /wft
Wick's Beasts and Things     Hunter   /wbt
Wick's Poisons and Things    Rogue    /wpt
Wick's Conjures and Things   Mage     /wcj


KEEPING YOUR SETTINGS
---------------------
On this beta the game writes every addon's settings at logout and
hands back nothing at load, so anything you configure is normally gone
next time. That is the client, and it affects every addon you have.

WickCore can keep your Wick settings anyway, in a handful of macros
named WickCfg01, WickCfg02 and so on. Macros live on Blizzard's
servers, so they survive a reload, a relog, a full restart and a
different PC. Nothing is written until you ask:

    /wickcore store on      keep settings in macros from now on
    /wickcore store off     remove those macros and stop
    /wickcore store         say what it is doing

It only stores what you changed from the defaults, so it is a few
macros, not dozens. Your own macros are never touched. If Blizzard
fixes the client, it notices and stays out of the way.


WHAT IS NEW SINCE THE LAST PACKAGE
----------------------------------
* Settings can be kept across restarts. See above.
* Escape closes any Wick window before it opens the game menu.
* Comforts: auto accept and hand in quests (Shift at any npc for the
  normal dialogs; a quest with a choice of rewards is never handed in
  for you), camera zoom out further, sound while the game is in the
  background, hide the proc glow on action buttons.
* Comforts: class-coloured health bars on the player, target, focus,
  boss and party frames, drawn as our own bar over Blizzard's so
  nothing of theirs is touched. Colours follow WickCore's class set:
  the game's own, or the Classic-era codes with /wickcore theme classic.
* Gear: every five-player dungeon Forever has, twenty-one with loot so
  far, up from fourteen. Ruins of Lordaeron and the Hall of Thanes have
  quest rewards only until players run them and Wowhead's data fills in.
* Gear: items your character has never seen are described from our own
  data instead of "Retrieving item information" forever, with a
  comparison against what you are wearing. Shift-click links them in
  chat. Mail and plate are only suggested once your class can wear
  them.
* Hunters: the strip's ammo count reads shots over what your quiver
  holds, 286/2k, with the count red under a fifth full, amber to three
  fifths, green above.
* Every locked Wick bar or window moves when you hold Shift and drag.
  The lock stops an accidental nudge, not you.


KNOWN ISSUES
------------
* Wick's Bags can show "blocked from an action" when right-clicking an
  item. Click Ignore. Still being worked on. /wbags bank prints what
  the client says if the bank looks wrong.

* The shaman and warlock kits have not been run on a character of
  their own class yet. Expect rough edges and please report them.


REPORTING
---------
Please include the full Lua error text if you get one, and what you
were doing. Issues: github.com/Wicksmods
"""


def allowed(name):
    if name in ALLOWED_NAMES:
        return True
    if name.startswith("."):
        return False
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    return ext in ALLOWED_EXT


def main():
    count, left_out = 0, []
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("READ ME FIRST.txt", README.replace("\n", "\r\n"))
        for folder in FOLDERS:
            root = os.path.join(ADDONS, folder)
            assert os.path.isdir(root), folder
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
                for f in filenames:
                    rel = os.path.relpath(os.path.join(dirpath, f), ADDONS).replace(os.sep, "/")
                    if not allowed(f):
                        left_out.append(rel)
                        continue
                    z.write(os.path.join(dirpath, f), rel)
                    count += 1

    size = os.path.getsize(OUT)
    print("wrote %s: %d files, %.2f MB" % (OUT, count, size / 1048576.0))
    print("left out:", ", ".join(left_out) if left_out else "nothing")

    # The audit. Fails the build rather than warning.
    problems = []
    with zipfile.ZipFile(OUT) as z:
        names = z.namelist()
        print("top level:", ", ".join(sorted({n.split("/")[0] for n in names})))
        for n in names:
            if n.endswith("/"):
                continue
            base = n.split("/")[-1]
            if base != "READ ME FIRST.txt" and (FORBIDDEN_NAME.search(n) or FORBIDDEN_NAME.search(base)):
                problems.append("name: " + n)
            text = z.read(n).decode("utf-8", "ignore")
            for pat in FORBIDDEN_TEXT:
                m = re.search(pat, text)
                if m:
                    where = text[max(0, m.start() - 40):m.end() + 40].replace("\n", " ").strip()
                    problems.append("content: %s matches %s near ...%s..." % (n, pat, where))
                    break
    if problems:
        os.remove(OUT)
        raise SystemExit("AUDIT FAILED, zip removed:\n  " + "\n  ".join(problems))
    print("audit: clean, %d files scanned by name and content" % len(names))


if __name__ == "__main__":
    main()

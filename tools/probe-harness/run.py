"""Offline load test for Wick's Probe.

Runs the addon against a stubbed WoW client via lupa, so the whole path
(load -> ADDON_LOADED -> /wickprobe -> report -> SavedVariables) is exercised
without launching the game.

    python WickSuite/tools/probe-harness/run.py [--addon <dir>] [--quiet]

Exits non-zero if the addon fails to load or the sweep raises.
"""

import argparse
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed. pip install lupa")

DEFAULT_ADDON = (
    r"C:/Program Files (x86)/World of Warcraft/_anniversary_"
    r"/Interface/AddOns/WicksProbe"
)

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--addon", default=DEFAULT_ADDON,
                    help="WicksProbe directory to load")
    ap.add_argument("--quiet", action="store_true",
                    help="only print pass/fail lines, not the full report")
    args = ap.parse_args()

    if not os.path.isdir(args.addon):
        sys.exit(f"addon directory not found: {args.addon}")

    harness = os.path.join(HERE, "harness.lua").replace("\\", "/")
    addon = args.addon.replace("\\", "/")

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    runner = lua.eval(
        "function(harness, dir, quiet)"
        "  QUIET = quiet"
        "  local f = assert(loadfile(harness))"
        "  return f(dir)"
        "end"
    )

    try:
        runner(harness, addon, args.quiet)
    except lupa.LuaError as e:
        sys.exit(f"harness failed:\n{e}")


if __name__ == "__main__":
    main()

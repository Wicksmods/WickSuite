"""Round-trip test for WickKeeper, the macro-backed saved-variable rescue.

Simulates the Forever fault: the client hands back nothing at load. Checks
that a stored snapshot comes back intact and that a working client is left
alone. Run from this directory:

    python keeper-test.py
"""
import sys
import lupa

DIR = "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/!WicksKeeper"

SCRIPT = r'''
local S = assert(loadfile("stubclient.lua"))("modern")
local MACROS = {}
function GetMacroInfo(i) local m = MACROS[i]; if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body) MACROS[#MACROS + 1] = { name = name, icon = icon, body = body }; return #MACROS end
function EditMacro(i, name, icon, body) MACROS[i] = { name = name, icon = icon, body = body }; return i end
function DeleteMacro(i) table.remove(MACROS, i) end
C_AddOns.GetNumAddOns = function() return 1 end
C_AddOns.GetAddOnInfo = function() return "PretendAddon" end
C_AddOns.GetAddOnMetadata = function(a, f) if f == "SavedVariables" then return "PretendAddonDB" end end

S.loadAddon("%s", "!WicksKeeper", { "Keeper.lua" })
local K = WickKeeper

PretendAddonDB = { profile = { theme = "hunter", size = 42, nested = { a = true } } }
K:Track("PretendAddon")
local savedOk = K:Save()

PretendAddonDB = nil
K.restored = {}
local n = K:Restore()
local back = PretendAddonDB and PretendAddonDB.profile or {}

PretendAddonDB = { profile = { theme = "fromClient" } }
K.restored = {}
K:Restore()

local smallMacros = #MACROS

-- A suite-sized load: the real question is whether nine addons' settings
-- fit in the macro budget at all, which is where the first build failed.
local function profile(i)
  return {
    enabled = true, locked = false, scale = 1.0, alpha = 0.9,
    theme = "auto", point = "CENTER", relativePoint = "CENTER",
    x = 120 + i, y = -40 - i, width = 340, height = 220,
    showHeader = true, showBrackets = true, showTooltips = true,
    categories = { "Consumable", "Trade Goods", "Quest", "Equipment", "Reagent", "Projectile" },
    columns = 12, spacing = 4, sortMode = "category", autoSort = true,
  }
end
local big = {}
for i = 1, 9 do
  local p = { profiles = {}, profileKeys = {}, global = { version = 1, firstRun = false } }
  for j = 1, 4 do
    p.profiles["Profile " .. j] = profile(i * 10 + j)
    p.profileKeys["Character " .. j .. " - Realm"] = "Profile " .. j
  end
  big["WicksPretend" .. i .. "DB"] = p
end
for name, value in pairs(big) do
  _G[name] = value
  K.tracked[name] = "PretendAddon"
end
local bigOk, bigInfo = K:Save()
local bigDropped = K.dropped

return table.concat({
  tostring(savedOk),
  tostring(n),
  tostring(back.theme),
  tostring(back.size),
  tostring(back.nested and back.nested.a),
  tostring(PretendAddonDB.profile.theme),
  tostring(smallMacros),
  tostring(#MACROS),
  tostring(bigOk),
  tostring(bigInfo),
  tostring(bigDropped),
}, "\t")
''' % DIR

vals = lupa.LuaRuntime().execute(SCRIPT).split("\t")
saved, n, theme, size, nested, untouched, macros, bigMacros, bigOk, bigInfo, bigDropped = vals

checks = [
    ("saved into macros", saved, "true"),
    ("restored one global", n, "1"),
    ("string survived", theme, "hunter"),
    ("number survived", size, "42"),
    ("nested table survived", nested, "true"),
    ("a suite-sized load saves", bigOk, "true"),
    ("and fits inside the macro budget", str(int(bigMacros) <= 90), "True"),
    ("and nothing had to be shed", bigDropped, "nil"),
    ("a working client is left alone", untouched, "fromClient"),
    ("macro slots used", macros, "1"),
]
fails = 0
for label, got, want in checks:
    ok = got == want
    fails += 0 if ok else 1
    print("  %-32s %-12s %s" % (label, got, "ok" if ok else "FAIL, wanted " + want))
print("PASS" if not fails else "%d check(s) failed" % fails)
sys.exit(1 if fails else 0)

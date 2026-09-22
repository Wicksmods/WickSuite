-- Offline load test for the three Forever class kits on WickCore.
--   args: coreDir, addonsDir, mode, stubPath
-- Loads WickCore, then each kit as the matching class, and drives the kit
-- panel, checklist, talents, racials and the kit-specific bars.

local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end
local function dumpErrors()
    for _, l in ipairs(S.CHAT) do if l:lower():find("error") then io.write("  chat: ", (l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "\n") end end
    S.CHAT = {}
end
local function try(label, fn)
    local ok, err = pcall(fn)
    check(ok, label .. (ok and "" or (": " .. tostring(err))))
    return ok
end

local CORE_FILES = { "LibStub.lua", "Core.lua", "Client.lua", "Restrict.lua", "Dialect.lua", "Locale.lua",
    "Chrome.lua", "Profiles.lua", "Store.lua", "Options.lua", "Launcher.lua", "Version.lua",
    "Talents.lua", "Checklist.lua", "Racials.lua", "Cooldowns.lua", "Kit.lua" }

io.write("== load WickCore (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore", CORE_FILES)
S.fire("ADDON_LOADED", "WickCore")
check(WickCore.Kit and WickCore.Talents and WickCore.Checklist and WickCore.Racials, "kit layer present")

-- ---------- shared kit layer -------------------------------------------
io.write("== kit layer ==\n")
local T = WickCore.Talents
check(T:IsAvailable() == MODERN, "talents availability matches client")
if MODERN then
    local str = T:Export()
    check(type(str) == "string" and #str > 0, "Talents:Export returns a string")
    local ok, why = T:Import(str, "Harness")
    check(ok == true, "Talents:Import through Blizzard parser " .. tostring(why or ""))
    local s = T:Summary()
    check(s and s.name == "Loadout A" and #s.spent == 3, "Talents:Summary reads config + tree currencies")
else
    local str, why = T:Export()
    check(str == nil and why, "Talents:Export declines on legacy")
end

local Rc = WickCore.Racials
local data, token = Rc:ForPlayer()
check(data ~= nil and token == "Orc", "racial data for player race")
check(#Rc:KnownActives() == 2, "racial actives resolve to spells")

-- ---------- Totems and Things -------------------------------------------
io.write("== Totems and Things ==\n")
CLASS = "SHAMAN"
S.loadAddon(ADDONS_DIR .. "/WicksTotemsAndThings", "WicksTotemsAndThings", { "Core.lua", "Totems.lua", "TotemBar.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksTotemsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local WT = WicksTotems
check(WT.A.initialized and WT.A.enabled, "totems initialized + enabled")
check(WicksTotemsDB == WT.A.db.profile and WicksTotemsCharDB == WT.A.db.char, "legacy globals alias the profile/char tables")
check(WicksTotemsSaved and WicksTotemsSaved.profiles, "saved variable carries the profile structure")
check(WT.A.kit ~= nil, "kit attached")
check(#WicksTotemsCharDB.presets == 2 and WicksTotemsCharDB.presets[1].totems.fire == "Searing Totem", "default presets seeded")
check(WT.TotemBar.host ~= nil and WT.TotemBar.callElements ~= nil, "totem bar built with Call of the Elements button")
local m = WT.TotemBar.btn_fire:GetAttribute("macrotext1")
check(m and m:find("/cast Searing Totem"), "element button macro: " .. tostring(m))
if MODERN then
    check(S.MULTICAST[1] == 133 or S.MULTICAST[1] ~= nil, "preset pushed into multicast slots on rebuild")
    local ok, why = WT.TotemBar:ApplyToTotemBar()
    check(ok == true, "ApplyToTotemBar " .. tostring(why))
else
    local ok, why = WT.TotemBar:ApplyToTotemBar()
    check(ok == false, "ApplyToTotemBar declines without a totem bar")
end
local active = WT:ActiveTotems()
check(active[1] and active[1].name == "Strength of Earth Totem", "ActiveTotems reads slot 1 at rest")
COMBAT = true
active = WT:ActiveTotems()
if MODERN then check(next(active) == nil and WT.totemsRestricted, "ActiveTotems empty + restricted flag in combat")
else check(active[1] ~= nil, "ActiveTotems still reads in combat on legacy") end
COMBAT = false
try("totems UI Build + Show", function() WT.UI:Build(); WT.UI:Show() end)
try("totems UI options tab", function() WT.UI:SelectTab("options") end)
try("totems UI active tab", function() WT.UI:SelectTab("active") end)
try("totems kit toggle", function() WT.A.kit:Toggle() end)
check(WT.A.kit.panel and WT.A.kit.panel:IsShown(), "kit panel shown")
try("kit checklist tab", function() WT.A.kit:Select("checklist") end)
local rows = WT.A.kit.checklist:Evaluate()
check(#rows == 5, "checklist evaluates 5 rows")
check(rows[1].state == "ok", "shield row ok at rest (Lightning Shield present): " .. tostring(rows[1].state))
check(rows[4].state == "missing" and rows[4].detail == "0", "ankh row missing with count")
check(rows[5].state == "ok", "totems ready row ok")
COMBAT = true
rows = WT.A.kit.checklist:Evaluate()
if MODERN then check(rows[1].state == "unknown", "shield row unknown in combat") end
COMBAT = false
try("kit racials tab", function() WT.A.kit:Select("racials") end)
try("kit talents tab", function() WT.A.kit:Select("talents") end)
S.CHAT = {}
SlashCmdList.WICK_WICKSTOTEMSANDTHINGS("status")
check(#S.CHAT >= 3, "/wtt status prints")
SlashCmdList.WICK_WICKSTOTEMSANDTHINGS("twist air on")
check(WicksTotemsCharDB.twist.air and WicksTotemsCharDB.twist.air.enabled, "/wtt twist air on")
check(WT.TotemBar.btn_air:GetAttribute("macrotext1"):find("/castsequence"), "twist macro rebuilt")

-- ---------- Demons and Things --------------------------------------------
io.write("== Demons and Things ==\n")
CLASS = "WARLOCK"
S.loadAddon(ADDONS_DIR .. "/WicksDemonsAndThings", "WicksDemonsAndThings", { "Core.lua", "SoulBar.lua", "PetBar.lua", "ShardCounter.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksDemonsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local WD = WicksDemons
check(WD.A.initialized and WD.A.enabled, "demons initialized + enabled")
check(WicksDemonsDB == WD.A.db.profile, "demons legacy global aliases profile")
check(WD.isWarlock, "class detection")
check(WD.Cooldowns == nil, "cooldown tracker not loaded")
check(WD.ShardCounter and WD.ShardCounter.frame, "shard counter built")
check(WD.ShardCounter:Count() == 1, "shard count from bags")
try("pet bar refresh at rest", function() if WD.PetBar.Refresh then WD.PetBar:Refresh() end end)
try("soul bar refresh at rest", function() if WD.SoulBar.Refresh then WD.SoulBar:Refresh() end end)
COMBAT = true
try("pet bar refresh in combat (secret cooldowns)", function() if WD.PetBar.Refresh then WD.PetBar:Refresh() end end)
try("soul bar refresh in combat", function() if WD.SoulBar.Refresh then WD.SoulBar:Refresh() end end)
COMBAT = false
try("demons UI build + toggle", function() WD.UI:Build(); WD.UI:Toggle() end)
try("demons kit", function() WD.A.kit:Toggle(); WD.A.kit:Select("checklist") end)
local drows = WD.A.kit.checklist:Evaluate()
check(#drows == 6, "demons checklist 6 rows")
check(drows[6].state == "ok", "demon out (pet exists)")
S.CHAT = {}
SlashCmdList.WICK_WICKSDEMONSANDTHINGS("status")
check(#S.CHAT >= 3, "/wdt status prints")

-- ---------- Forms and Things ---------------------------------------------
io.write("== Forms and Things ==\n")
CLASS = "DRUID"
S.loadAddon(ADDONS_DIR .. "/WicksFormsAndThings", "WicksFormsAndThings", { "Core.lua", "TravelForm.lua", "TravelFormUI.lua" })
S.fire("ADDON_LOADED", "WicksFormsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local F = WICKSTRAVELFORM
check(F.A.initialized and F.A.enabled, "forms initialized + enabled")
check(WicksTravelFormDB == F.A.db.profile, "forms legacy global aliases profile")
check(F.isDruid, "class detection")
local macro = F.buildMacro()
check(macro:find("%[swimming%] Aquatic Form") and macro:find("%[outdoors%] Travel Form") and macro:find("Cat Form"), "macro built: " .. macro)
check(not macro:find("Flight"), "no flight clause in a non-flyable zone")
if MODERN then check(F.bestFlightForm() == nil, "no flight form on Forever")
else check(F.bestFlightForm() == "Flight Form", "flight form found via spellbook on legacy") end
check(F.predictForm() == "Travel Form", "predicted form outdoors: " .. tostring(F.predictForm()))
-- A fresh druid knows no forms at all: the key must offer nothing rather
-- than cast spells they do not have.
do
    S.ALL_UNKNOWN = true
    check(F.buildMacro() == "", "no forms learned yet: the macro is empty")
    check(F.predictForm() == nil, "no forms learned yet: nothing predicted")
    -- The button and its tooltip have to survive having nothing to predict.
    local okIcon = pcall(function() F.UI:Refresh() end)
    check(okIcon, "button refreshes with no forms learned")
    check(_G.WicksTravelFormHost and not _G.WicksTravelFormHost:IsShown(),
        "button hides itself while no form is known")
    local btn = _G.WicksTravelFormButton
    local okTip = btn and pcall(btn.__scripts.OnEnter, btn)
    check(okTip, "button tooltip survives having nothing to predict")
    S.ALL_UNKNOWN = false
    F.UI:Refresh()   -- put the real macro back on the button
    check(_G.WicksTravelFormHost and _G.WicksTravelFormHost:IsShown(),
        "button comes back once a form is learned")
    check(F.buildMacro() ~= "", "macro returns once the forms are known again")
end
local btn = _G.WicksTravelFormButton
check(btn and btn:GetAttribute("macrotext1") == macro, "secure button carries the macro")
try("resource bar draw at rest", function() F.UpdateResourceBar() end)
COMBAT = true
try("resource bar draw in combat (secret power)", function() F.UpdateResourceBar() end)
COMBAT = false
try("forms kit", function() F.A.kit:Toggle(); F.A.kit:Select("checklist") end)
local frows = F.A.kit.checklist:Evaluate()
check(#frows == 4, "forms checklist 4 rows")
check(frows[4].state == "ok", "rebirth ready at rest: " .. tostring(frows[4].state))
S.CHAT = {}
SlashCmdList.WICK_WICKSFORMSANDTHINGS("debug")
check(#S.CHAT >= 3, "/wft debug prints")

io.write("== Beasts and Things ==\n")
CLASS = "HUNTER"
S.PET_FAMILY = "Wolf"
S.PET_SPELLS = { { "Bite", "active" }, { "Growl", "active" }, { "Furious Howl", "active" }, { "Avoidance", "passive" } }
local BNS = S.loadAddon(ADDONS_DIR .. "/WicksBeastsAndThings", "WicksBeastsAndThings", { "Core.lua", "Pet.lua", "Ammo.lua", "Beasts.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksBeastsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local bns
for _, f in ipairs(S.frames) do if f.__name == "WicksBeastsEvents" then bns = true end end
check(bns, "beasts event frame created")
local kb = _G.WicksBeastsFeedButton
check(kb ~= nil, "feed keybind button exists")
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("status")
check(#S.CHAT >= 3, "/wbt status prints")
local statusLine = table.concat(S.CHAT, " | ")
check(statusLine:find("happiness 2") ~= nil, "pet happiness read: " .. statusLine:sub(1, 120))
if MODERN then
    local mt = tostring(kb:GetAttribute("macrotext"))
    check(mt:find("/cast Feed Pet") and mt:find("/use item:6948"), "feed macro built from CanPetEatItem: " .. mt)
    check(statusLine:find("count 150") ~= nil, "ammo equipped count read")
else
    check(kb:GetAttribute("macrotext") == "", "no feed macro without CanPetEatItem on legacy")
end
local strip = _G.WicksBeastsStrip
check(strip ~= nil and strip:IsShown(), "compact strip built and shown for a hunter")
check(strip and strip.feed and strip.feed:GetAttribute("type") == "macro", "strip feed button is a secure macro button")
try("strip refresh", function() local U = strip and strip.__scripts.OnShow; if U then U(strip) end end)
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("strip")
check(strip and not strip:IsShown() and S.CHAT[1] and S.CHAT[1]:find("hidden"), "/wbt strip hides the strip")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("strip")
check(strip and strip:IsShown(), "/wbt strip shows it again")
-- The strip reads shots over what the quiver holds, 1768/2000 style, when
-- a quiver or ammo pouch is equipped; without one it is the plain count.
-- Capacity is every slot of every such bag, by the family the client
-- reports, times the stack the ammo itself reports.
S.ITEMS = S.ITEMS or {}
S.ITEMS[2512] = { name = "Rough Arrow", type = "Projectile", sub = "Arrow", classID = 6, subClassID = 2, stack = 200 }
S.BAG_FAMILY[1] = 1                       -- bag 1 is a quiver, sixteen slots in the stub
BNS.UI:RefreshAmmo()
local ammoState = BNS.Ammo:State()
check(ammoState.capacity == 3200, "a sixteen slot quiver of two hundred stacks holds 3200: " .. tostring(ammoState.capacity))
-- The count carries a colour for how full the quiver is: under a fifth
-- red, up to three fifths amber, above that the brand green. The
-- capacity is abbreviated so the number that matters gets the room.
local function hex6(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
local RED_HEX, AMBER_HEX, FEL_HEX = "cc4d4d", "d9a640", hex6(WickCore.Chrome.Colors.fel)
check(strip.ammoText.__text == ("|cff%s%d|r/3.2k"):format(RED_HEX, ammoState.total),
    "151 of 3200 is red over an abbreviated capacity: " .. tostring(strip.ammoText.__text))
local realCount = GetInventoryItemCount
GetInventoryItemCount = function(_, inv) return inv == 0 and 1300 or 1 end
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("|cff" .. AMBER_HEX .. "1301|r/3.2k", 1, true) ~= nil,
    "about forty percent is amber: " .. tostring(strip.ammoText.__text))
GetInventoryItemCount = function(_, inv) return inv == 0 and 2500 or 1 end
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("|cff" .. FEL_HEX .. "2501|r/3.2k", 1, true) ~= nil,
    "nearly full is green: " .. tostring(strip.ammoText.__text))
GetInventoryItemCount = realCount
S.ITEMS[2512].stack = 125                 -- sixteen slots of 125 is a round two thousand
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("/2k", 1, true) ~= nil, "a round capacity abbreviates without a decimal: " .. tostring(strip.ammoText.__text))
S.ITEMS[2512].stack = 200
BNS.UI:RefreshAmmo()
S.BAG_FAMILY[1] = nil
BNS.UI:RefreshAmmo()
ammoState = BNS.Ammo:State()
check(ammoState.capacity == nil, "no quiver, no capacity")
check(not tostring(strip.ammoText.__text):find("/"), "and the strip goes back to the plain count: " .. tostring(strip.ammoText.__text))
S.ITEMS[2512] = nil
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("unlock")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("lock")
try("beasts panel", function() WicksBeastsAndThings_Toggle() end)
try("beasts panel refresh", function() WicksBeastsAndThings_Toggle(); WicksBeastsAndThings_Toggle() end)
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("ammo 50")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food 6948")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food")
check(#S.CHAT >= 4, "/wbt ammo and food commands print")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food clear")
try("beasts kit", function() SlashCmdList.WICK_WICKSBEASTSANDTHINGS("kit") end)
local bkit
for _, f in ipairs(S.frames) do if f.__name == "WickWicksBeastsAndThingsKit" then bkit = f end end
check(bkit ~= nil, "beasts kit panel built")
local BENTRY = WickCore.Launcher.entries.WicksBeastsAndThings
local BADDON = BENTRY and BENTRY.addon
check(BADDON ~= nil, "beasts launcher registered")
if BADDON then
    local rows = BADDON.kit.checklist:Evaluate()
    check(#rows == 5, "beasts checklist 5 rows")
    check(rows[2].state == "ok", "pet out at rest: " .. tostring(rows[2].state))
    check(rows[3].state == "missing", "content pet reads as not fed: " .. tostring(rows[3].state))
    check(rows[4].state == "ok", "ammo stocked above the 50 warn: " .. tostring(rows[4].state))
    if MODERN then
        COMBAT = true
        local crows = BADDON.kit.checklist:Evaluate()
        check(crows[3].state == "unknown", "pet fed unknown in combat (secret happiness): " .. tostring(crows[3].state))
        COMBAT = false
    end

    -- The beast atlas. Nothing in the client joins family to abilities,
    -- so it learns by reading the pet spell book whenever a pet is out.
    local function special(family)
        local list = BNS.beasts:Known(family)
        return list and table.concat(list, ", ") or "nothing"
    end
    local fams = BADDON.db.global.families
    check(fams and fams.Wolf ~= nil, "the wolf out at login was filed")
    check(fams.Wolf.abilities["Furious Howl"] == "active", "with its active abilities")
    check(fams.Wolf.abilities["Avoidance"] == "passive", "and its passive ones marked as passive")

    S.PET_FAMILY = "Hyena"
    S.PET_SPELLS = { { "Bite", "active" }, { "Growl", "active" }, { "Tendon Rip", "active" } }
    S.fire("UNIT_PET", "player")
    check(BADDON.db.global.families.Hyena ~= nil, "a second family files on its own")
    check(special("Hyena"):find("Tendon Rip") ~= nil, "hyena keeps Tendon Rip: " .. special("Hyena"))

    -- A third family makes Bite and Growl ordinary, three being the point
    -- at which an ability stops being a reason to tame anything.
    S.PET_FAMILY = "Boar"
    S.PET_SPELLS = { { "Bite", "active" }, { "Growl", "active" }, { "Charge", "active" } }
    S.fire("UNIT_PET", "player")
    check(special("Hyena") == "Tendon Rip",
        "with three families sharing Bite and Growl, only Tendon Rip stands out: " .. special("Hyena"))
    check(special("Boar") == "Charge", "and only Charge for the boar: " .. special("Boar"))

    S.CHAT = {}
    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("beasts")
    local blist = table.concat(S.CHAT, " | ")
    check(blist:find("Hyena") ~= nil and blist:find("Tendon Rip") ~= nil and blist:find("Boar") ~= nil,
        "/wbt beasts lists them: " .. blist:sub(1, 80))

    -- The Beasts tab, contributed by the kit rather than built into the
    -- core, since WickCore has no business knowing what a hunter keeps.
    local kit = BADDON.kit
    check(kit.tabs.beasts ~= nil, "the kit grew a Beasts tab")
    check(kit.panes.beasts ~= nil, "with a pane behind it")
    kit:Select("beasts")
    check(kit.panes.beasts:IsShown(), "selecting it shows the pane")
    check(kit.panes.talents:IsShown() == false, "and puts the others away")
    local prows = BNS.beasts.pane.rows
    local shown = 0
    for _, r in ipairs(prows) do if r:IsShown() then shown = shown + 1 end end
    check(shown == 3, "a row per recorded family, got " .. shown)
    local texts = {}
    for _, r in ipairs(prows) do texts[#texts + 1] = r.family:GetText() .. "=" .. r.abilities:GetText() end
    local joined = table.concat(texts, " | ")
    check(joined:find("Hyena=Tendon Rip") ~= nil, "the pane leads with what sets a family apart: " .. joined:sub(1, 70))
    check(joined:find("%(") ~= nil, "and brackets the ones they all share")

    BNS.beasts:Forget()
    BNS.beasts:RefreshPane()
    shown = 0
    for _, r in ipairs(prows) do if r:IsShown() then shown = shown + 1 end end
    check(shown == 0, "forget all empties the pane")
    kit:Select("talents")
end

io.write("== Poisons and Things ==\n")
CLASS = "ROGUE"
S.loadAddon(ADDONS_DIR .. "/WicksPoisonsAndThings", "WicksPoisonsAndThings", { "Core.lua", "Poisons.lua", "Combo.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksPoisonsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local PENTRY = WickCore.Launcher.entries.WicksPoisonsAndThings
local PA = PENTRY and PENTRY.addon
check(PA ~= nil, "poisons launcher registered")
local mainKey, offKey = _G.WicksPoisonsMainButton, _G.WicksPoisonsOffButton
check(mainKey ~= nil and offKey ~= nil, "a coating keybind button per hand")
local pstrip = _G.WicksPoisonsStrip
check(pstrip ~= nil and pstrip:IsShown(), "poison strip built and shown for a rogue")
if MODERN then
    local mt = tostring(mainKey:GetAttribute("macrotext"))
    check(mt:find("/use item:6948") and mt:find("/use 16"), "main hand macro uses the coating then the slot: " .. mt)
    check(tostring(offKey:GetAttribute("macrotext")):find("/use 17") ~= nil, "off hand macro targets the off hand slot")
else
    check(tostring(mainKey:GetAttribute("macrotext")) ~= "", "legacy still builds a coating macro")
end
S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("status")
local pline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wpt status prints")
if MODERN then
    check(pline:find("coated true") ~= nil, "main hand reads as coated from the temporary enchantment")
    check(pline:find("minutes 30") ~= nil, "time left read: " .. pline:sub(1, 90))
end
-- Combo points over the target's nameplate. The point of the design is
-- that it never compares the value, so the same code has to survive the
-- number arriving secret. Run it both ways.
local combo = _G.WicksPoisonsComboRow
check(combo ~= nil, "combo row built for a rogue")
check(not combo:IsShown(), "and stays hidden with no target")
S.HAS_TARGET = true
S.COMBO = 3
S.fire("PLAYER_TARGET_CHANGED")
check(combo:IsShown(), "it appears once the target has a nameplate")
local plate = C_NamePlate.GetNamePlateForUnit("target")
check(combo:GetParent() == plate, "parented to the target's plate")
check(combo.anchoredToName == false, "sits under the health bar, off the name above it")
PA.db.profile.comboAbove = true
S.fire("PLAYER_TARGET_CHANGED")
check(combo.anchoredToName == true, "the option lifts it above the name, clear of the cast bar")
PA.db.profile.comboAbove = false
S.fire("PLAYER_TARGET_CHANGED")
check(combo.anchoredToName == false, "and back under the health bar")
check(combo.count == 5, "five pips")
check(combo.pips[1].__min == 0 and combo.pips[1].__max == 1, "each pip covers one point of the range")
check(combo.pips[4].__min == 3 and combo.pips[4].__max == 4, "the fourth pip covers three to four")
S.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
check(combo.pips[1]:GetValue() == 3, "the raw count goes into every pip")

-- Now with the client refusing to say. Nothing may compare, and nothing
-- may error; the pips just take the secret.
S.POWER_SECRET = true
local okSecret = pcall(function()
    S.fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
    S.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
end)
check(okSecret, "a secret combo count does not throw")
check(combo.count == 5, "and falls back to five pips when the maximum is secret too")
S.POWER_SECRET = false

PA.db.profile.comboOnPlate = false
S.fire("PLAYER_TARGET_CHANGED")
check(not combo:IsShown(), "switching it off hides the row")
PA.db.profile.comboOnPlate = true
S.fire("PLAYER_TARGET_CHANGED")
S.HAS_TARGET = false
S.fire("PLAYER_TARGET_CHANGED")
check(not combo:IsShown(), "losing the target hides it again")
S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("combo")
local creport = table.concat(S.CHAT, " | ")
check(creport:find("power secret") ~= nil and creport:find("GetComboPoints") ~= nil,
    "/wpt combo says whether the client will answer: " .. creport:sub(1, 70))

try("poison panel", function() WicksPoisonsAndThings_Toggle() end)
S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("warn 12")
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("pin main 6948")
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("pin off clear")
check(#S.CHAT >= 3, "/wpt warn and pin print")
check(PA.db.profile.warnMinutes == 12 and PA.db.profile.pinned.main == 6948, "warn and pin stored")
try("poisons kit", function() SlashCmdList.WICK_WICKSPOISONSANDTHINGS("kit") end)
if PA then
    local prows = PA.kit.checklist:Evaluate()
    check(#prows == 4, "poisons checklist 4 rows")
    check(prows[1].state == "ok", "main hand coated reads ok: " .. tostring(prows[1].state))
    check(prows[3].state == "ok", "coatings carried: " .. tostring(prows[3].state))
end

io.write("== cooldown bar in every kit ==\n")
for _, name in ipairs({ "WicksTotemsAndThings", "WicksDemonsAndThings", "WicksFormsAndThings",
                        "WicksBeastsAndThings", "WicksPoisonsAndThings" }) do
    local entry = WickCore.Launcher.entries[name]
    local addon = entry and entry.addon
    check(addon ~= nil and addon.cooldowns ~= nil, name .. " has a cooldown bar")
    if addon and addon.cooldowns then
        local bar = addon.cooldowns
        check(bar:Store().shown == false, name .. " keeps it off until asked")
        local okCmd = pcall(function() bar:Command("list") end)
        check(okCmd, name .. " cd command runs")
        -- The kit window carries the same controls, so the bar can be
        -- built without knowing the slash command.
        addon.kit:Build()
        check(addon.kit.panes.cooldowns ~= nil, name .. " kit has a Cooldowns tab")
        local okTab = pcall(function() addon.kit:Select("cooldowns") end)
        check(okTab, name .. " Cooldowns tab opens")
    end
end

-- A lock is there to stop an accidental nudge while you click the bar,
-- not to stop you moving it on purpose. Hunting for the unlock checkbox
-- every time is worse than the accident, so shift always moves it. One
-- rule, asked of WickCore, rather than each bar deciding for itself.
io.write("== a lock yields to shift ==\n")
local Chrome = WickCore.Chrome
local realShift = IsShiftKeyDown
IsShiftKeyDown = function() return false end
check(Chrome:DragAllowed(false) == true, "an unlocked frame drags")
check(Chrome:DragAllowed(true) == false, "a locked one does not")
IsShiftKeyDown = function() return true end
check(Chrome:DragAllowed(true) == true, "until you hold shift")
check(Chrome:DragAllowed(false) == true, "and shift never gets in the way of an unlocked one")

-- Not just the helper: the bar people actually lock has to move.
do
    local entry = WickCore.Launcher.entries["WicksTotemsAndThings"]
    local bar = entry and entry.addon and entry.addon.cooldowns
    -- The frame is built lazily, so ask for it rather than waiting for
    -- something else in the run to have opened the bar.
    local frame = bar and bar:Build()
    local h = frame and frame.GetScript and frame:GetScript("OnDragStart")
    check(h ~= nil, "the cooldown bar has a drag handler to test")
    if h then
        bar:SetLocked(true)
        local started = false
        frame.StartMoving = function() started = true end
        IsShiftKeyDown = function() return false end
        h(frame)
        check(not started, "a locked cooldown bar ignores a plain drag")
        IsShiftKeyDown = function() return true end
        h(frame)
        check(started, "and moves when the drag is deliberate")
        bar:SetLocked(false)
    end
end
IsShiftKeyDown = realShift

io.write("== Conjures and Things ==\n")
CLASS = "MAGE"
S.loadAddon(ADDONS_DIR .. "/WicksConjuresAndThings", "WicksConjuresAndThings", { "Core.lua", "Conjure.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksConjuresAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local MENTRY = WickCore.Launcher.entries.WicksConjuresAndThings
local MA = MENTRY and MENTRY.addon
check(MA ~= nil, "conjures launcher registered")
check(_G.WicksConjuresWaterButton ~= nil and _G.WicksConjuresFoodButton ~= nil, "a conjure keybind per ration")
local cstrip = _G.WicksConjuresStrip
check(cstrip ~= nil and cstrip:IsShown(), "conjures strip shown for a mage")
local stock = WICKCONJ and nil
S.CHAT = {}
SlashCmdList.WICK_WICKSCONJURESANDTHINGS("status")
local cline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wcj status prints")
if MODERN then
    check(cline:find("rations %d") ~= nil, "conjured rations counted from the bags: " .. cline:sub(1, 70))
    check(tostring(_G.WicksConjuresWaterButton:GetAttribute("spell")) ~= "", "the water key carries a spell")
    check(tostring(_G.WicksConjuresFoodButton:GetAttribute("spell")):find("Food") ~= nil,
        "and the food key carries the food one: " .. tostring(_G.WicksConjuresFoodButton:GetAttribute("spell")))

    -- The strip has one Rations segment standing for both halves of the
    -- job, and it used to conjure drink whichever half you were short of.
    local rations
    for _, fr in ipairs(S.frames) do
        local a = fr.__attr
        if a and a.spell2 and tostring(a.spell1):find("Water") then rations = fr end
    end
    check(rations ~= nil, "found the rations segment")
    if rations then
        check(tostring(rations:GetAttribute("spell1")):find("Water") ~= nil,
            "left-click conjures drink: " .. tostring(rations:GetAttribute("spell1")))
        check(tostring(rations:GetAttribute("spell2")):find("Food") ~= nil,
            "right-click conjures food: " .. tostring(rations:GetAttribute("spell2")))
    end
end
try("conjures panel", function() WicksConjuresAndThings_Toggle() end)
try("conjures kit", function() SlashCmdList.WICK_WICKSCONJURESANDTHINGS("kit") end)
if MA then
    local crows = MA.kit.checklist:Evaluate()
    check(#crows == 5, "conjures checklist 5 rows")
    check(MA.cooldowns ~= nil, "conjures has a cooldown bar")
end

io.write("== Comforts ==\n")

-- Straight off the toc, so a module added to the addon is tested here
-- without anyone remembering to add it twice.
local CNS = S.loadAddon(ADDONS_DIR .. "/WicksComforts", "WicksComforts")
S.fire("ADDON_LOADED", "WicksComforts")
S.fire("PLAYER_LOGIN")
dumpErrors()
local CENTRY = WickCore.Launcher.entries.WicksComforts
local CA = CENTRY and CENTRY.addon
check(CA ~= nil, "comforts registered")
if CA then
    local db = CA.db.profile
    -- Nothing may change on a fresh install.
    local anyOn = false
    for _, v in pairs(db) do if v == true then anyOn = true end end
    local onCount = 0
    for k, v in pairs(db) do if v == true then onCount = onCount + 1 end end
    check(onCount == 1 and db.clientFixes == true, "only the client-error fix starts on")
    check(_G.LFGWhoListFrame ~= nil and _G.LFGWhoListFrame.wicksStub, "the missing group finder frame is stood in for")

    local frames = CNS.modules.frames
    S.UNITS = { target = true, player = true }

    -- Health bars. Two earlier attempts are encoded here as things that
    -- must not happen again. Hooking UnitFrameHealthBar_Update never
    -- fired, because Blizzard reaches it through a local. Setting their
    -- lockColor did fire, and put a tainted value in their table, which
    -- made their own status text formatter illegal the next time it
    -- compared secret health: every target change threw, blaming us.
    --
    -- So the test is not "is the bar green or blue". It is "did we leave
    -- their frame exactly as we found it, and is there a bar of ours on
    -- top carrying the colour".
    CLASS = "PALADIN"
    _G.TargetFrame = S.newMock("Frame")
    local theirs = S.newMock("StatusBar")
    theirs.unit = "target"
    theirs:SetStatusBarColor(0, 1, 0)
    theirs:SetMinMaxValues(0, 100)
    theirs:SetValue(70)
    theirs:Show()
    _G.TargetFrame.healthbar = theirs

    -- Anything we write into their table is a tainted value waiting for
    -- their code to read it, so record what is in there to begin with.
    local before = {}
    for k, v in pairs(theirs) do before[k] = v end

    db.classColorHealth = false
    frames:Apply()
    check(theirs.__color[1] == 0 and theirs.__color[2] == 1,
        "off by default, their bar is left the green they painted it")

    db.classColorHealth = true
    frames:Apply()
    local pal = RAID_CLASS_COLORS.PALADIN
    local ov = frames.OverlayFor(theirs)
    check(ov ~= nil and ov:IsShown(), "switched on, a bar of ours appears over theirs")
    check(math.abs(ov.__color[1] - pal.r) < 0.01,
        "and it carries the class colour: " .. tostring(ov.__color[1]))
    check(theirs.__color[1] == 0 and theirs.__color[2] == 1,
        "while their own bar is still the green it always was")

    -- The whole point. One new field on their frame is enough to throw
    -- inside TextStatusBar the next time it formats secret health.
    -- Looking a method up on the mock leaves a stand-in behind, which a
    -- real widget does not do, so those do not count. Anything else
    -- appearing is a value of ours sitting in their table waiting to
    -- taint the next thing that reads it.
    local function lookupArtifact(k, v)
        if type(v) == "function" then return true end
        return type(v) == "table" and rawget(v, "__parent") == theirs
    end
    local added = {}
    for k, v in pairs(theirs) do
        if before[k] == nil and not lookupArtifact(k, v) then added[#added + 1] = tostring(k) end
    end
    check(#added == 0, "and nothing of ours was written into their table: "
        .. table.concat(added, ", "))

    -- Ours has to track theirs, and the numbers involved are secret, so
    -- they are passed across without ever being looked at.
    theirs:SetValue(30)
    frames:Tick()
    check(ov.__value == 30, "ours follows theirs when the health moves: " .. tostring(ov.__value))
    theirs:SetMinMaxValues(0, 250)
    frames:Tick()
    check(ov.__max == 250, "and follows the scale as well")

    -- A creature has no class, so there is nothing of ours to show.
    S.IS_PLAYER = { target = false }
    frames:Apply()
    check(not ov:IsShown(), "a creature gets no overlay")
    S.IS_PLAYER = nil

    db.classColorHealth = false
    frames:Apply()
    check(not ov:IsShown(), "and switching off takes ours away")
    check(theirs.__color[2] == 1, "leaving theirs exactly as it was")

    -- Nothing coloured means nothing to poll.
    check(frames.driver ~= nil and not frames.driver:IsShown(),
        "with nothing to follow, the ticker stops")
    db.classColorHealth = true
    frames:Apply()
    check(frames.driver:IsShown(), "and runs again when there is")
    db.classColorHealth = false
    frames:Apply()

    -- The party and raid setting is a console variable and only that.
    -- Asking CompactRaidFrameContainer to refresh from our execution
    -- leaves a tainted needsUpdate on every compact frame, and their
    -- OnUpdate then compares a secret colour in our name.
    local poked = false
    _G.CompactRaidFrameContainer = { TryUpdate = function() poked = true end }
    check(frames:SetRaidClassColor(true), "the raid frame class colour setting is written")
    check(S.CVARS["raidFramesDisplayClassColor"] == "1", "as the game's own variable")
    check(not poked, "and their container is never asked to refresh by us")
    _G.CompactRaidFrameContainer = nil

    -- Moving frames is Edit Mode's job, not ours.
    _G.EditModeManagerFrame = S.newMock("Frame")
    _G.EditModeManagerFrame.CanEnterEditMode = function() return true end
    _G.ShowUIPanel = function(f) S.SHOWN_PANEL = f end
    check(frames:OpenEditMode(), "the Edit Mode button opens Blizzard's own")
    check(S.SHOWN_PANEL == _G.EditModeManagerFrame, "and opens the right frame")

    -- Never their update. Health is secret and their formatter compares
    -- it, so asking them to redraw throws in our name.
    local called = 0
    local realUpdate = UnitFrameHealthBar_Update
    UnitFrameHealthBar_Update = function(...) called = called + 1 return realUpdate(...) end
    db.classColorHealth = true
    frames:Apply()
    frames:Tick()
    UnitFrameHealthBar_Update = realUpdate
    check(called == 0, "repainting never calls Blizzard's update, which would run tainted")
    db.classColorHealth = false
    frames:Apply()

    -- ---- Quests -------------------------------------------------
    local quests = CNS.modules.quests
    S.QUEST = {}
    quests:Accept()
    check((S.QUEST.accepted or 0) == 0, "a quest is not accepted for you until you ask")

    db.autoAcceptQuests = true
    quests:Accept()
    check(S.QUEST.accepted == 1, "switched on, the quest is accepted")

    -- Shift is the escape hatch: whatever is on, the dialogs come back.
    local realShift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    quests:Accept()
    check(S.QUEST.accepted == 1, "holding shift hands the dialog back")
    IsShiftKeyDown = realShift

    db.autoTurnInQuests = true
    S.QUEST.completable = false
    quests:Progress()
    check((S.QUEST.completeAsked or 0) == 0, "a quest you have not finished is left alone")
    S.QUEST.completable = true
    quests:Progress()
    check(S.QUEST.completeAsked == 1, "one you have finished asks for the reward screen")

    -- The one thing that must never be automatic.
    S.QUEST.choices = 3
    quests:Complete()
    check(S.QUEST.rewarded == nil, "a choice of rewards is never picked for you")
    S.QUEST.choices = 1
    quests:Complete()
    check(S.QUEST.rewarded == 1, "a single reward is taken")
    S.QUEST.choices = 0
    S.QUEST.rewarded = nil
    quests:Complete()
    check(S.QUEST.rewarded == 0, "and no reward at all still hands the quest in")

    -- Gossip npcs hide the quest behind a line of dialogue.
    S.QUEST.available = { { questID = 4242 } }
    quests:Gossip()
    check(S.QUEST.pickedAvailable == 4242, "the one quest on offer is picked out of the gossip")
    S.QUEST.available = { { questID = 1 }, { questID = 2 } }
    S.QUEST.pickedAvailable = nil
    quests:Gossip()
    check(S.QUEST.pickedAvailable == nil, "but two on offer is a decision, so nothing is picked")
    S.QUEST.available = {}
    S.QUEST.active = { { questID = 7, isComplete = false }, { questID = 8, isComplete = true } }
    quests:Gossip()
    check(S.QUEST.pickedActive == 8, "and the finished one is the one handed in")
    db.autoAcceptQuests = false
    db.autoTurnInQuests = false

    -- ---- Camera and client settings -----------------------------
    local client = CNS.modules.client
    S.CVAR_CEILING["cameraDistanceMaxZoomFactor"] = 2.6
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    client:Apply()
    check(S.CVARS["cameraDistanceMaxZoomFactor"] == "1",
        "the camera is left where it was until asked")

    db.maxCameraZoom = true
    client:Apply()
    check(tonumber(S.CVARS["cameraDistanceMaxZoomFactor"]) == 2.6,
        "asked, it finds this build's ceiling rather than guessing: "
        .. tostring(S.CVARS["cameraDistanceMaxZoomFactor"]))

    db.maxCameraZoom = false
    client:Apply()
    check(S.CVARS["cameraDistanceMaxZoomFactor"] == "1", "and off puts it back")

    -- A miss must not be remembered. The console variables were not
    -- readable when this module first applied, and caching that meant
    -- the option did nothing for the rest of the session.
    client.zoomName, client.zoomWas, client.found, client.pushed = nil, nil, nil, nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = nil
    check(client:ZoomCVar() == nil, "no camera variable, nothing to do")
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    check(client:ZoomCVar() == "cameraDistanceMaxZoomFactor",
        "and it is found once the client will answer")

    -- The other spelling, for the Classic side of this client's family.
    client.zoomName, client.zoomWas, client.found = nil, nil, nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = nil
    S.CVARS["cameraDistanceMaxFactor"] = "1"
    S.CVAR_CEILING["cameraDistanceMaxFactor"] = 3.4
    db.maxCameraZoom = true
    client:Apply()
    check(tonumber(S.CVARS["cameraDistanceMaxFactor"]) == 3.4,
        "the Classic spelling works too, at its own ceiling: "
        .. tostring(S.CVARS["cameraDistanceMaxFactor"]))
    db.maxCameraZoom = false
    client:Apply()
    S.CVARS["cameraDistanceMaxFactor"] = nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    client.zoomName, client.zoomWas, client.found = nil, nil, nil

    check(S.CVARS["Sound_EnableSoundWhenGameIsInBG"] ~= "1", "background sound is off until asked")
    db.soundInBackground = true
    client:Apply()
    check(S.CVARS["Sound_EnableSoundWhenGameIsInBG"] == "1", "and on when it is")
    db.soundInBackground = false

    -- ---- Proc glow ----------------------------------------------
    local glow = CNS.modules.glow
    local button = {}
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == true, "the proc glow still works until asked to go")

    db.hideProcGlow = true
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == false, "switched on, a glow is hidden instead of shown")

    -- Off has to give the game back exactly what it had.
    db.hideProcGlow = false
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == true, "and off gives the game its own glow back")
    check(next(glow.wrapped) == nil, "with nothing of ours left wrapped around it")

    check(Minimap.__maskTex == nil, "the minimap is untouched until asked")

    db.squareMinimap = true
    db.autoLoot = true
    db.sellJunk = true
    db.autoRepair = true
    local okApply = pcall(function() WicksComfortsApply() end)
    check(okApply ~= false, "settings apply without error")
    check(Minimap.__maskTex == "Interface\\BUTTONS\\WHITE8X8", "the square mask is applied once asked")
    local ring = MODERN and MinimapCompassTexture or MinimapBorder
    check(ring and not ring:IsShown(), "the round ring art is hidden with it")
    local mmChrome = _G.WicksComfortsMinimapChrome
    check(mmChrome and mmChrome:IsShown(), "the Wick border replaces the ring")
    if MODERN then
        check(MinimapCluster.MinimapContainer:GetWidth() == Minimap:GetWidth(),
            "the container tightens to the map so the header sits flush")
    end
    db.squareMinimap = false
    WicksComfortsApply()
    check(Minimap.__maskTex ~= "Interface\\BUTTONS\\WHITE8X8", "turning it off restores the round mask")
    check(ring and ring:IsShown(), "and brings the ring art back")
    check(mmChrome and not mmChrome:IsShown(), "and takes the Wick border away again")
    if MODERN then
        check(MinimapCluster.MinimapContainer:GetWidth() == 240, "and gives the container its size back")
    end
end
S.CHAT = {}
SlashCmdList.WICK_WICKSCOMFORTS("status")
check(#S.CHAT >= 1, "/wcomfort status prints")

io.write("== missing globals reached during the run ==\n")
io.write("  ", table.concat(S.missingReport(), " "), "\n")
io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")

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


io.write("== load WickCore (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")   -- file list straight off WickCore.toc
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
S.PET_SPELLS = {
    { "Bite", "active", 132127, 17253 },
    { "Growl", "active", 132270, 2649 },
    { "Furious Howl", "active", 136168, 24604 },
    { "Avoidance", "passive", 132279, 24672 },
}
local BNS = S.loadAddon(ADDONS_DIR .. "/WicksBeastsAndThings", "WicksBeastsAndThings", { "Core.lua", "Pet.lua", "Ammo.lua", "Beasts.lua", "Bestiary.lua", "UI.lua" })
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
    -- ========================================================
    -- The bestiary: the animals, not the families.
    -- ========================================================
    -- Beasts.lua files what a Wolf can do. Nothing filed the wolf. A pet
    -- in the stable reads nothing at all to the client, so the only place
    -- this can come from is a record kept while the animal is out.
    local Bst = BNS.Bestiary
    check(Bst ~= nil, "the bestiary module loaded")

    -- The atlas is a cache and the roster is not. The store is about
    -- fourteen kilobytes for the whole suite and five recorded families
    -- already come to ten on their own, so an atlas left in it would crowd
    -- out every other addon's settings. It rebuilds from the pet spell
    -- book; a stabled pet reads as nothing, so the roster cannot.
    check(BADDON.opts.storeExclude and BADDON.opts.storeExclude[1] == "global",
        "the family atlas is kept out of the settings store")
    check(BNS.A.db.char.pets ~= nil, "while the roster stays in it")

    Bst:Forget()
    S.PET_NAME, S.PET_FAMILY = "Grizzle", "Bear"
    check(Bst:Record() ~= nil, "a pet that is out is written down")
    check(Bst:Count() == 1, "one animal recorded, got " .. Bst:Count())
    local grizzle = Bst:Find("Grizzle")
    check(grizzle ~= nil and grizzle.family == "Bear", "with its family: " .. tostring(grizzle and grizzle.family))
    check(grizzle.diet ~= nil and #grizzle.diet > 0, "and what it eats")

    -- Calling the same animal again is the same line, not a second one.
    Bst:Record()
    check(Bst:Count() == 1, "calling it again does not duplicate it, got " .. Bst:Count())
    check(grizzle.seen == 2, "it counts the times it was out: " .. tostring(grizzle.seen))

    -- A second animal of a different family is a second line. The family
    -- alone would not do as a key, since a hunter can own two wolves.
    S.PET_NAME, S.PET_FAMILY = "Skitter", "Spider"
    Bst:Record()
    check(Bst:Count() == 2, "a second animal is a second line, got " .. Bst:Count())
    local all = Bst:All()
    check(all[1].name == "Skitter", "most recently out comes first: " .. tostring(all[1].name))
    check(Bst:Current() ~= nil and Bst:Current().name == "Skitter", "and the one out now is known")

    -- A level the client will not hand over must not wipe the one it did.
    local skitter = Bst:Find("Skitter")
    local hadLevel = skitter.level
    check(hadLevel ~= nil, "a level was recorded: " .. tostring(hadLevel))
    local realLevel = UnitLevel
    UnitLevel = function(unit) if unit == "pet" then return nil end return realLevel(unit) end
    Bst:Record()
    check(Bst:Find("Skitter").level == hadLevel, "a level the client withholds leaves the last one alone")
    UnitLevel = realLevel

    -- The food pin belongs to the animal. It used to be one item for the
    -- hunter, which silently misapplies the moment you own two pets that
    -- eat different things.
    check(Bst:Pin(6948) == "Skitter", "the pin goes to the animal that is out")
    check(Bst:PinnedFood() == 6948, "and reads back for that animal")
    S.PET_NAME, S.PET_FAMILY = "Grizzle", "Bear"
    Bst:Record()
    check(Bst:PinnedFood() == nil, "the other animal does not inherit it")

    S.CHAT = {}
    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("pets")
    local plist = table.concat(S.CHAT, " | ")
    check(plist:find("Grizzle") ~= nil and plist:find("Skitter") ~= nil, "/wbt pets lists them: " .. plist:sub(1, 90))
    S.CHAT = {}
    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("pets Skitter")
    check(Bst:Count() == 1, "/wbt pets <name> forgets one, left " .. Bst:Count())
    check(Bst:Find("Grizzle") ~= nil, "and leaves the others alone")

    -- Its own tab, alongside Beasts.
    check(kit.tabs.bestiary ~= nil, "the kit grew a Bestiary tab")
    kit:Select("bestiary")
    check(kit.panes.bestiary:IsShown(), "selecting it shows the pane")
    check(kit.panes.beasts:IsShown() == false, "and puts the Beasts pane away")
    local brows = BNS.Bestiary.pane.rows
    local bshown = 0
    for _, r in ipairs(brows) do if r:IsShown() then bshown = bshown + 1 end end
    check(bshown == 1, "a row per animal, got " .. bshown)
    check(tostring(brows[1].name:GetText()):find("Grizzle") ~= nil,
        "naming the animal: " .. tostring(brows[1].name:GetText()))
    check(tostring(brows[1].age:GetText()) == "out", "and marking the one that is out")
    -- The window: a roster on the left, a page on the right. The page is
    -- the join the two records exist for, so it has to name what the
    -- family brings alongside the animal itself.
    S.PET_NAME, S.PET_FAMILY = "Grizzle", "Bear"
    Bst:Record()
    S.CHAT = {}
    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("bestiary")
    local win = _G.WicksBestiaryWindow
    check(win ~= nil and win:IsShown(), "/wbt bestiary opens the window")
    check(Bst.selectedKey ~= nil, "with something selected rather than a blank page")
    local wrows, wshown = win.rows, 0
    for _, r in ipairs(wrows) do if r:IsShown() then wshown = wshown + 1 end end
    check(wshown == 1, "a roster row per animal, got " .. wshown)
    check(wrows[1].hl:IsShown(), "the selected one is highlighted")
    check(tostring(wrows[1].tag:GetText()):find("out") ~= nil, "and tagged as out: " .. tostring(wrows[1].tag:GetText()))

    -- Icons. The game names its own pet icons after the family, so the
    -- path is derived; only the families whose file name differs from the
    -- printed name are listed out.
    check(Bst:FamilyIcon("Bear") == "Interface\\Icons\\Ability_Hunter_Pet_Bear",
        "a family icon is derived from its name: " .. Bst:FamilyIcon("Bear"))
    check(Bst:FamilyIcon("Wind Serpent") == "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
        "a two word family loses the space: " .. Bst:FamilyIcon("Wind Serpent"))
    check(Bst:FamilyIcon(nil):find("Ability_Hunter_BeastCall") ~= nil,
        "and an unknown family falls back rather than asking for a file that is not there")
    check(wrows[1].icon.__tex == Bst:FamilyIcon("Bear"),
        "the roster row carries it: " .. tostring(wrows[1].icon.__tex))
    check(tostring(win.detail.name:GetText()) == "Grizzle", "the page names it: " .. tostring(win.detail.name:GetText()))
    check(tostring(win.detail.diet:GetText()):find("Fish") ~= nil,
        "and says what it eats: " .. tostring(win.detail.diet:GetText()))
    check(win.detail.vLevel:GetText() ~= "-", "with its level in its own cell: " .. tostring(win.detail.vLevel:GetText()))
    check(win.detail.dot:IsShown() and win.detail.outText:IsShown(), "and marked out while it is out")
    check(win.detail.portraitFrame:IsShown(), "the portrait is framed")
    check(win.detail.empty:IsShown() == false, "with no empty notice while there is an animal")

    -- Bear was never recorded in the family atlas, so there is nothing to
    -- join; a Wolf was. The page has to handle both.
    check(tostring(win.detail.abilHead:GetText()):find("NOT TAMED") ~= nil,
        "an unrecorded family says so rather than claiming it brings nothing: " .. tostring(win.detail.abilHead:GetText()))
    S.PET_NAME, S.PET_FAMILY = "Fang", "Wolf"
    Bst:Record()
    Bst.selectedKey = Bst:Key("Fang", "Wolf")
    Bst:RefreshWindow()
    check(tostring(win.detail.abilHead:GetText()):find("WOLF") ~= nil,
        "a recorded family is named: " .. tostring(win.detail.abilHead:GetText()))
    -- Abilities are drawn now, not spelled out. The book gives an icon and
    -- a spell id, so each one is a chip you can point at.
    local chips, nchips = win.detail.chips, 0
    for _, b in ipairs(chips) do if b:IsShown() then nchips = nchips + 1 end end
    check(nchips == 4, "a chip per ability the family brings, got " .. nchips)
    -- What sets the family apart leads, alphabetically within each group,
    -- so find them by name rather than assuming a position.
    local byName = {}
    for i, b in ipairs(chips) do if b:IsShown() then byName[b.abilityName] = i end end
    check(byName["Furious Howl"] ~= nil and byName["Bite"] ~= nil, "every ability got a chip")
    check(byName["Avoidance"] < byName["Bite"] and byName["Furious Howl"] < byName["Bite"],
        "what sets the family apart comes before the plumbing")
    local howl = chips[byName["Furious Howl"]]
    check(howl.icon.__tex == 136168, "carrying its icon: " .. tostring(howl.icon.__tex))
    check(howl.spellID == 24604, "and its spell, so the tooltip is the real one")
    check(howl.shared == false and howl.icon.__desaturated == false, "and is not dimmed")
    local bite = chips[byName["Bite"]]
    check(bite.shared == true and bite.icon.__desaturated == true,
        "while the plumbing is greyed rather than hidden")
    check(chips[byName["Avoidance"]].passive == true, "a passive ability is known to be one")
    check(win.detail.abil:IsShown() == false, "with no leftover text line while every ability has a chip")

    -- Pointing at one has to say something, whether or not the client will
    -- hand over a spell tooltip.
    GameTooltip.__lines = {}
    bite.__scripts.OnEnter(bite)
    local tip = table.concat(GameTooltip.__lines, " | ")
    check(tip:find("Most families bring this") ~= nil, "the tooltip says when one is shared: " .. tip)
    GameTooltip.__lines = {}
    howl.__scripts.OnEnter(howl)
    check(table.concat(GameTooltip.__lines, " | "):find("Sets this family apart") ~= nil,
        "and says when one is not")
    howl.__scripts.OnLeave(howl)

    -- An atlas filed before icons were captured has the names and nothing
    -- else, and only the family of the pet that is out can be read again.
    -- Rather than make the player summon every animal in the stable, the
    -- name is handed to the client, which knows the spell either way.
    local wolfRec = BNS.A.db.global.families["Wolf"]
    local keptIcons = wolfRec.icons
    wolfRec.icons = {}
    Bst:RefreshWindow()
    local stillShown = 0
    for _, b in ipairs(chips) do if b:IsShown() then stillShown = stillShown + 1 end end
    check(stillShown == 4, "an atlas with no icons still draws, resolved by name, got " .. stillShown)
    check(win.detail.abil:IsShown() == false, "so there is nothing left to spell out")
    -- A guess must never be written back, or it would outrank the real
    -- read the next time the pet is out.
    check(next(wolfRec.icons) == nil, "and the guess is not written into the atlas")

    -- A name the client cannot place still has to say something.
    S.UNKNOWN_SPELLS = { ["Furious Howl"] = true, ["Bite"] = true, ["Growl"] = true, ["Avoidance"] = true }
    BNS.beasts:ForgetResolved()
    Bst:RefreshWindow()
    local noneShown = 0
    for _, b in ipairs(chips) do if b:IsShown() then noneShown = noneShown + 1 end end
    check(noneShown == 0, "nothing the client can place, so no chips, got " .. noneShown)
    check(win.detail.abil:IsShown() and tostring(win.detail.abil:GetText()):find("Furious Howl") ~= nil,
        "and it falls back to naming them: " .. tostring(win.detail.abil:GetText()))
    S.UNKNOWN_SPELLS = nil
    BNS.beasts:ForgetResolved()
    wolfRec.icons = keptIcons
    Bst:RefreshWindow()

    -- Forgetting the selected animal must not leave the page pointing at a
    -- record that is gone.
    win.forget.__scripts.OnClick()
    check(Bst:Find("Fang") == nil, "the Forget button forgets the selected animal")
    check(Bst.selectedKey == Bst:Key("Grizzle", "Bear"), "and the page falls to what is left")
    check(tostring(win.detail.name:GetText()) == "Grizzle", "showing it: " .. tostring(win.detail.name:GetText()))

    Bst:Forget()
    Bst:RefreshWindow()
    check(win.detail.empty:IsShown(), "an empty roster shows the notice instead of a page")
    check(win.forget:IsShown() == false, "and takes the buttons away")

    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("bestiary")
    check(win:IsShown() == false, "/wbt bestiary again closes it")

    kit:Select("beasts")
    S.PET_NAME, S.PET_FAMILY = nil, "Wolf"

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

io.write("== Stances and Things ==\n")
CLASS = "WARRIOR"
S.STANCE, S.STANCE_COUNT = 1, 3          -- a warrior past thirty, in Battle
S.loadAddon(ADDONS_DIR .. "/WicksStancesAndThings", "WicksStancesAndThings")
S.fire("ADDON_LOADED", "WicksStancesAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local SENTRY = WickCore.Launcher.entries.WicksStancesAndThings
local SA = SENTRY and SENTRY.addon
check(SA ~= nil, "stances launcher registered")
local sstrip = _G.WicksStancesStrip
check(sstrip ~= nil and sstrip:IsShown(), "stance strip shown for a warrior")
check(_G.WicksStancesButton1 and _G.WicksStancesButton2 and _G.WicksStancesButton3,
    "a keybindable button per stance")
check(_G.WicksStancesSmartButton ~= nil, "and one for the smart key")

-- The macro is the whole feature: it has to name the stance the ability
-- needs and only cast the ability once you are in it. Two lines, because
-- the game will not change stance and swing off the same press.
local Stances
for _, fr in ipairs(S.frames) do if fr.__name == "WicksStancesEvents" then Stances = true end end
check(Stances, "stances event frame created")

local smart = _G.WicksStancesSmartButton
local charge = tostring(smart:GetAttribute("macrotext"))
check(charge:find("/cast %[nostance:1%] Battle Stance") ~= nil,
    "the smart key swaps to Battle for Charge: " .. charge:gsub("\n", " | "))
check(charge:find("/cast %[stance:1%] Charge") ~= nil, "and casts Charge once there")
check(tostring(_G.WicksStancesButton3:GetAttribute("macrotext")):find("Berserker Stance") ~= nil,
    "the third button swaps to Berserker")

-- An ability in another stance re-routes.
S.CHAT = {}
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Shield Wall")
local sw = tostring(smart:GetAttribute("macrotext"))
check(sw:find("nostance:2") ~= nil and sw:find("%[stance:2%] Shield Wall") ~= nil,
    "Shield Wall routes to Defensive: " .. sw:gsub("\n", " | "))

-- One with no stance requirement is cast where you stand, not routed.
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Execute")
local ex = tostring(smart:GetAttribute("macrotext"))
check(ex:find("stance") == nil and ex:find("/cast Execute") ~= nil,
    "an ability needing no stance is cast where you stand: " .. ex:gsub("\n", " | "))
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Charge")

-- Secure attributes cannot be written in combat, and the strip has to
-- pick the change up the moment it clears rather than staying stale.
COMBAT = true
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Intercept")
check(tostring(smart:GetAttribute("macrotext")):find("Intercept") == nil,
    "nothing is written to a secure button in combat")
COMBAT = false
S.fire("PLAYER_REGEN_ENABLED")
check(tostring(smart:GetAttribute("macrotext")):find("%[stance:3%] Intercept") ~= nil,
    "and it catches up when combat ends: " .. tostring(smart:GetAttribute("macrotext")):gsub("\n", " | "))
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Charge")

-- A stance the character has not learned reads as unlearned, not missing.
S.STANCE_COUNT = 1
sstrip.__scripts.OnShow(sstrip)
check(SA.kit ~= nil, "stances has a kit")
S.STANCE_COUNT = 3

S.CHAT = {}
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("status")
local sline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wst status prints")
check(sline:find("Battle Stance") ~= nil, "and names the stance you are in: " .. sline:sub(1, 90))

try("stances strip toggle", function() WicksStancesAndThings_Toggle(); WicksStancesAndThings_Toggle() end)
try("stances kit", function() SlashCmdList.WICK_WICKSSTANCESANDTHINGS("kit") end)
if SA then
    local srows = SA.kit.checklist:Evaluate()
    check(#srows == 4, "stances checklist 4 rows, got " .. #srows)
    check(srows[2].state == "ok", "in a stance reads ok while in one: " .. tostring(srows[2].state))
    check(SA.cooldowns ~= nil, "stances has a cooldown bar")
end
S.STANCE, S.STANCE_COUNT = 0, 0

io.write("== Trade Hall ==\n")
CLASS = "HUNTER"
local THNS = S.loadAddon(ADDONS_DIR .. "/WicksTradeHall", "WicksTradeHall")
S.fire("ADDON_LOADED", "WicksTradeHall")
S.fire("PLAYER_LOGIN")
dumpErrors()
local THENTRY = WickCore.Launcher.entries.WicksTradeHall
local THA = THENTRY and THENTRY.addon
check(THA ~= nil and THA.enabled, "trade hall registered and enabled")
check(_G.WicksTradeHallBar ~= nil and _G.WicksTradeHallBar:IsShown(), "the session bar is up")

local Lg, P = THNS.Ledger, THNS.Prices

-- Money is plain on this client, so the gold delta is ordinary
-- arithmetic. The purse is driven by hand here.
local realMoney = GetMoney
local purse = 100000
GetMoney = function() return purse end

check(Lg:Start(), "a session starts")
check(Lg.active and Lg.startMoney == 100000, "and takes the purse as its starting point")
check(not Lg:Start(), "starting twice does nothing")

purse = 112345
S.fire("PLAYER_MONEY")
check(Lg.goldDelta == 12345, "gold earned is the difference: " .. tostring(Lg.goldDelta))
check(Lg.totalCopper == 12345, "and the total follows it")

-- A grey collapses into one Junk row however many drop; anything else
-- is its own line.
S.ITEMS = S.ITEMS or {}
S.ITEMS[2589] = { name = "Linen Cloth", quality = 1, sellPrice = 15 }
S.ITEMS[3300] = { name = "Rabbit's Foot", quality = 0, sellPrice = 40 }
check(Lg:AddLoot("You receive loot: |cff9d9d9d|Hitem:3300::::::::20:::::::::|h[Rabbit's Foot]|h|r."), "a grey is taken")
Lg:AddLoot("You receive loot: |cff9d9d9d|Hitem:3300::::::::20:::::::::|h[Rabbit's Foot]|h|r x3.")
check(Lg.loot.junk ~= nil and Lg.loot.junk.count == 4, "greys collapse into one Junk row: " .. tostring(Lg.loot.junk and Lg.loot.junk.count))
check(Lg.loot.junk.copper == 160, "carrying the running total, not a unit price: " .. tostring(Lg.loot.junk.copper))
Lg:AddLoot("You receive loot: |cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r x5.")
check(Lg.loot["2589"] ~= nil and Lg.loot["2589"].count == 5, "a white gets its own line")
check(Lg.totalCopper == 12345 + 160 + 15 * 5, "and the total counts each by its own rule: " .. tostring(Lg.totalCopper))

-- An item the client cannot price counts as nothing, and says so.
S.UNKNOWN = S.UNKNOWN or {}
S.UNKNOWN[11111] = true
Lg:AddLoot("You receive loot: |cffffffff|Hitem:11111::::::::20:::::::::|h[Something]|h|r.")
check(Lg.loot["11111"].source == "unknown", "an unpriceable item is marked, not guessed at")
local conf, known, total = P:Confidence(Lg.loot)
-- Three kinds, not four: the two greys merged into one junk row.
check(known == 2 and total == 3, "and the confidence says how much of the total is real: " .. known .. "/" .. total)

-- When the server answers late it is repriced, not left wrong.
S.UNKNOWN[11111] = nil
S.ITEMS[11111] = { name = "Something", quality = 2, sellPrice = 500 }
check(Lg:Reprice(), "a late arrival is repriced")
check(Lg.loot["11111"].copper == 500 and Lg.loot["11111"].source == "vendor", "with the real price")

-- A reload must not lose the run.
local carried = Lg.totalCopper
Lg.Persist()
Lg.active, Lg.totalCopper, Lg.loot = false, 0, {}
check(Lg:Resume(), "a saved session resumes")
check(Lg.totalCopper == carried, "with its total intact: " .. tostring(Lg.totalCopper))

check(Lg:Stop(), "the session stops")
check(#Lg:History() == 1, "and lands in history")
Lg:Start(); Lg:Stop()
check(#Lg:History() == 1, "a session that earned nothing is not filed")

-- A running total is not a setting: the macro store must not carry it,
-- or a long night of looting crowds out the settings that matter.
check(THA.opts.storeExclude ~= nil and THA.opts.storeExclude[1] == "char",
    "the session is excluded from the macro store")

-- The board reads the trade channel. Reading chat is not restricted on
-- this client, only sending, so this is the piece that ports whole.
local Bd = THNS.Board
S.CHANNELS = { [1] = "General", [2] = "Trade - City", [5] = "LookingForGroup" }
GetChannelList = function() return 1, "General", false, 2, "Trade - City", false, 5, "LookingForGroup", false end
Bd:RebuildChannels()
check(Bd:Watching(2) == true, "a channel named Trade is watched")
check(Bd:Watching(1) == false and Bd:Watching(5) == false, "General and LookingForGroup are not")

Bd:Clear()
check(Bd:Handle("WTS [Copper Bar] x20 cheap pst", "Seller-Realm", 2), "a sell advert is taken")
check(Bd.listings[1] and Bd.listings[1].category == "WTS", "and read as selling: " .. tostring(Bd.listings[1] and Bd.listings[1].category))
check(Bd.listings[1].name == "Seller", "with the realm stripped off the name")
check(not Bd:Handle("WTS [Copper Bar] x20 cheap pst", "Seller-Realm", 2), "the same person repeating it is one listing, not two")
check(#Bd.listings == 1, "so the board still has one: " .. #Bd.listings)

check(Bd:Handle("WTB arcanite bar paying well", "Buyer", 2), "a buy advert is taken")
check(Bd.listings[1].category == "WTB", "and read as buying: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Free enchants at the bank, tips welcome", "Enchanter", 2), "an enchanter is taken")
check(Bd.listings[1].category == "ENCHANT", "and read as enchanting: " .. tostring(Bd.listings[1].category))

-- Both of these landed in Misc on the live board, which is what sent me
-- back to the rule. An advert with no service word is still an advert,
-- and someone looking for an enchant belongs on the enchanting shelf
-- next to the person offering one.
check(Bd:Handle("Enchanting in Undercity", "Ench2", 2), "a bare enchant advert is taken")
check(Bd.listings[1].category == "ENCHANT", "and is enchanting, not misc: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("LF agility to gloves enchant", "Ench3", 2), "someone looking for an enchant is taken")
check(Bd.listings[1].category == "ENCHANT", "and is enchanting too: " .. tostring(Bd.listings[1].category))

-- And the mistake in the other direction, which the fix nearly made: a
-- slot name on its own must not pull a sale into enchanting.
check(Bd:Handle("WTS gloves and boots cheap", "Vendor", 2), "a sale naming armour slots is taken")
check(Bd.listings[1].category == "WTS", "and stays selling: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Free crusader at the bank, tips welcome", "Ench4", 2), "an enchant named without the word is taken")
check(Bd.listings[1].category == "ENCHANT", "and reads as enchanting: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Portals to Stormwind, 5s, pst", "Mage", 2), "a portal advert is taken")
check(Bd.listings[1].category == "TRAVEL", "and read as travel: " .. tostring(Bd.listings[1].category))

-- A group advert is not trade, and the blacklist runs before the rules.
check(not Bd:Handle("LFM Deadmines need tank and healer", "Leader", 2), "a group advert is not a listing")
check(not Bd:Handle("Guild recruiting for raids, apply within", "Recruiter", 2), "nor is guild recruitment")
-- Unless it says outright that it is selling.
check(Bd:Handle("WTS Deadmines boost, raid geared", "Booster", 2), "but a boost being sold is")

-- Nothing from a channel we do not watch.
local before = #Bd.listings
check(not Bd:Handle("WTS everything cheap", "Spammer", 5), "a channel we do not watch is ignored")
check(#Bd.listings == before, "and nothing lands")

-- An item link reads as the item name, not the markup.
Bd:Clear()
Bd:Handle("WTS |cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r x20", "Tailor", 2)
check(Bd.listings[1] and Bd.listings[1].message:find("Linen Cloth", 1, true) ~= nil,
    "a link reads as the item name: " .. tostring(Bd.listings[1] and Bd.listings[1].message))
check(Bd.listings[1].message:find("|c") == nil, "with no markup left in it")

-- A long advert ran off the panel and over whatever was behind it.
-- The text is bounded by where the age begins and never wraps.
THNS.UI:Build()
THNS.UI.panel:Show()
THNS.UI:Select("board")
local prow = THNS.UI.panel.rows[1]
check(prow ~= nil, "a board row was drawn")
if prow then
    check(prow.left.__wordWrap == false, "a listing is one line, never wrapped")
    local bounded = false
    for _, pt in ipairs(prow.left.__points or {}) do if pt[1] == "RIGHT" then bounded = true end end
    check(bounded, "and is bounded on the right so it cannot overflow")
end
THNS.UI.panel:Hide()

-- Anything nobody repeats ages off.
Bd.listings[1].lastSeen = time() - (25 * 60)
check(Bd:Prune() == 1, "a listing nobody repeated for twenty minutes drops off")
check(#Bd.listings == 0, "leaving the board empty")

-- The bar has a control. A tracker you cannot start is an ornament.
local bar = _G.WicksTradeHallBar
check(bar.go ~= nil, "the session bar has a start button")
-- Drawn, not typed: this client's font has no play or stop glyph and
-- the bar showed an empty box.
check(bar.go.rows ~= nil and #bar.go.rows == 8, "built from textures rather than a character")
bar.go:SetShape(false, { 0.31, 0.78, 0.47 })
local widths = {}
for i, t in ipairs(bar.go.rows) do widths[i] = t.__w end
check(widths[1] < widths[4] and widths[4] > widths[8], "stopped, it is a triangle: " .. table.concat(widths, ","))
bar.go:SetShape(true, { 0.88, 0.29, 0.29 })
local same = true
for _, t in ipairs(bar.go.rows) do if t.__w ~= bar.go.rows[1].__w then same = false end end
check(same, "running, it is a square")
local wasActive = Lg.active
bar.go.__scripts.OnClick(bar.go)
check(Lg.active ~= wasActive, "clicking it starts or stops the session")
if Lg.active then bar.go.__scripts.OnClick(bar.go) end
check(not Lg.active, "and clicking again stops it")

S.CHAT = {}
SlashCmdList.WICK_WICKSTRADEHALL("status")
check(#S.CHAT >= 2, "/wth status prints")
try("trade hall window", function() WicksTradeHall_Toggle(); WicksTradeHall_Toggle() end)
try("trade board tab", function() THNS.UI:Select("board"); THNS.UI:Select("ledger") end)
GetMoney = realMoney
S.ITEMS[2589], S.ITEMS[3300], S.ITEMS[11111] = nil, nil, nil

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
    -- The group finder is load on demand. Claiming its frame name before
    -- it has loaded takes the name away from Blizzard, and the who panel
    -- then opens with its close button and side tabs drawn and nothing in
    -- the middle. So: nothing until their addon has actually loaded.
    check(_G.LFGWhoListFrame == nil, "no stub while the group finder has not loaded")
    S.LOADED["Blizzard_GroupFinder_VanillaStyle"] = true
    S.fire("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
    check(_G.LFGWhoListFrame ~= nil and _G.LFGWhoListFrame.wicksStub,
        "once it has loaded and still has no frame, the stub stands in")

    -- And if Blizzard does build one, theirs is left alone.
    CNS.modules.fixes.stubbedWhoList = nil
    _G.LFGWhoListFrame = S.newMock("Frame")
    CNS.modules.fixes:Apply()
    check(not _G.LFGWhoListFrame.wicksStub, "a real frame from Blizzard is never replaced")
    local report = table.concat(CNS.modules.fixes:WhoReport(), " | ")
    check(report:find("Blizzard's") ~= nil, "and the report says whose it is: " .. report:sub(1, 80))
    _G.LFGWhoListFrame = nil
    S.LOADED["Blizzard_GroupFinder_VanillaStyle"] = nil
    CNS.modules.fixes.stubbedWhoList = nil

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
    -- The hue follows the class colour set WickCore is on. Classic paladin
    -- pink is F58CBA where the client table says F48CBA: one step of red.
    check(tostring(ov.__statusTex or ""):find("UI%-StatusBar") ~= nil,
        "the overlay draws with Blizzard's shaded bar texture, not a flat fill")
    WickCore.Chrome.classColorSet = "classic"
    frames:Apply()
    check(math.abs(ov.__color[1] - 0xF5 / 255) < 0.002, "switching WickCore to the Classic-era set changes the bar: " .. tostring(ov.__color[1]))
    WickCore.Chrome.classColorSet = "client"
    frames:Apply()
    check(math.abs(ov.__color[1] - pal.r) < 0.01, "and back to the client set restores it")

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

    -- Repair on arrival. This shipped broken: the cost was fetched as
    -- `local cost, canRepair = GetRepairAllCost and GetRepairAllCost()`,
    -- and `and` keeps only the first return, so canRepair was always nil
    -- and the guard on the next line sent it home every time.
    db.autoRepair = true
    db.guildRepair = false
    S.REPAIR_COST, S.REPAIRED, S.MONEY = 5000, nil, 100000
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "self", "arriving at a merchant repairs: " .. tostring(S.REPAIRED))

    -- Nothing to repair is not a failure, it is just quiet.
    S.REPAIR_COST, S.REPAIRED = 0, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "with nothing broken it does not pay to repair nothing")

    -- Guild funds first when they are offered and they cover it.
    db.guildRepair = true
    S.GUILD_REPAIR, S.GUILD_FUNDS = true, 10000
    S.REPAIR_COST, S.REPAIRED = 5000, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "guild", "guild funds are used when they cover it: " .. tostring(S.REPAIRED))

    -- Guild funds that fall short fall back to the player's own.
    S.GUILD_FUNDS, S.REPAIRED = 100, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "self", "and fall back to your own when they do not: " .. tostring(S.REPAIRED))

    -- Too poor to repair says so rather than failing silently.
    db.guildRepair = false
    S.GUILD_REPAIR = false
    S.MONEY, S.REPAIRED = 100, nil
    S.CHAT = {}
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "too poor to repair does not try")
    check(table.concat(S.CHAT, " "):find("cannot afford") ~= nil, "and says why")
    S.MONEY = 100000

    -- Off means off.
    db.autoRepair = false
    S.REPAIR_COST, S.REPAIRED = 5000, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "and with the setting off it leaves the repair alone")
    db.autoRepair = true

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

-- ============================================================
-- WickCore missing
-- ============================================================
--
-- Every addon used to declare WickCore with Dependencies, which is a hard
-- one: with WickCore absent the client refuses to load the addon at all, so
-- none of our code runs and the player gets a greyed line in the AddOns list
-- and nothing else. The assert each addon carried could never fire.
--
-- They ask with OptionalDeps now and say so themselves. This loads two of
-- them with no WickCore in sight and checks they come up quietly, then speak
-- once, together, with somewhere to go.
io.write("== WickCore missing ==\n")
do
    local keepCore, keepLib = WickCore, LibStub
    WickCore, _G.WickCore = nil, nil
    _G.WicksNeedCore = nil
    S.CHAT = {}

    local ok1 = pcall(S.loadAddon, ADDONS_DIR .. "/WicksBeastsAndThings", "WicksBeastsAndThings",
        { "Core.lua", "Pet.lua", "Ammo.lua", "Beasts.lua", "Bestiary.lua", "UI.lua" })
    check(ok1, "Wick's Beasts and Things loads with no WickCore rather than erroring")
    local ok2 = pcall(S.loadAddon, ADDONS_DIR .. "/WicksTradeHall", "WicksTradeHall",
        { "Core.lua", "Prices.lua", "Ledger.lua", "Board.lua", "UI.lua" })
    check(ok2, "so does Wick's Trade Hall")

    local need = _G.WicksNeedCore
    check(type(need) == "table" and #need == 2,
        "both put their name down, got " .. tostring(need and #need))

    -- Nothing is said at load: the chat frame is not up yet, and one line
    -- per addon would be a wall with the whole suite installed.
    check(#S.CHAT == 0, "and nothing is said before the player is in the world")

    S.fire("PLAYER_LOGIN")
    local said = table.concat(S.CHAT, " | ")
    check(#S.CHAT == 1, "one line for the lot of them, got " .. #S.CHAT)
    check(said:find("Wick's Beasts and Things", 1, true) and said:find("Wick's Trade Hall", 1, true),
        "naming each: " .. said:sub(1, 110))
    check(said:find("wicksmods.com", 1, true) ~= nil, "with somewhere to get it")
    check(said:find("need", 1, true) ~= nil, "and reading as plural for two of them")

    WickCore, _G.WickCore, LibStub = keepCore, keepCore, keepLib
    _G.WicksNeedCore = nil
end


io.write("== missing globals reached during the run ==\n")
io.write("  ", table.concat(S.missingReport(), " "), "\n")
io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")

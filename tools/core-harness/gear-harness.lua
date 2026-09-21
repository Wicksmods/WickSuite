-- Wick's Gear, offline.
--   args: coreDir, addonsDir, mode, stubPath
--
-- The interesting parts are not that a list appears. They are that item
-- data is requested before anything is scored, that a class is never
-- offered gear it cannot wear, and that a piece is judged against what
-- is already on the character rather than in a vacuum.

local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)

local failures, passes = 0, 0
local function check(cond, label)
    io.write(cond and "  ok    " or "  FAIL  ", label, "\n")
    if cond then passes = passes + 1 else failures = failures + 1 end
end

CLASS = "ROGUE"

S.loadAddon(CORE_DIR, "WickCore", {
    "LibStub.lua", "Core.lua", "Client.lua", "Dialect.lua", "Restrict.lua",
    "Locale.lua", "Chrome.lua", "Theme.lua", "Profiles.lua", "Options.lua",
    "Launcher.lua", "Version.lua", "Talents.lua", "Checklist.lua",
    "Racials.lua", "Cooldowns.lua", "Kit.lua",
})
S.fire("ADDON_LOADED", "WickCore")

io.write("== Wick's Gear ==\n")

-- Three pieces standing in for the real data: leather the rogue wants,
-- mail they cannot wear, and a two-hander they cannot wield.
S.ITEMS = {
    [7719] = { equipLoc = "INVTYPE_LEGS",  classID = 4, subClassID = 2,
               stats = { ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 4 } },
    [6463] = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3,
               stats = { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 19 } },
    [7717] = { equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5,
               stats = { ITEM_MOD_STRENGTH_SHORT = 10 } },
}
S.UNCACHED = { [7719] = true, [6463] = true, [7717] = true }
S.REQUESTED = 0

local ns = S.loadAddon(ADDONS_DIR .. "/WicksGear", "WicksGear",
    { "Data.lua", "Score.lua", "Core.lua", "Doll.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksGear")
S.fire("PLAYER_LOGIN")

check(ns.DUNGEONS ~= nil and ns.DUNGEON_ORDER ~= nil, "the data file loaded")
check(#ns.DUNGEON_ORDER >= 10, #ns.DUNGEON_ORDER .. " dungeons carried")
local ids = ns.AllItemIDs()
check(#ids > 200, #ids .. " distinct items, deduplicated")
check(ns.WEIGHTS.ROGUE ~= nil and ns.PROFICIENCY.ROGUE ~= nil, "weights and proficiencies came with it")

-- The client answers item queries from the server and throttles hard,
-- so they leave in small batches rather than all at once. Asking for
-- everything the moment the window opened got most of them dropped.
S.UNCACHED = { [7719] = true, [6463] = true, [7717] = true }
S.REQUESTED = 0
local missing = ns.Score:Want({ 7719, 6463, 7717 })
check(missing == 3, "three unknown items are queued, got " .. missing)
check(S.REQUESTED > 0 and S.REQUESTED <= 12,
    "and they leave a batch at a time rather than in a flood: " .. S.REQUESTED)

-- The spacing itself cannot be seen here, because the stub runs timers
-- the instant they are set and the queue drains in one go. What can be
-- seen is that nothing is asked for twice, which is the other half of
-- not flooding the server.
S.REQUESTED = 0
S.UNCACHED = {}
local many = {}
for i = 1, 100 do many[i] = 900000 + i; S.UNCACHED[many[i]] = true end
ns.Score:Want(many)
check(S.REQUESTED == 100, "a hundred unknown items are each asked for: " .. S.REQUESTED)
S.REQUESTED = 0
ns.Score:Want(many)
check(S.REQUESTED == 0, "and asking again does not ask the server again: " .. S.REQUESTED)

-- Anything the client already knows is never asked for at all.
S.UNCACHED = {}
S.REQUESTED = 0
ns.Score:Want({ 7719, 6463 })
check(S.REQUESTED == 0, "known items are not requested, got " .. S.REQUESTED)

S.UNCACHED = {}   -- they have arrived now; the rest of the run assumes so

-- Proficiency. A rogue in mail, or holding a two-handed mace, is how you
-- can tell a gear list has never been used by anyone.
local leather = ns.Score:Info(7719)
local mail    = ns.Score:Info(6463)
local twoHand = ns.Score:Info(7717)
check(ns.Score:Usable(leather), "a rogue may wear leather")
check(not ns.Score:Usable(mail), "but not mail")
check(not ns.Score:Usable(twoHand), "and may not wield a two-handed mace")

-- Cloaks, rings and necks carry a negative subclass and no restriction.
S.ITEMS[9999] = { equipLoc = "INVTYPE_CLOAK", classID = 4, subClassID = -6 }
check(ns.Score:Usable(ns.Score:Info(9999)), "a cloak has no armour type to fail")

-- Scoring follows the weights: agility is a rogue's primary, stamina less.
S.LINK_TO_ID = { ["|Hitem:7719|h"] = 7719 }
local pts = ns.Score:Value("|Hitem:7719|h")
check(pts > 0, "leggings score something: " .. string.format("%.1f", pts))
local w = ns.WEIGHTS.ROGUE
check(math.abs(pts - (9 * w.agility + 4 * w.stamina)) < 0.01,
    "and score exactly agility and stamina by weight")

-- The same piece is worth less to someone who values agility less.
CLASS = "WARRIOR"
local warriorPts = ns.Score:Value("|Hitem:7719|h")
CLASS = "ROGUE"
check(warriorPts < pts, "a warrior values the same leggings lower: "
    .. string.format("%.1f vs %.1f", warriorPts, pts))

-- Judged against what is already worn, not in a vacuum.
S.EQUIPPED = { [7] = "|Hitem:7719|h" }
check(ns.Score:EquippedValue(7) > 0, "what you are wearing is read from the character")

-- The window.
ns.UI:Toggle()
local panel = _G.WicksGearPanel
check(panel ~= nil and panel:IsShown(), "the window opens")
check(ns.UI.tabs.upgrades ~= nil and ns.UI.tabs.browse ~= nil, "with both tabs")
ns.UI:Select("browse")
check(ns.UI.panes.browse:IsShown() and not ns.UI.panes.upgrades:IsShown(), "browse shows on its own")
local rows = 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then rows = rows + 1 end end
check(rows >= 10, "a row per dungeon, got " .. rows)

-- A dungeon opens to show what is in it.
local before = rows
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
rows = 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then rows = rows + 1 end end
check(rows > before, "opening a dungeon lists its loot: " .. before .. " to " .. rows)

-- Gear the class cannot use has to be obvious at a glance. Muted grey
-- against off-white reads as the same colour at this size, so it is
-- darkened and the icon is desaturated too.
-- Both of these really do drop in the Deadmines, so they appear in the
-- list; the stub decides what they are made of.
S.ITEMS[10399] = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 2 }  -- leather
S.ITEMS[5202]  = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3 }  -- call it mail
ns.UI:FillBrowse()
local dim, lit = 0, 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() and r.itemID then
        if r.dimmed then dim = dim + 1 else lit = lit + 1 end
    end
end
check(lit > 0, "usable items stay lit, " .. lit .. " of them")
check(dim > 0, "and the ones a rogue cannot wear are dimmed, " .. dim .. " of them")

-- ---- the paperdoll ----------------------------------------------
-- Wearing leggings worth 4 agility, trying on a pair worth 9. The
-- interesting number is the difference, and what the difference does to
-- the character sheet.
S.EQUIPPED = { [7] = "|Hitem:old|h" }
S.LINK_TO_ID["|Hitem:old|h"] = 8888
S.ITEMS[8888] = { equipLoc = "INVTYPE_LEGS", classID = 4, subClassID = 2,
                  stats = { ITEM_MOD_AGILITY_SHORT = 4 } }

-- Right-clicking a row can ask to try something on before the Compare
-- tab has ever been drawn, so there is no paperdoll yet to put it in.
-- That is the order a real person hits first and it used to throw.
check(ns.Doll.pane == nil, "nothing is built until the tab is needed")
local okEarly, errEarly = pcall(function() return ns.Doll:TryOn(7719) end)
check(okEarly, "trying a piece on before the tab exists does not error: " .. tostring(errEarly))
check(ns.Doll.pane ~= nil, "it builds the paperdoll on demand instead")
ns.Doll:ClearAll()

ns.UI:Select("compare")
check(ns.Doll.pane ~= nil, "the paperdoll builds")
local slots = 0
for _ in pairs(ns.Doll.slots) do slots = slots + 1 end
check(slots == 15, "a button per equipment slot, got " .. slots)

check(ns.Doll:TryOn(7719), "a piece can be tried on")
check(ns.Doll.trying[7] ~= nil, "it lands in the slot it belongs to")
check(ns.Doll.slots[7].mark:IsShown(), "and the slot is marked as borrowed")

local d = ns.Doll:Deltas()
check(d.agi == 5, "agility delta is the difference, not the whole item: " .. tostring(d.agi))
check(d.sta == 4, "and stamina counts too, the old pair had none: " .. tostring(d.sta))

-- Derived numbers come from the client's own conversions rather than
-- formulas of ours, so they have to move with the stats.
ns.Doll:RefreshStats()
local text = ns.Doll.derived:GetText() or ""
check(text:find("Attack power") ~= nil, "attack power is derived: " .. text:gsub("\n", " | "):sub(1, 60))
check(text:find("Health") ~= nil, "and health, from the client's stamina conversion")
check(text:find("%+5") ~= nil or text:find("Attack power %+5") ~= nil,
    "five agility is five attack power at this stub's rate")

-- A class that cannot use it is refused rather than silently accepted.
check(not ns.Doll:TryOn(6463), "mail is refused for a rogue")

ns.Doll:Clear(7)
check(ns.Doll.trying[7] == nil, "right-click puts it back")
check(next(ns.Doll:Deltas()) == nil, "and the deltas go with it")

-- Item data arrives from the server a few at a time. Whatever had not
-- turned up when the list was drawn used to sit there reading "item
-- 9454" until you closed and reopened the window.
ns.UI:Select("browse")
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
local before
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() and r.itemID == 5202 then before = r.left:GetText() end
end
check(before ~= nil, "the row is on screen")

ns.UI.redrawQueued = nil
S.fire("ITEM_DATA_LOAD_RESULT", 5202, true)
check(ns.UI.redrawQueued == nil, "a late arrival triggers a redraw rather than being ignored")

-- Arrivals come in floods, so the redraw is coalesced behind a flag.
-- The stub runs timers the instant they are set, so the coalescing
-- itself cannot be observed here; what can is that the flag stops a
-- second redraw being queued while one is already waiting.
local drew = 0
local realFill = ns.UI.FillBrowse
ns.UI.FillBrowse = function(self) drew = drew + 1 return realFill(self) end
ns.UI.redrawQueued = true          -- pretend one is already pending
for i = 1, 20 do S.fire("ITEM_DATA_LOAD_RESULT", 5202, true) end
ns.UI.FillBrowse = realFill
check(drew == 0, "arrivals are ignored while a redraw is already queued, got " .. drew)
ns.UI.redrawQueued = nil

S.CHAT = {}
SlashCmdList.WICKSGEAR("browse")
check(true, "/wgear browse does not error")

local miss = S.missingReport()
if #miss > 0 then
    io.write("== missing globals reached during the run ==\n  ", table.concat(miss, " "), "\n")
end
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, failures))
return failures

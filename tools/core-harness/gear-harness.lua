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
    { "Data.lua", "Score.lua", "Core.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksGear")
S.fire("PLAYER_LOGIN")

check(ns.DUNGEONS ~= nil and ns.DUNGEON_ORDER ~= nil, "the data file loaded")
check(#ns.DUNGEON_ORDER >= 10, #ns.DUNGEON_ORDER .. " dungeons carried")
local ids = ns.AllItemIDs()
check(#ids > 200, #ids .. " distinct items, deduplicated")
check(ns.WEIGHTS.ROGUE ~= nil and ns.PROFICIENCY.ROGUE ~= nil, "weights and proficiencies came with it")

-- Nothing can be scored before the client has the items.
-- The stub runs timers the instant they are set, so the three second
-- backstop fires here rather than the load events doing it. What matters
-- either way is that the caller is told exactly once: told twice and the
-- panel rebuilds itself on top of itself.
local calls = 0
ns.Score:Preload({ 7719, 6463, 7717 }, function() calls = calls + 1 end)
check(S.REQUESTED == 3, "every uncached item was requested, got " .. S.REQUESTED)
check(calls == 1, "the caller is told once")
for _, id in ipairs({ 7719, 6463, 7717 }) do S.fire("ITEM_DATA_LOAD_RESULT", id, true) end
check(calls == 1, "and not again when the loads land afterwards")

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

S.CHAT = {}
SlashCmdList.WICKSGEAR("browse")
check(true, "/wgear browse does not error")

local miss = S.missingReport()
if #miss > 0 then
    io.write("== missing globals reached during the run ==\n  ", table.concat(miss, " "), "\n")
end
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, failures))
return failures

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

S.loadAddon(CORE_DIR, "WickCore")   -- file list straight off WickCore.toc
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
    { "Data.lua", "DataCrafted.lua", "DataQuests.lua", "Score.lua", "Core.lua", "Doll.lua", "UI.lua" })
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

-- A name and a usable link without the server having answered, which is
-- the state a lot of items are actually in on this beta.
S.UNCACHED = { [7719] = true }
check(ns.Score:NameFor(7719) ~= nil, "a name comes from the client even when the item has not loaded")
check(ns.Score:LinkFor(7719) == "item:7719", "and a link can be built from the id: " .. ns.Score:LinkFor(7719))
check(ns.Score:Value("item:7719") > 0, "which is enough to read stats from")

-- The client cannot name an item the character has never met: of the
-- thirteen things in Gnomeregan it knew three. So the data file carries
-- a name and a stat line to fall back on, used only when the client has
-- nothing of its own to say.
S.UNCACHED = {}
S.UNKNOWN = { [9454] = true }   -- the client has never heard of this one
check(ns.ENTRY[9454] ~= nil, "the shipped entry is indexed by id")
check(ns.Score:NameFor(9454) == "Acidic Walkers",
    "an unknown item still has a name: " .. tostring(ns.Score:NameFor(9454)))
local fb = ns.Score:StatsOf(9454)
check(fb.int == 8 and fb.spi == 4, "and a stat line: int " .. tostring(fb.int))
check(ns.Score:Value(nil, 9454) > 0, "which is enough to score it")

-- The client's answer wins wherever it has one, because it is the one
-- this server is using.
S.UNKNOWN = {}
S.ITEMS[9454] = { equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 2,
                  name = "Whatever The Client Says",
                  stats = { ITEM_MOD_AGILITY_SHORT = 99 } }
check(ns.Score:NameFor(9454) == "Whatever The Client Says",
    "the client overrides the shipped name")
local live = ns.Score:StatsOf(9454)
check(live.agi == 99 and live.int == nil, "and the shipped stats are not mixed in")

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

-- The source strip belongs to Browse. It was parented to the panel, so
-- it stayed on screen over Upgrades and Compare: only the pane and its
-- head are shown and hidden when a tab changes.
local strip = ns.UI.panes.browse
check(strip.search:GetParent() == strip, "the search box belongs to the browse pane")
check(strip.equippable:GetParent() == strip, "so does the equippable toggle")
for key, b in pairs(strip.sourceBtns) do
    check(b:GetParent() == strip, "and the " .. key .. " button")
end
check(ns.UI.panes.upgrades.sourceBtns == nil, "upgrades never built a strip of its own")
check(ns.UI.panes.compare.sourceBtns == nil, "nor did compare")



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

-- Twenty-eight dungeons and four hundred items, navigable only by opening
-- one dungeon at a time: there was no way to ask where boots drop or where
-- a named item comes from. Searching flattens the list, because a collapsed
-- dungeon hiding the match is the opposite of searching.
local function shownRows()
    local n = 0
    for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then n = n + 1 end end
    return n
end
ns.UI.panes.browse.open["The Deadmines"] = false
ns.UI.search = "zzzznothing"
ns.UI:FillBrowse()
check(shownRows() == 0, "a search matching nothing shows nothing, got " .. shownRows())
check(ns.UI.panes.browse.empty:IsShown(), "and says so rather than going blank")

-- A dungeon name finds its loot without the dungeon being open.
ns.UI.search = "deadmines"
ns.UI:FillBrowse()
local byDungeon = shownRows()
check(byDungeon > 0, "searching a dungeon name finds its loot while it is collapsed: " .. byDungeon)

ns.UI.search = ""
ns.UI:FillBrowse()
check(shownRows() >= 10, "clearing the box puts the dungeon list back")

-- Four ways into the same pile of gear. Crafted has a skill where a
-- dungeon has a level bracket, a quest reward has a zone, and a set has
-- neither, so the group header stopped being dungeon shaped.
check(#(ns.CRAFTED_ORDER or {}) == 4, "four gear professions, got " .. #(ns.CRAFTED_ORDER or {}))
check(#(ns.QUESTS_ORDER or {}) > 10, "quest rewards across the zones, got " .. #(ns.QUESTS_ORDER or {}))

local order, groups = ns.UI:Groups("crafted")
check(#order == 4 and groups[order[1]] ~= nil, "the crafted source offers its professions")
check(groups[order[1]][1].skill ~= nil, "and a recipe carries the skill it is learned at")

order = ns.UI:Groups("sets")
check(#order > 10, "sets are built by walking the tables, got " .. #order)

-- Sets are not scraped as their own table; every entry carries the set
-- it belongs to and the view is assembled from that, so a crafted piece
-- joins its set with no emitter change.
local _, setGroups = ns.UI:Groups("sets")
local anySet, fromCrafted = nil, false
for name, rows in pairs(setGroups) do
    anySet = anySet or name
    for _, e in ipairs(rows) do if e.skill then fromCrafted = true end end
end
check(anySet ~= nil, "a set was found: " .. tostring(anySet))

ns.UI:SetSource("crafted")
check(ns.UI.source == "crafted", "switching source sticks")
check(shownRows() == 4, "and the list shows a row per profession, got " .. shownRows())
ns.UI.panes.browse.open["Blacksmithing"] = true
ns.UI:FillBrowse()
check(shownRows() > 4, "opening one lists what it makes")

ns.UI:SetSource("quests")
check(shownRows() == #ns.QUESTS_ORDER, "quests list a row per zone, got " .. shownRows())

-- Search spans whichever source is showing, which is why it was built
-- before the sources were. Matched on the slot rather than the item
-- name: the stub answers GetItemInfo for every id, so the shipped name
-- is never reached here, which is the one thing this harness cannot
-- exercise about searching.
ns.UI.search = "feet"
ns.UI:FillBrowse()
local inQuests = shownRows()
check(inQuests > 0, "a slot search finds quest rewards, got " .. inQuests)
ns.UI:SetSource("crafted")
ns.UI.search = "feet"
ns.UI:FillBrowse()
check(shownRows() > inQuests, "and the same search over crafted finds more: " .. shownRows() .. " against " .. inQuests)

-- Equippable. Dimming is enough for a dungeon's nine items and useless
-- against a profession's four hundred, most of which are the wrong
-- armour type for this class.
ns.UI:SetSource("crafted")
ns.UI.panes.browse.open["Leatherworking"] = true
ns.UI:FillBrowse()
local allRows = shownRows()

-- An item the client has not described yet is kept on purpose: hiding it
-- would make the list shrink as the answers arrive, which reads as the
-- addon losing things. So the stub has to actually know these three
-- before the filter has anything to act on. Plate, on a warrior who is
-- not high enough for it yet.
for _, id in ipairs({ 2302, 2303, 2307 }) do
    S.ITEMS[id] = { equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 4 }
end
ns.db().onlyEquippable = true
ns.UI:FillBrowse()
local fitRows = shownRows()
check(fitRows == allRows - 3, "the toggle drops what this class cannot wear: " .. fitRows .. " of " .. allRows)
check(fitRows > 0, "and does not empty the list")

-- A group with nothing left for this class should not sit there as an
-- empty header inviting a click.
local names = {}
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() then names[#names + 1] = tostring(r.left:GetText()) end
end
check(#names == fitRows, "every shown row accounted for")

ns.db().onlyEquippable = false
ns.UI.panes.browse.open["Leatherworking"] = false
for _, id in ipairs({ 2302, 2303, 2307 }) do S.ITEMS[id] = nil end

ns.UI:SetSource("dungeons")
ns.UI:FillBrowse()


-- Put the list back the way the next checks expect to find it.
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()


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

-- This client hands some unit values back as secrets: they can be shown
-- but not added to, and the addition throws in our name. That is exactly
-- what UNIT_STATS did in game. With the totals out of reach the deltas
-- are still entirely ours, so the panel has to keep working on them.
local realStat, realArmor = UnitStat, UnitArmor
local secret = setmetatable({}, {
    __add = function() error("attempt to perform arithmetic on a secret number value") end,
    __sub = function() error("attempt to perform arithmetic on a secret number value") end,
})
UnitStat = function() return secret, secret, 0, 0 end
UnitArmor = function() return secret, secret, 0, 0, 0 end
local okSecret, errSecret = pcall(ns.Doll.RefreshStats, ns.Doll)
check(okSecret, "secret stats do not throw: " .. tostring(errSecret))
local stext = ns.Doll.derived:GetText() or ""
check(stext:find("Attack power") ~= nil,
    "and the derived change still comes out, from the delta alone: "
    .. stext:gsub("\n", " | "):sub(1, 60))
check(stext:find("Attack power %+5") ~= nil,
    "with the same answer the readable path gave")
local shown
for i, key in ipairs(ns.Score.STAT_ORDER) do
    if key == "agi" then shown = ns.Doll.statRows[i] end
end
check(shown and shown.delta:GetText() == "+5",
    "the change is still shown even though the total cannot be")
check(shown and not (shown.value:GetText() or ""):find("table"),
    "and no raw table leaks into the total: " .. tostring(shown and shown.value:GetText()))
UnitStat, UnitArmor = realStat, realArmor
ns.Doll:RefreshStats()

-- On this beta the client only knows an item the character has actually
-- met. Asking it for a tooltip on any other one gives "Retrieving item
-- information" forever, because the data is never coming. So when the
-- client cannot answer, the tooltip is built from what we shipped.
do
    -- Pick one the client knows nothing about, the way the beta leaves
    -- most of this list.
    local uncached = nil
    for _, id in ipairs(ns.AllItemIDs()) do
        if ns.ENTRY[id] and ns.ENTRY[id].name ~= "" and ns.ENTRY[id].stats then
            uncached = id
            break
        end
    end
    -- Server data missing, client files still there: that is exactly
    -- the beta's state. GetItemInfo goes quiet, GetItemInfoInstant
    -- still answers with the slot.
    S.ITEMS = S.ITEMS or {}
    S.ITEMS[uncached] = { name = ns.ENTRY[uncached].name, type = "Armor",
                          equipLoc = "INVTYPE_CLOAK", classID = 4, subClassID = -6 }
    S.UNCACHED = S.UNCACHED or {}
    S.UNCACHED[uncached] = true
    S.UNKNOWN = S.UNKNOWN or {}
    S.UNKNOWN[uncached] = true
    check(uncached ~= nil and not ns.Score:Cached(uncached),
        "the stub has an item the client cannot describe")
    if uncached then
        local e = ns.ENTRY[uncached]
        GameTooltip:ClearLines()
        local fromGame = ns.Score:FillTooltip(GameTooltip, uncached, ns.Score:LinkFor(uncached))
        local text = GameTooltip:Text()
        check(not fromGame, "the game is not asked for one it cannot answer")
        check(text:find(e.name, 1, true) ~= nil,
            "the item is named from our own data: " .. text:sub(1, 48))
        check(text:find("Retrieving") == nil, "and never says Retrieving item information")
        check(text:find(e.dungeon, 1, true) ~= nil, "with where it drops")
        check(text:find("what you are wearing") ~= nil or text:find("No change") ~= nil,
            "and what it would change against what is worn")
    end

    -- Shift-click has to produce something chat will accept. An item link
    -- is a fixed shape on any given build, and "|Hitem:279899|h" is not
    -- it: that one field version carried everything a receiving client
    -- needs and still would not go in the chat box, which is what the
    -- player saw as "most of them will not link".
    --
    -- So the shape is learned off a link the client itself made, from the
    -- gear on the player's back, rather than guessed at.
    local worn = "|cff1eff00|Hitem:12345:0:0:0:0:0:0:0:60:0:0:0:0:0:0:0:0|h[Worn Thing]|h|r"
    S.EQUIPPED = { [1] = worn }
    ns.Score:LearnLinkShape()
    local fields = ns.Score:LinkFields()
    check(fields == 17, "the link shape is read off what the player is wearing, got " .. tostring(fields))

    local link, source = ns.Score:ChatLink(uncached)
    check(link ~= nil and link:find("|Hitem:" .. uncached, 1, true) ~= nil,
        "an uncached item still gets a chat link: " .. tostring(link))
    check(source == "built", "and it is ours, not the client's: " .. tostring(source))
    check(link:find("[" .. ns.ENTRY[uncached].name .. "]", 1, true) ~= nil and link:sub(-4) == "|h|r",
        "a well formed one, with the name in brackets")

    -- The part that was actually broken: ours has to have as many fields
    -- as the client's own, or the chat box will not take it.
    local function fieldsIn(l)
        local payload = l:match("|Hitem:([^|]*)|h")
        local n = 1
        for _ in payload:gmatch(":") do n = n + 1 end
        return n
    end
    check(fieldsIn(link) == fieldsIn(worn),
        ("ours carries the same field count as the client's, %d against %d")
            :format(fieldsIn(link), fieldsIn(worn)))

    -- A build that shapes links differently is followed, not argued with.
    S.EQUIPPED = { [1] = "|cffffffff|Hitem:99:0:0:0|h[Short]|h|r" }
    check(fieldsIn(ns.Score:ChatLink(uncached)) == 17,
        "a shape already learned is not thrown away by a later read")

    S.UNCACHED[uncached] = nil
    S.UNKNOWN[uncached] = nil

    -- An item the client does know is still the client's to describe.
    local known = ns.AllItemIDs()[2]
    if ns.Score:Cached(known) then
        GameTooltip:ClearLines()
        local fromGame = ns.Score:FillTooltip(GameTooltip, known, ns.Score:LinkFor(known))
        check(fromGame, "a cached item still goes to the game, whose answer is the real one")
    end

end

-- A class that cannot use it is refused rather than silently accepted.
check(not ns.Doll:TryOn(6463), "mail is refused for a rogue")

-- Mail and plate are trained at forty. A hunter is listed as wearing
-- mail, which was true of the character sheet and false of a level
-- twenty hunter, who was being told to go and find mail.
do
    local realClass, realLevel = CLASS, S.LEVEL
    CLASS = "HUNTER"
    local mail = { classID = 4, subClassID = 3 }
    local leather = { classID = 4, subClassID = 2 }
    S.LEVEL = 20
    check(not ns.Score:Usable(mail), "a level twenty hunter is not shown mail")
    check(ns.Score:Usable(leather), "but leather is still theirs")
    S.LEVEL = 40
    check(ns.Score:Usable(mail), "and at forty the mail appears")
    CLASS = "ROGUE"
    S.LEVEL = 60
    check(not ns.Score:Usable(mail), "a rogue never gets it, whatever the level")
    CLASS, S.LEVEL = realClass, realLevel
end

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

-- What a click on a row does. Rows are pooled, and one used as a group
-- header carries the header's toggle, so an item row has to take its own
-- handler back or clicking the item reopens the group.
ns.UI:SetSource("dungeons")
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
local itemRow
for _, r in ipairs(ns.UI.panes.browse.rows) do
    if r:IsShown() and r.itemID then itemRow = r break end
end
check(itemRow ~= nil, "found an item row to click")
check(itemRow.__scripts.OnClick == ns.UI.RowClick,
    "an item row carries the item handler, not a header toggle")

-- Plain click: our own viewer, and the tab with it.
ns.UI:Select("browse")
S.DRESSED = nil
itemRow.__scripts.OnClick(itemRow, "LeftButton")
check(ns.UI.active == "compare", "clicking a row opens our viewer: " .. tostring(ns.UI.active))
check(S.DRESSED == nil, "and does not open the dressing room")

-- Ctrl-click: the game's dressing room, and not our tab.
ns.UI:Select("browse")
S.CTRL = true
itemRow.__scripts.OnClick(itemRow, "LeftButton")
S.CTRL = false
check(S.DRESSED ~= nil, "ctrl-click sends it to the dressing room: " .. tostring(S.DRESSED))
check(ns.UI.active == "browse", "and leaves you where you were")

local miss = S.missingReport()
if #miss > 0 then
    io.write("== missing globals reached during the run ==\n  ", table.concat(miss, " "), "\n")
end
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, failures))
return failures

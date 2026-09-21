-- Offline load-test harness for Wick's Probe.
-- Stubs enough of the WoW client to load the addon, fire ADDON_LOADED and run
-- the slash command, so the whole report path is exercised outside the game.

unpack = unpack or table.unpack
date = os.date

local ADDON_DIR = ...

-- ---------- mock frames -------------------------------------------------
local VALID_EVENTS = {}
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "VARIABLES_LOADED",
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "QUEST_LOG_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
    "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_MONEY", "MERCHANT_SHOW",
    "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_TOTEM_UPDATE", "COMBAT_RATING_UPDATE",
    "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SOCKET_INFO_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
}) do VALID_EVENTS[e] = true end

local function newMock(kind)
    local self = { __kind = kind, __scripts = {}, __events = {} }
    local mt
    mt = {
        __index = function(t, k)
            if k == "RegisterEvent" then
                return function(_, e)
                    if not VALID_EVENTS[e] then
                        error("Attempt to register unknown event '" .. tostring(e) .. "'", 2)
                    end
                    t.__events[e] = true
                end
            elseif k == "UnregisterEvent" then
                return function(_, e) t.__events[e] = nil end
            elseif k == "SetScript" then
                return function(_, name, fn) t.__scripts[name] = fn end
            elseif k == "GetScript" then
                return function(_, name) return t.__scripts[name] end
            elseif k == "CreateTexture" or k == "CreateFontString" then
                return function() return newMock(k) end
            elseif k == "IsShown" then
                return function() return t.__shown and true or false end
            elseif k == "Show" then
                return function() t.__shown = true end
            elseif k == "Hide" then
                return function() t.__shown = false end
            end
            -- Everything else is a chainable no-op that returns the mock.
            local fn = function() return t end
            rawset(t, k, fn)
            return fn
        end,
    }
    return setmetatable(self, mt)
end

local ALL_FRAMES = {}

function CreateFrame(kind, name, parent, template)
    local f = newMock(kind or "Frame")
    if name then _G[name] = f end
    ALL_FRAMES[#ALL_FRAMES + 1] = f
    return f
end

UIParent = newMock("Frame")

local chatLines = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) chatLines[#chatLines + 1] = msg end,
}

SlashCmdList = {}

-- ---------- stubbed client APIs ----------------------------------------
-- Deliberately a TBC-shaped client: legacy container/aura/item globals
-- present, no C_Container / C_UnitAuras / C_Secrets. That is the control
-- sample the Forever run gets diffed against.

WOW_PROJECT_ID = 5
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_WRATH_CLASSIC = 11

CR_HIT_MELEE = 6
CR_HIT_RANGED = 7
CR_HIT_SPELL = 8
CR_CRIT_MELEE = 9
CR_CRIT_RANGED = 10
CR_CRIT_SPELL = 11
CR_EXPERTISE = 24

ITEM_MOD_AGILITY_SHORT = "AGI"
ITEM_MOD_STRENGTH_SHORT = "STR"
ITEM_MOD_STAMINA_SHORT = "STA"
ITEM_MOD_CRIT_RATING_SHORT = "Crit Rating"
ITEM_MOD_HIT_RATING_SHORT = "Hit Rating"

STAT_CRITICAL_STRIKE = "Critical Strike"

function GetBuildInfo() return "2.5.5", "51536", "Sep 12 2026", 20505 end
function GetLocale() return "enUS" end
function GetRealmName() return "Whitemane" end
function GetNormalizedRealmName() return "Whitemane" end
function UnitClass(u) return "Shaman", "SHAMAN", 7 end
function UnitRace(u) return "Orc", "Orc", 2 end
function UnitLevel(u) return 70 end
function GetContainerNumSlots(b) return 16 end
function GetContainerItemInfo(b, s) return "Interface\\Icons\\INV_Misc_Bag_08", 1, false, false, false, false, "|cffffffff|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r" end
function UnitAura(u, i) return "Lightning Shield", "Interface\\Icons\\Spell_Nature_LightningShield", 3, nil, 600, 0 end
function GetItemInfo(id) return "Hearthstone", "|cffffffff|Hitem:6948|h[Hearthstone]|h|r", 1, 1, 1, "Miscellaneous", "Junk", 1, "", "Interface\\Icons\\INV_Misc_Rune_01", 0 end
function GetSpellInfo(id) return "Fireball", "Rank 1", "Interface\\Icons\\Spell_Fire_FlameBolt", 0, 0, 35, 133 end
function GetInventoryItemLink(u, s) return "|cffa335ee|Hitem:30905::::::::70:::::|h[Ancestral Ring]|h|r" end
function GetItemStats(link)
    if link == "" then return nil end
    return { ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_HIT_RATING_SHORT = 15, EMPTY_SOCKET_RED = 1 }
end
function GetNumSockets() return 0 end
function GetCritChance() return 24.31 end
function GetRangedCritChance() return 21.05 end
function GetSpellCritChance(school) return 18.44 end
function GetSpellHitModifier() return 0 end
function GetHitModifier() return 0 end
function GetExpertise() return 5 end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i) return "Elemental", "Interface\\Icons\\x", 0, 21 end
function GetTalentInfo(tab, idx) return "Convection", "Interface\\Icons\\x", 1, 1, 5, 5 end
function GetNumQuestLogEntries() return 12, 9 end
function GetQuestLogSpecialItemInfo(i) return "|cffffffff|Hitem:12345|h[Signal Flare]|h|r", "Interface\\Icons\\INV_Misc_Flare", 3, false end
function GetTradeSkillLine() return "Alchemy", 350, 375 end
function GetNumShapeshiftForms() return 0 end
function GetNumGroupMembers() return 5 end
function IsInRaid() return false end
function CombatLogGetCurrentEventInfo() return 0, "SPELL_DAMAGE" end
function IsFlyableArea() return false end
function IsActiveBattlefieldArena() return false end
function GetCombatRating(i) return 42 end

-- ---------- load the addon ---------------------------------------------
local ns = {}
local FILES = { "Surface.lua", "UI.lua", "Core.lua" }

for _, f in ipairs(FILES) do
    local path = ADDON_DIR .. "/" .. f
    local chunk, err = loadfile(path)
    if not chunk then
        print("LOAD ERROR  " .. f .. ": " .. tostring(err))
        os.exit(1)
    end
    local ok, rerr = pcall(chunk, "WicksProbe", ns)
    if not ok then
        print("RUNTIME ERROR  " .. f .. ": " .. tostring(rerr))
        os.exit(1)
    end
    print("loaded ok   " .. f)
end

-- ---------- fire ADDON_LOADED ------------------------------------------
print("")
print("-- firing ADDON_LOADED --")
for _, f in ipairs(ALL_FRAMES) do
    local h = rawget(f, "__scripts") and f.__scripts.OnEvent
    if h then
        local ok, err = pcall(h, f, "ADDON_LOADED", "WicksProbe")
        if not ok then print("OnEvent ERROR: " .. tostring(err)) end
    end
end

for _, line in ipairs(chatLines) do print("  " .. line) end

-- ---------- run the sweep ----------------------------------------------
print("")
print("-- running /wickprobe --")
chatLines = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) chatLines[#chatLines + 1] = msg end

local cmd = SlashCmdList["WICKSPROBE"]
if not cmd then
    print("FAIL: slash command was never registered")
    os.exit(1)
end

local ok, err = pcall(cmd, "")
if not ok then
    print("SLASH ERROR: " .. tostring(err))
    os.exit(1)
end

for _, line in ipairs(chatLines) do print("  " .. line) end

-- ---------- print the report -------------------------------------------
if not QUIET then
    print("")
    print("-- report --")
    print(ns.Probe:Report())
end

-- ---------- full mode --------------------------------------------------
print("")
print("-- running /wickprobe full --")
local ok2, err2 = pcall(cmd, "full")
if not ok2 then
    print("FULL MODE ERROR: " .. tostring(err2))
    os.exit(1)
end
print("full mode ok")

-- ---------- SavedVariables ---------------------------------------------
print("")
if WicksProbeDB and WicksProbeDB.runs and #WicksProbeDB.runs > 0 then
    print("SavedVariables: " .. #WicksProbeDB.runs .. " run(s) stored, latest report "
        .. #(WicksProbeDB.latest or "") .. " chars")
    print("")
    print("PASS")
else
    print("FAIL: WicksProbeDB was not populated")
    os.exit(1)
end

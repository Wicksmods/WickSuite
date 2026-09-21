-- Stub WoW client for offline load tests. Shared by the WickCore harness and
-- the per-product harnesses.
--
--   local S = assert(loadfile("stubclient.lua"))("modern" | "legacy")
--
-- Returns a table with fire(event, ...), SECRET, SENT, CHAT, MISSING and the
-- mode flag. World state is global so tests can flip it: COMBAT, LOGGED,
-- IN_GROUP, BANK_OPEN.

unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan
date = os.date
time = os.time
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = strsplit or function(sep, s) local out = {} for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end return unpack(out) end
strtrim = strtrim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format

local MODE = ... or "modern"
local MODERN = MODE == "modern"
local S = { mode = MODE, modern = MODERN, SENT = {}, CHAT = {}, MISSING = {} }

COMBAT = false
LOGGED = true
IN_GROUP = false
BANK_OPEN = false
OPENED = nil

S.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local SECRET = S.SECRET

-- Any read of an undefined global is recorded, so a harness can print what the
-- code under test reached for that the stub does not provide.
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" then S.MISSING[k] = (S.MISSING[k] or 0) + 1 end
    return nil
end })

-- ---------- mock frames -------------------------------------------------
-- Real clients accept nearly any event name; only a few are flavor-specific.
-- Registering one of these raises, which is what WickCore's pcall fallbacks
-- are tested against.
local INVALID_EVENTS = MODERN
    and { LEARNED_SPELL_IN_TAB = true, TRADE_SKILL_UPDATE = true }
    or  { ADDON_RESTRICTION_STATE_CHANGED = true, BANK_TABS_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
          ACTIVE_COMBAT_CONFIG_CHANGED = true, CURRENCY_DISPLAY_UPDATE = true }
local function eventValid(e) return type(e) == "string" and e:match("^[A-Z][A-Z0-9_]+$") ~= nil and not INVALID_EVENTS[e] end

local ALL_FRAMES = {}
S.frames = ALL_FRAMES

local function newMock(kind, name)
    local self = { __kind = kind, __name = name, __scripts = {}, __events = {}, __w = 100, __h = 100,
                   __shown = false, __text = "", __children = {} }
    local mt = {}
    mt.__index = function(t, k)
        if k == "RegisterEvent" then
            return function(_, e)
                if not eventValid(e) then error("Attempt to register unknown event '" .. tostring(e) .. "'", 2) end
                t.__events[e] = true
            end
        elseif k == "UnregisterEvent" then return function(_, e) t.__events[e] = nil end
        elseif k == "UnregisterAllEvents" then return function() t.__events = {} end
        elseif k == "SetScript" then return function(_, n, fn) t.__scripts[n] = fn end
        elseif k == "HookScript" then return function(_, n, fn)
                local prev = t.__scripts[n]
                t.__scripts[n] = function(...) if prev then prev(...) end fn(...) end
            end
        elseif k == "GetScript" then return function(_, n) return t.__scripts[n] end
        elseif k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then return function() return newMock(k) end
        elseif k == "IsShown" or k == "IsVisible" then return function() return t.__shown end
        elseif k == "Show" then return function() t.__shown = true; if t.__scripts.OnShow then t.__scripts.OnShow(t) end end
        elseif k == "Hide" then return function() local was = t.__shown; t.__shown = false; if was and t.__scripts.OnHide then t.__scripts.OnHide(t) end end
        elseif k == "SetShown" then return function(_, v) if v then t:Show() else t:Hide() end end
        elseif k == "SetSize" then return function(_, w, h) t.__w, t.__h = w, h end
        elseif k == "SetWidth" then return function(_, w) t.__w = w end
        elseif k == "SetHeight" then return function(_, h) t.__h = h end
        elseif k == "GetWidth" then return function() return t.__w end
        elseif k == "GetHeight" then return function() return t.__h end
        elseif k == "GetSize" then return function() return t.__w, t.__h end
        elseif k == "GetCenter" then return function() return 0, 0 end
        elseif k == "GetLeft" or k == "GetBottom" then return function() return 0 end
        elseif k == "GetRight" or k == "GetTop" then return function() return 100 end
        elseif k == "GetEffectiveScale" or k == "GetScale" then return function() return 1 end
        elseif k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 12, -34 end
        elseif k == "SetPoint" then return function(_, point, rel, ...)
                -- Retail rule: a protected frame (secure templates) may anchor
                -- only to frames, never to a texture or font string.
                if MODERN and t.__template and t.__template:find("^Secure") and type(rel) == "table"
                   and (rel.__kind == "Texture" or rel.__kind == "FontString" or rel.__kind == "CreateTexture" or rel.__kind == "CreateFontString") then
                    error("Action[SetPoint] failed because[Cannot anchor protected frames to regions]: attempted from: Button:SetPoint.", 2)
                end
                t.__points = t.__points or {}
                t.__points[#t.__points + 1] = { point, rel, ... }
            end
        elseif k == "GetNumPoints" then return function() return 1 end
        elseif k == "SetText" then return function(_, s, r, g, b, a, wrap)
                -- Retail tooltips: SetText(text [, r, g, b, a, wrap]) or a color
                -- object; argument five must be a number. TBC accepted the wrap
                -- flag there because alpha was optional.
                if MODERN and t.__kind == "GameTooltip" and a ~= nil and type(a) ~= "number" then
                    error("bad argument #5 to 'SetText' (outside of expected range -3.402823e+38 to 3.402823e+38 - Usage: self:SetText(text [, color, alpha, wrap]))", 2)
                end
                t.__text = s
            end
        elseif k == "GetText" then return function() return t.__text end
        elseif k == "GetStringWidth" then return function() return #tostring(t.__text) * 6 end
        -- Height has to account for wrapping, because that is the part
        -- layout code gets wrong: a note that wraps to three lines but
        -- reports one line of height lands under whatever follows it.
        elseif k == "GetStringHeight" then
            return function()
                local txt = tostring(t.__text or "")
                local perLine = math.max(1, math.floor((t.__w or 300) / 5.5))
                local lines = 0
                for chunk in (txt .. "\n"):gmatch("([^\n]*)\n") do
                    lines = lines + math.max(1, math.ceil(#chunk / perLine))
                end
                return math.max(1, lines) * 13
            end
        elseif k == "GetName" then return function() return t.__name end
        elseif k == "GetObjectType" then return function() return t.__kind end
        elseif k == "GetParent" then return function() return t.__parent end
        elseif k == "SetParent" then return function(_, p) t.__parent = p end
        elseif k == "GetItem" then return function() return "Hearthstone", "|Hitem:6948|h[Hearthstone]|h" end
        elseif k == "GetChecked" then return function() return t.__checked end
        elseif k == "SetChecked" then return function(_, v) t.__checked = v end
        elseif k == "IsMouseOver" then return function() return false end
        elseif k == "GetFrameLevel" then return function() return 1 end
        elseif k == "GetFrameStrata" then return function() return "MEDIUM" end
        elseif k == "SetAlpha" then return function(_, a) t.__alpha = a end
        elseif k == "GetAlpha" then return function() return t.__alpha or 1 end
        elseif k == "GetTexture" then return function() return t.__tex end
        elseif k == "SetTexture" then return function(_, v) t.__tex = v end
        elseif k == "SetMaskTexture" then return function(_, v) t.__maskTex = v end
        elseif k == "GetNumLines" then return function() return 1 end
        elseif k == "NumLines" then return function() return 1 end
        elseif k == "GetCursorPosition" then return function() return 0 end
        elseif k == "IsEnabled" then return function() return true end
        elseif k == "SetAttribute" then return function(_, a, v) t.__attr = t.__attr or {}; t.__attr[a] = v end
        elseif k == "GetAttribute" then return function(_, a) return t.__attr and t.__attr[a] end
        elseif k == "SetStatusBarColor" then return function(_, r, g, b, a) t.__color = { r, g, b, a } end
        elseif k == "SetColorTexture" then return function(_, r, g, b, a) t.__color = { r, g, b, a } end
        elseif k == "SetTextColor" then return function(_, r, g, b, a) t.__textColor = { r, g, b, a } end
        -- Slider
        elseif k == "SetMinMaxValues" then return function(_, lo, hi) t.__min, t.__max = lo, hi end
        elseif k == "GetMinMaxValues" then return function() return t.__min or 0, t.__max or 0 end
        elseif k == "SetValue" then return function(_, v) t.__value = v end
        elseif k == "GetValue" then return function() return t.__value or 0 end
        elseif k == "SetValueStep" then return function(_, v) t.__step = v end
        elseif k == "GetValueStep" then return function() return t.__step or 1 end
        -- ScrollFrame
        elseif k == "SetScrollChild" then return function(_, c) t.__scrollChild = c end
        elseif k == "GetScrollChild" then return function() return t.__scrollChild end
        elseif k == "GetVerticalScroll" then return function() return t.__scroll or 0 end
        elseif k == "SetVerticalScroll" then return function(_, v) t.__scroll = v end
        elseif k == "GetVerticalScrollRange" then return function() return 0 end
        end
        if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
        local blocked = rawget(t, "__nokeys")
        if blocked and blocked[k] then return nil end
        -- Unknown Capitalized key: either a method we do not model or a template
        -- child region (b.IconBorder, b.Count). A callable child mock serves
        -- both: b:Foo() calls it, b.Foo:Hide() indexes it.
        local child = newMock(k)
        child.__parent = t
        rawset(t, k, child)
        return child
    end
    mt.__call = function(t) return t end
    return setmetatable(self, mt)
end
S.newMock = newMock

-- Templates whose base type is the retail intrinsic ItemButton. Creating one
-- as a plain "Button" on a modern client keeps the virtual template's own
-- children but drops the intrinsic's regions (icon, Count, IconBorder,
-- NormalTexture), which is exactly what Forever did on first login.
local ITEM_BUTTON_TEMPLATES = { ContainerFrameItemButtonTemplate = true, ItemButtonTemplate = true }
local INTRINSIC_KEYS = { Count = true, IconTexture = true, IconBorder = true, IconOverlay = true,
                         IconOverlay2 = true, NormalTexture = true, PushedTexture = true, Stock = true }
S.ITEM_BUTTONS = {}

function CreateFrame(kind, name, parent, template)
    kind = kind or "Frame"
    if kind == "ItemButton" and not MODERN then
        error("CreateFrame: Unknown frame type 'ItemButton'", 2)
    end
    local f = newMock(kind, name)
    f.__parent = parent
    f.__template = template
    if name then _G[name] = f end
    if MODERN and (kind == "ItemButton" or (template and ITEM_BUTTON_TEMPLATES[template])) then
        if kind == "ItemButton" then
            -- Intrinsic regions, keyed and named the way the XML does it.
            f.icon = newMock("Texture", name and (name .. "IconTexture"))
            f.Count = newMock("FontString", name and (name .. "Count"))
            f.IconBorder = newMock("Texture")
            f.NormalTexture = newMock("Texture", name and (name .. "NormalTexture"))
            if name then
                _G[name .. "IconTexture"] = f.icon
                _G[name .. "Count"] = f.Count
                _G[name .. "NormalTexture"] = f.NormalTexture
            end
        else
            -- Wrong base type: the intrinsic's regions never exist.
            f.__nokeys = INTRINSIC_KEYS
        end
        S.ITEM_BUTTONS[#S.ITEM_BUTTONS + 1] = f
    elseif template and ITEM_BUTTON_TEMPLATES[template] and name then
        -- Legacy client: the old XML template names its regions globally.
        f.__legacyRegions = true
        _G[name .. "IconTexture"] = newMock("Texture", name .. "IconTexture")
        _G[name .. "Count"] = newMock("FontString", name .. "Count")
    end
    ALL_FRAMES[#ALL_FRAMES + 1] = f
    return f
end

function S.fire(event, ...)
    for _, f in ipairs(ALL_FRAMES) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then print("  OnEvent error (" .. event .. "): " .. tostring(err)) end
        end
    end
end

UIParent = newMock("Frame", "UIParent"); UIParent.__w, UIParent.__h = 1600, 900
Minimap = newMock("Minimap", "Minimap"); Minimap.__w = 140
-- Forever ships the compass ring and keeps the zoom controls on the frame.
if MODERN then
    -- Blizzard sizes the container to the ring art, larger than the map.
    MinimapCluster = newMock("Frame", "MinimapCluster")
    MinimapCluster.MinimapContainer = newMock("Frame", "MinimapContainer")
    MinimapCluster.MinimapContainer.__w, MinimapCluster.MinimapContainer.__h = 240, 240
    Minimap.__w, Minimap.__h = 198, 198
    MinimapCompassTexture = newMock("Texture", "MinimapCompassTexture")
    MinimapCompassTextureUnderlay = newMock("Texture", "MinimapCompassTextureUnderlay")
else
    MinimapBorder = newMock("Texture", "MinimapBorder")
end
GameTooltip = newMock("GameTooltip", "GameTooltip")
ItemRefTooltip = newMock("GameTooltip", "ItemRefTooltip")
BankFrame = newMock("Frame", "BankFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) S.CHAT[#S.CHAT + 1] = msg end }
SlashCmdList = {}
ITEM_QUALITY_COLORS = {}
for q = 0, 5 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
StaticPopupDialogs = {}
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
MAX_WATCHED_TOKENS = 3
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
RAID_CLASS_COLORS = {}
do
    local hexes = { WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF",
                    SHAMAN = "0070DD", MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A" }
    for tok, h in pairs(hexes) do
        RAID_CLASS_COLORS[tok] = { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
    end
end

function print(...) local parts = {} for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end S.CHAT[#S.CHAT + 1] = table.concat(parts, " ") end

-- ---------- shared client functions --------------------------------------
function GetLocale() return "enUS" end
function GetRealmName() return "Classic Beta PvP" end
function UnitName() return "Wick" end
CLASS = "SHAMAN"
local CLASS_NAMES = { SHAMAN = { "Shaman", 7 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 } }
function UnitClass() local c = CLASS_NAMES[CLASS] or { CLASS, 0 } return c[1], CLASS, c[2] end
function UnitRace() return "Orc", "Orc", 2 end
function UnitExists(u) return u == "player" or u == "pet" end
function UnitCreatureFamily(unit)
    if unit == "target" then return S.TARGET_FAMILY end
    return S.PET_FAMILY or (CLASS == "HUNTER" and "Wolf" or "Imp")
end
function HasPetSpells()
    local list = S.PET_SPELLS
    if not list then return nil end
    return #list, "PET"
end
function GetSpellBookItemName(i, book)
    if book ~= "pet" then return nil end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    return e and e[1] or nil
end
function IsPassiveSpell(i, book)
    if book ~= "pet" then return false end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    return e ~= nil and e[2] == "passive"
end
-- Unit identity. Not restricted on this client, which is what makes layer
-- fingerprinting possible at all, so the GUID comes back as a plain string.
function UnitGUID(unit)
    if unit == "player" then return "Player-4619-006648E8" end
    return S.GUIDS and S.GUIDS[unit] or nil
end

-- Chat channels.
S.CHANNELS = S.CHANNELS or {}
function GetChannelList()
    local out = {}
    for i, c in ipairs(S.CHANNELS) do
        out[#out + 1] = i
        out[#out + 1] = c
        out[#out + 1] = false
    end
    return unpack(out)
end
function GetChannelName(name)
    for i, c in ipairs(S.CHANNELS) do
        if c:lower() == tostring(name):lower() then return i, c end
    end
    return 0
end
function JoinChannelByName(name)
    S.CHANNELS[#S.CHANNELS + 1] = name
    return true
end

-- Character sheet numbers, and the conversions the sheet itself uses.
-- These take a stat value as an argument, which is what lets a paperdoll
-- ask what a piece would do without anyone reimplementing the formulas.
S.STATS = S.STATS or { 20, 35, 40, 20, 40 }   -- str, agi, sta, int, spi
function UnitStat(_, index)
    local v = S.STATS[index] or 0
    return v, v, 0, 0
end
function UnitArmor() return 0, S.ARMOR or 200, 0, 0, 0 end
function GetAttackPowerForStat(index, value)
    if index == 1 then return value * 2 end   -- strength
    if index == 2 then return value * 1 end   -- agility
    return 0
end
function GetRangedAttackPowerForStat(index, value)
    if index == 2 then return value * 2 end
    return 0
end
function GetCritChanceFromStat(index, value)
    if index == 2 then return value / 330 end
    return 0
end
function GetSpellCritChanceFromStat(index, value) return value / 600 end
function UnitHPPerStamina() return 10 end
STAMINA_BREAK = 20
INTELLECT_BREAK = 20
MANA_PER_INTELLECT = 15
ARMOR_PER_AGILITY = 2

function UnitCreatureType(unit)
    if unit == "target" then return S.TARGET_TYPE or "Beast" end
    return "Beast"
end
function UnitIsDead() return false end
function HasPetUI() return true, CLASS == "HUNTER" end
-- Hunter pet reads. Modern: C_PetInfo. Legacy: the old globals.
local PET = { happiness = 2, damage = 100, rate = 1, loyalty = "Best Friend", total = 12, used = 7, diet = { "Meat", "Fish" } }
S.PET = PET
local function petHappiness() if COMBAT and MODERN then return SECRET, SECRET, SECRET end return PET.happiness, PET.damage, PET.rate end
function UnitPowerType() return 0 end
-- Nameplates. One plate, handed out for whichever unit is asked about,
-- which is enough to check that something attaches to the right anchor.
S.NAMEPLATE = nil
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit ~= "target" or not S.HAS_TARGET then return nil end
        if not S.NAMEPLATE then
            local plate = S.newMock("NamePlate")
            plate.UnitFrame = S.newMock("Frame")
            plate.UnitFrame.HealthBarsContainer = S.newMock("Frame")
            -- Lowercase, so the mock's capitalised-key rule will not
            -- invent it. The real plate has one and it is the anchor
            -- the combo pips prefer.
            plate.UnitFrame.name = S.newMock("FontString")
        S.NAMEPLATE = plate
        end
        return S.NAMEPLATE
    end,
    GetNamePlates = function() return {} end,
}

function UnitPowerMax(_, powerType)
    if powerType == 4 then return S.POWER_SECRET and SECRET or 5 end
    return 1000
end
function GetComboPoints() return S.POWER_SECRET and SECRET or (S.COMBO or 0) end
function UnitIsUnit(a, b) return a == b or (S.HAS_TARGET and a == "nameplate1" and b == "target") end
function UnitHealthMax() return 500 end
function GetShapeshiftForm() return 0 end
function GetShapeshiftFormInfo() return nil end
function GetNumShapeshiftForms() return 0 end
function IsSwimming() return false end
function IsOutdoors() return true end
function GetRealZoneText() return "Elwynn Forest" end
function IsFlyableArea() return false end
function GetBindingKey() return nil end
function SetBindingClick() return true end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function GetWeaponEnchantInfo() return true, 600, 1, 0, false end
function GetItemCooldown() return 0, 0, 1 end
function PlaySound() end
SOUNDKIT = { UI_AUTOLOOT_COMPLETE = 798 }
BOOKTYPE_SPELL = "spell"
function GetSpellTexture() return 136048 end
function CreateFromMixins(...) local o = {} for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do o[k] = v end end return o end
function UnitLevel() return 30 end
function UnitFactionGroup() return "Horde", "Horde" end
function IsLoggedIn() return LOGGED end
function InCombatLockdown() return COMBAT end
function IsInGroup() return IN_GROUP end
function IsInRaid() return false end
function IsInGuild() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end
function IsAltKeyDown() return false end
function GetTime() return os.clock() end
function GetCursorPosition() return 0, 0 end
function GetCursorInfo() return nil end
function CursorHasItem() return false end
function ClearCursor() end
function GetMoney() return 123456 end
function GetInventoryItemID(unit, inv)
    if inv and inv >= 20 and inv <= 23 then return 4500 end
    if CLASS == "HUNTER" and inv == 0 then return 2512 end   -- Rough Arrow
    if CLASS == "HUNTER" and inv == 18 then return 2504 end  -- Worn Shortbow
    return nil
end
function GetInventoryItemCount(unit, inv) return inv == 0 and 150 or 1 end
INVSLOT_AMMO, INVSLOT_RANGED = 0, 18
INVSLOT_MAINHAND, INVSLOT_OFFHAND = 16, 17
-- Temporary weapon enchantments. Main hand coated, off hand bare.
S.TEMPENCH = { [16] = { remainingTimeMs = 1800000, chargesRemaining = 40, enchantID = 603 } }
function GetInventoryItemTexture(unit, inv) return inv and inv >= 20 and inv <= 23 and 133633 or nil end
function GetInventoryItemLink(_, slot) return S.EQUIPPED and S.EQUIPPED[slot] or nil end
function GetInventorySlotInfo() return 20 end
function PickupBagFromSlot() end
function PutItemInBag() end
function ToggleBag() end
function ToggleBackpack() end
function OpenBag() end
function OpenBackpack() end
function CloseAllBags() end
function PlaySound() end
function StaticPopup_Show(which) S.LAST_POPUP = which end
function GetScreenWidth() return 1600 end
function GetScreenHeight() return 900 end
function GetTotemInfo(slot)
    if MODERN and COMBAT then return SECRET, SECRET, SECRET, SECRET, nil, SECRET, SECRET end
    if slot == 1 then return true, "Strength of Earth Totem", 100, 120, 136024, 1, 8075 end
    return false, "", 0, 0, nil, 0, 0
end
function UnitPower(unit, ptype)
    if ptype == 7 then return 0 end
    if MODERN then return SECRET end
    return 650
end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
-- Console variables. S.CVARS survives a simulated reload, the way the
-- real ones survive a session, which is what the settings store relies on.
S.CVARS = S.CVARS or {}
C_CVar = {
    RegisterCVar = function(n, v) if S.CVARS[n] == nil then S.CVARS[n] = v or "" end end,
    GetCVar = function(n) return S.CVARS[n] end,
    SetCVar = function(n, v) S.CVARS[n] = tostring(v) end,
    AreCVarsLoaded = function() return true end,
}
function GetCVar(n) return S.CVARS[n] end
function SetCVar(n, v) S.CVARS[n] = tostring(v) end
-- A handful of Blizzard addons the client really does register, so code
-- that asks "is this present?" gets a truthful answer instead of always no.
local INSTALLED = {
    ["Blizzard_GroupFinder_VanillaStyle"] = true,
}

C_AddOns = {
    GetNumAddOns = function() return 0 end,
    GetAddOnInfo = function(name) if INSTALLED[name] then return name end return nil end,
    IsAddOnLoaded = function() return false end,
    LoadAddOn = function() return false end,
    GetAddOnMetadata = function() return nil end,
    EnableAddOn = function() end,
}

-- Items: slots 1..3 of every real container hold Hearthstones; the rest are
-- empty so the Free aggregate path runs.
local function slotHasItem(bag, slot) return slot <= 3 end
local ITEM_LINK = "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"

S.BAGS_SCANNED = {}
local function numSlots(bag)
    S.BAGS_SCANNED[bag] = (S.BAGS_SCANNED[bag] or 0) + 1
    if bag == 5 and MODERN then return 12 end   -- a reagent bag is equipped
    if bag == 0 then return MODERN and 20 or 16 end
    if bag >= 1 and bag <= 4 then return 16 end
    if MODERN then
        if bag == -1 then return 0 end                -- keyring on Forever: unknown, stub empty
        if bag >= 6 and bag <= 14 then return bag <= 7 and 28 or 0 end
        return 0
    end
    if bag == -2 then return 12 end                   -- TBC keyring
    if bag == -1 then return BANK_OPEN and 28 or 0 end
    if bag >= 5 and bag <= 11 then return (BANK_OPEN and bag <= 6) and 16 or 0 end
    return 0
end

if MODERN then
    function GetBuildInfo() return "1.60.1", "69893", "Sep 16 2026", 16001, "", "" end
    WOW_PROJECT_ID = 1
    function issecretvalue(v) return v == SECRET end
    Enum = {
        AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
        BagIndex = { Accountbanktab = -3, Characterbanktab = -2, Keyring = -1, Backpack = 0, ReagentBag = 5,
                     CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        ItemConsumableSubclass = { Bandage = 7, Itemenhancement = 8, ItemenhancementTemporary = 9 },
        TooltipDataType = { Item = 0, Unit = 2 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, SoulShards = 7 },
    }
    C_RestrictedActions = { IsAddOnRestrictionActive = function(v) return v == 0 and COMBAT end }
    C_PetInfo = {
        GetPetHappiness = petHappiness,
        GetPetLoyalty = function() return PET.loyalty end,
        GetPetTrainingPoints = function() return PET.total, PET.used end,
        GetPetFoodTypes = function() return PET.diet end,
        CanPetEatItem = function(id) return id == 6948 end,   -- the mock bags hold only Hearthstones
    }
    C_PaperDollInfo = { AmmoNeeded = function() return CLASS == "HUNTER" end, IsRangedSlotShown = function() return true end,
        GetTemporaryEnchantmentInfo = function(slot) return S.TEMPENCH[slot] end }
    C_ClassColor = { GetClassColor = function(tok) local c = RAID_CLASS_COLORS[tok]; return c and { r = c.r, g = c.g, b = c.b } end }
    C_XMLUtil = {
        GetTemplateInfo = function(t)
            if ITEM_BUTTON_TEMPLATES[t] then return { type = "ItemButton", width = 37, height = 37 } end
            return { type = "Frame", width = 0, height = 0 }
        end,
    }
    C_Secrets = { HasSecretRestrictions = function() return true end, ShouldCooldownsBeSecret = function() return COMBAT end,
        ShouldUnitPowerBeSecret = function() return S.POWER_SECRET end,
        ShouldUnitPowerMaxBeSecret = function() return S.POWER_SECRET end }

    C_GameRules = { GetActiveGameMode = function() return 3 end, IsHardcoreActive = function() return false end, IsSelfFoundAllowed = function() return false end }
    C_Item = {
        GetItemInfo = function(id)
            -- The real one returns nothing until the item has arrived
            -- from the server, which is the whole reason the addon has
            -- a queue and a redraw.
            if type(id) == "number" and S.UNKNOWN and S.UNKNOWN[id] then return nil end
            if type(id) == "number" and S.UNCACHED and S.UNCACHED[id] then return nil end
            if type(id) == "number" and S.ITEMS and S.ITEMS[id] then
                local link = ("|cffffffff|Hitem:%d::::::::20:::::::::|h[item %d]|h|r"):format(id, id)
                return ("item %d"):format(id), link, 3, 1, 0, "Armor", "", 1, "", 134414,
                       0, 4, 2, 1, 0, nil, false, true
            end
            local name = CLASS == "MAGE" and "Conjured Spring Water" or "Hearthstone"
            return name, ITEM_LINK, 1, 1, 0, "Consumable", "Food & Drink", 20, "", 134414, 0, 15, 0, 1, 0, nil, false, true
        end,
        GetItemInfoInstant = function(id)
            local e = S.ITEMS and S.ITEMS[id]
            if e then
                return id, e.type or "Armor", e.sub or "", e.equipLoc or "", 134414,
                       e.classID or 4, e.subClassID or 2
            end
            if CLASS == "ROGUE" then return 6948, "Consumable", "Item Enhancement", "", 134414, 0, 9 end
            return 6948, "Miscellaneous", "Junk", "", 134414, 15, 0
        end,
        GetItemCount = function(id) return id == 17030 and 0 or 1 end,
        GetItemIconByID = function() return 134414 end,
        -- Answered from the client's own files, so it works for an item
        -- that has never arrived from the server.
        GetItemNameByID = function(id)
            if S.UNKNOWN and S.UNKNOWN[id] then return nil end
            local e = S.ITEMS and S.ITEMS[id]
            if e then return e.name or ("item " .. tostring(id)) end
            return nil
        end,
        GetItemStats = function(link)
            -- Read the id out of the link the way the real one does,
            -- falling back to whatever the test mapped by hand.
            local id = tonumber(tostring(link):match("item:(%d+)"))
                or (S.LINK_TO_ID and S.LINK_TO_ID[link])
            if id and S.UNKNOWN and S.UNKNOWN[id] then return nil end
            local e = id and S.ITEMS and S.ITEMS[id]
            if e and e.stats then return e.stats end
            return { ITEM_MOD_STAMINA_SHORT = 10 }
        end,
        -- Item data is not in memory until asked for, which is the whole
        -- reason the gear panel has a loading step.
        IsItemDataCachedByID = function(id)
            if S.UNCACHED and S.UNCACHED[id] then return false end
            return true
        end,
        RequestLoadItemDataByID = function(id)
            if S.UNCACHED then S.UNCACHED[id] = nil end
            S.REQUESTED = (S.REQUESTED or 0) + 1
        end,
        GetItemSpell = function() return "Hearth", 8690 end,
        GetItemQualityColor = function(q) return 1, 1, 1, "|cffffffff" end,
        GetItemCooldown = function() return 0, 0, 1 end,
        GetWeaponEnchantInfo = function(slot) local e = S.TEMPENCH[slot]
            if not e then return { enchants = {} } end
            return { enchants = { { hasEnchant = true, timeLeft = e.remainingTimeMs, charges = e.chargesRemaining, enchantID = e.enchantID, enchantIconID = 132273 } } } end,
    }
    C_Spell = {
        GetSpellInfo = function(id) return { name = "Fireball", iconID = 135812, originalIconID = 135812, castTime = 3500, minRange = 0, maxRange = 35, spellID = 133 } end,
        GetSpellName = function() return "Fireball" end,
        GetSpellTexture = function() return 135812 end,
        GetSpellCooldown = function(id) return { startTime = COMBAT and SECRET or 0, duration = COMBAT and SECRET or 0, isEnabled = true, modRate = 1 } end,
    }
    C_SpellBook = { IsSpellKnown = function() return not S.ALL_UNKNOWN end }
    C_Container = {
        GetContainerNumSlots = numSlots,
        GetContainerNumFreeSlots = function(bag) return math.max(0, numSlots(bag) - 3), 0 end,
        GetContainerItemInfo = function(bag, slot)
            if not slotHasItem(bag, slot) or slot > numSlots(bag) then return nil end
            return { iconFileID = 134414, stackCount = 1, isLocked = false, quality = 1, hyperlink = ITEM_LINK, itemID = 6948, isBound = true }
        end,
        GetContainerItemLink = function(bag, slot) if slotHasItem(bag, slot) and slot <= numSlots(bag) then return ITEM_LINK end end,
        GetContainerItemID = function(bag, slot) if slotHasItem(bag, slot) and slot <= numSlots(bag) then return 6948 end end,
        UseContainerItem = function() end,
        PickupContainerItem = function() end,
        ContainerIDToInventoryID = function(bag) return 19 + bag end,
        GetItemCooldown = function() return 0, 0, 1 end,
        SortBags = function() S.SORTED = (S.SORTED or 0) + 1 end,
        SortBank = function() S.SORTED_BANK = (S.SORTED_BANK or 0) + 1 end,
    }
    C_Bank = {
        -- Swappable, so a test can be a character who has never been
        -- granted the free first tab.
        FetchNumPurchasedBankTabs = function() return S.BANK_TABS or 2 end,
        FetchMaxNumBankTabs = function() return 9 end,
        FetchPurchasedBankTabData = function() return { { ID = 6, name = "Consumables", icon = 133633 }, { ID = 7, name = "Gear", icon = 133634 } } end,
        FetchNextPurchasableBankTabData = function() return { tabCost = 100000 } end,
        PurchaseBankTab = function() S.PURCHASED_TAB = true end,
        CloseBankFrame = function() BANK_OPEN = false end,
    }
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if COMBAT then error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted") end
            if i > 2 then return nil end
            return { name = i == 1 and "Lightning Shield" or "Water Shield", icon = 136051, applications = 3, duration = 600, expirationTime = 1000, spellId = 324 }
        end,
        GetAuraDataBySpellName = function(unit, name)
            if COMBAT then error("GetAuraDataBySpellName(): Auras cannot be accessed when secret while tainted") end
            return { name = name, spellId = 324 }
        end,
    }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 12, 9 end,
        GetInfo = function(i) return { title = "Quest " .. i, level = 10, isHeader = false, isComplete = false, questID = 100 + i, questLogIndex = i } end,
    }
    function GetNumGroupMembers() return IN_GROUP and 5 or 0 end
    C_CurrencyInfo = {
        GetCoinTextureString = function(c) return c .. "c" end,
        GetBackpackCurrencyInfo = function(i) if i == 1 then return { name = "Honor", quantity = 250, iconFileID = 1455894, currencyTypesID = 1792 } end end,
    }
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, chan) S.SENT[#S.SENT + 1] = { prefix, msg, chan } end,
        InChatMessagingLockdown = function() return false end,
    }
    C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Alchemy", skillLevel = 150, maxSkillLevel = 225, professionID = 171 } end }
    C_ClassTalents = { GetActiveConfigID = function() return 4242 end }
    C_Traits = {}
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) S.TOOLTIP_HOOK = fn end }
    S.MULTICAST = {}
    function SetMultiCastSpell(action, spellID) S.MULTICAST[action] = spellID end
    function GetMultiCastTotemSpells(slot) return 8075 end
    C_SpellBook.IsSpellKnown = function(id)
        if S.ALL_UNKNOWN then return false end
        return id ~= 33943 and id ~= 40120 and id ~= 6229
    end
    C_SpellBook.GetNumSpellBookSkillLines = function() return 2 end
    C_SpellBook.HasPetSpells = function()
        local list = S.PET_SPELLS
        if not list then return nil end
        return #list, "PET"
    end
    C_SpellBook.GetSpellBookItemInfo = function(i, bank)
        if bank ~= 1 then return nil end
        local e = S.PET_SPELLS and S.PET_SPELLS[i]
        if not e then return nil end
        return { name = e[1], isPassive = e[2] == "passive" }
    end
    C_Spell.GetSpellInfo = function(idOrName)
        local names = { [133] = "Fireball", [783] = "Travel Form", [768] = "Cat Form", [1066] = "Aquatic Form", [16864] = "Omen of Clarity" }
        local name = type(idOrName) == "string" and idOrName or (names[idOrName] or ("Spell " .. tostring(idOrName)))
        local id = type(idOrName) == "number" and idOrName or (name == "Searing Totem" and 3599 or 133)
        return { name = name, iconID = 135812, originalIconID = 135812, castTime = (id == 133) and 3500 or 0, minRange = 0, maxRange = 35, spellID = id }
    end
    C_Traits = {
        GenerateImportString = function() return "CkEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" end,
        GetLoadoutSerializationVersion = function() return 2 end,
        GetConfigInfo = function(id) return { ID = id, name = "Loadout A", treeIDs = { 900 } } end,
        GetTreeInfo = function(cfg, tree) return { ID = tree } end,
        GetTreeCurrencyInfo = function() return { { spent = 31, quantity = 0, maxQuantity = 51 }, { spent = 20, quantity = 0, maxQuantity = 51 }, { spent = 0, quantity = 0, maxQuantity = 51 } } end,
        GetTreeHash = function() return { 0 } end,
    }
    C_ClassTalents = { GetActiveConfigID = function() return 4242 end,
        ImportLoadout = function(cfg, entries, name, text) S.IMPORTED = { cfg, name, text } return true end }
    ClassTalentImportExportMixin = {
        ImportLoadout = function(self, text, name)
            if text == "" then self:ShowImportError("empty") return false end
            return C_ClassTalents.ImportLoadout(self:GetConfigID(), {}, name, text)
        end,
    }
    C_Item.GetItemCooldown = function() return 0, 0, 1 end
    Settings = {
        RegisterCanvasLayoutCategory = function(f, n) return { ID = "cat:" .. n, GetID = function(s) return s.ID end } end,
        RegisterCanvasLayoutSubcategory = function(root, f, n) return { ID = "sub:" .. n, GetID = function(s) return s.ID end } end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) OPENED = id end,
    }
else
    function GetBuildInfo() return "2.5.5", "51536", "Sep 12 2026", 20505 end
    WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
    -- A legacy client has no consumable subclass enum, so a rogue's bag
    -- item is named like a poison to exercise the name fallback.
    function GetItemInfo(id)
        local name = CLASS == "ROGUE" and "Instant Poison" or "Hearthstone"
        return name, ITEM_LINK, 1, 1, 0, "Consumable", "Consumable", 1, "",
            "Interface\\Icons\\INV_Misc_Rune_01", 0, 15, 0, 1, 0, nil, false
    end
    function GetItemInfoInstant(id) return 6948, "Miscellaneous", "Junk", "", 134414, 15, 0 end
    function GetItemCount(id) return id == 17030 and 0 or 1 end
    function GetItemIcon() return "Interface\\Icons\\INV_Misc_Rune_01" end
    function GetItemStats(link) return { ITEM_MOD_STAMINA_SHORT = 10 } end
    function GetItemSpell() return "Hearth", 8690 end
    function GetItemQualityColor(q) return 1, 1, 1, "|cffffffff" end
    function GetItemCooldown() return 0, 0, 1 end
    function GetPetHappiness() return PET.happiness, PET.damage, PET.rate end
    function GetPetLoyalty() return PET.loyalty end
    function GetPetTrainingPoints() return PET.total, PET.used end
    function GetPetFoodTypes() return unpack(PET.diet) end
    function GetSpellInfo(id) return "Fireball", "Rank 1", "Interface\\Icons\\Spell_Fire_FlameBolt", 3500, 0, 35, 133 end
    function GetSpellTexture() return "Interface\\Icons\\Spell_Fire_FlameBolt" end
    function GetSpellCooldown() return 0, 0, 1, 1 end
    function IsSpellKnown() return not S.ALL_UNKNOWN end
    GetContainerNumSlots = numSlots
    function GetContainerNumFreeSlots(bag) return math.max(0, numSlots(bag) - 3), 0 end
    function GetContainerItemInfo(bag, slot)
        if not slotHasItem(bag, slot) or slot > numSlots(bag) then return nil end
        return "Interface\\Icons\\INV_Misc_Rune_01", 1, false, 1, false, false, ITEM_LINK, false, false, 6948, true
    end
    function GetContainerItemLink(bag, slot) if slotHasItem(bag, slot) and slot <= numSlots(bag) then return ITEM_LINK end end
    function GetContainerItemID(bag, slot) if slotHasItem(bag, slot) and slot <= numSlots(bag) then return 6948 end end
    function UseContainerItem() end
    function PickupContainerItem() end
    function ContainerIDToInventoryID(bag) return 19 + bag end
    function GetNumBankSlots() return 2 end
    function GetBankSlotCost() return 10000 end
    function PurchaseSlot() S.PURCHASED_SLOT = true end
    function PickupBankItem() end
    function BankButtonIDToInvSlotID(slot) return 39 + slot end
    function CloseBankFrame() BANK_OPEN = false end
    function GetHonorCurrency() return 120 end
    function GetArenaCurrency() return 0 end
    function UnitAura(unit, i, filter)
        if i > 2 then return nil end
        return i == 1 and "Lightning Shield" or "Water Shield", "Interface\\Icons\\x", 3, nil, 600, 1000, "player", false, false, 324
    end
    function GetNumQuestLogEntries() return 12, 9 end
    function GetQuestLogTitle(i) return "Quest " .. i, 10, 0, false, false, false, 0, 100 + i end
    function GetNumRaidMembers() return 0 end
    function GetNumPartyMembers() return IN_GROUP and 4 or 0 end
    function GetCoinTextureString(c) return c .. "c" end
    function RegisterAddonMessagePrefix() return true end
    function SendAddonMessage(prefix, msg, chan) S.SENT[#S.SENT + 1] = { prefix, msg, chan } end
    function GetTradeSkillLine() return "Alchemy", 150, 225 end
    function GetTalentInfo() return "Convection", "x", 1, 1, 5, 5 end
    function GetNumTalentTabs() return 3 end
    function GetTalentTabInfo(i) return "Tab" .. i, "x", i == 1 and 31 or 10 end
    function GetNumSpellTabs() return 1 end
    function GetSpellTabInfo() return "General", "x", 0, 2 end
    -- The druid forms, but only for the player book: this also answers
    -- for "pet", and swallowing that argument hid the pet list entirely.
    function GetSpellBookItemName(i, book)
        if book == "pet" then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            return e and e[1] or nil
        end
        return i == 1 and "Flight Form" or "Cat Form"
    end
    -- Druid forms, hunter pet and aspect spells: a levelled character.
    local KNOWN = { [33943]=1, [133]=1, [883]=1, [6991]=1, [13163]=1, [1066]=1, [783]=1, [768]=1 }
    function IsSpellKnown(id)
        if S.ALL_UNKNOWN then return false end
        return KNOWN[id] == true or KNOWN[id] == 1
    end
    function InterfaceOptions_AddCategory() end
    function InterfaceOptionsFrame_OpenToCategory(f) OPENED = f end
end

-- Load a list of files as one addon, passing (addonName, ns) like the client.
function S.loadAddon(dir, name, files)
    local ns = {}
    for _, f in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. f)
        if not chunk then error("LOAD ERROR " .. f .. ": " .. tostring(err), 0) end
        local ok, rerr = pcall(chunk, name, ns)
        if not ok then error("RUNTIME ERROR " .. f .. ": " .. tostring(rerr), 0) end
    end
    return ns
end

-- Missing-global report: only Capitalized names, which is what a WoW API
-- looks like. Lowercase misses are Lua locals the mock does not model.
function S.missingReport()
    local names = {}
    for k in pairs(S.MISSING) do
        -- Skip template child lookups (_G["WicksBagsSlot3IconBorder"]); they
        -- are expected misses, not API gaps.
        if k:match("^[A-Z]") and not k:match("^Wicks%a+Slot%d") then names[#names + 1] = k end
    end
    table.sort(names)
    return names
end

return S

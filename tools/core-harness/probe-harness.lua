-- Does the watcher catch a buff going up and falling off mid-fight,
-- and does the report make the difference legible afterwards?
local PROBE_DIR, STUB = ...
local S = assert(loadfile(STUB))("modern")
local SECRET = S.SECRET

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) S.CHAT[#S.CHAT + 1] = tostring(m) end }

-- A hand-cranked ticker, so the test controls time.
local ticks = {}
C_Timer = C_Timer or {}
C_Timer.NewTicker = function(_, fn)
    ticks[#ticks + 1] = fn
    return { Cancel = function() ticks = {} end }
end

AURA_UP = false
C_Secrets.ShouldSpellAuraBeSecret = function() return COMBAT end
C_Secrets.GetSpellAuraSecrecy = function() return 2 end
C_UnitAuras = C_UnitAuras or {}
-- The hoped-for shape: real data, secret while restricted, nil when the
-- buff is not there.
C_UnitAuras.GetCooldownAuraBySpellID = function()
    if not AURA_UP then return nil end
    -- The nested table is what the real aura tables carry, and its
    -- address is new on every call. If that reaches the signature,
    -- nothing ever deduplicates.
    return { duration = COMBAT and SECRET or 21, expirationTime = COMBAT and SECRET or 100,
             points = {} }
end
C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
C_UnitAuras.GetUnitAuraBySpellID = function() return nil end
C_UnitAuras.GetAuraDataBySpellName = function() return nil end
local function blocked(what)
    return function()
        if COMBAT then error(what .. "(): Auras cannot be accessed when secret while tainted") end
        return 21
    end
end
C_UnitAuras.GetAuraDuration = blocked("GetAuraDuration")
C_UnitAuras.GetAuraBaseDuration = blocked("GetAuraBaseDuration")
C_UnitAuras.DoesAuraHaveExpirationTime = blocked("DoesAuraHaveExpirationTime")
C_UnitAuras.GetBuffDataByIndex = function(_, i)
    if COMBAT then error("GetBuffDataByIndex(): Auras cannot be accessed when secret while tainted") end
    if i == 1 and AURA_UP then return { spellId = 5171, name = "Slice and Dice" } end
    return nil
end
C_Spell.GetSpellInfo = function(x)
    if x == 5171 or x == "Slice and Dice" then
        return { spellID = 5171, name = "Slice and Dice", iconID = 1 }
    end
end

S.loadAddon(PROBE_DIR, "WicksProbe", { "Surface.lua", "Persist.lua", "UI.lua", "Core.lua" })
S.fire("ADDON_LOADED", "WicksProbe")

local fails = 0
local function want(cond, label)
    if cond then io.write("  ok    ", label, "\n")
    else io.write("  FAIL  ", label, "\n"); fails = fails + 1 end
end

local function tick(n)
    for _ = 1, n do
        for _, fn in ipairs(ticks) do pcall(fn) end
    end
end

S.CHAT = {}
COMBAT = false
SlashCmdList["WICKSPROBE"]("aura watch Slice and Dice")
want(table.concat(S.CHAT):find("watching Slice and Dice", 1, true) ~= nil,
     "arming says what it is watching")

-- A fight: pull, get the buff up, let it fall off, then drop combat.
COMBAT = true; tick(2)                 -- fighting, no buff yet
AURA_UP = true; tick(3)                -- Slice and Dice running
AURA_UP = false; tick(2)               -- it fell off mid-fight
COMBAT = false; AURA_UP = true; tick(2)  -- re-applied, out of combat
AURA_UP = false; tick(2)

S.CHAT = {}
SlashCmdList["WICKSPROBE"]("aura report")

-- The report goes to the probe's own window, not to chat, so read it
-- back out of the edit box the way a player would read it off screen.
local text = table.concat(S.CHAT, "\n")
for _, fr in ipairs(S.frames) do
    local t = fr.__text
    if type(t) == "string" and t:find("aura route samples", 1, true) then text = t end
end
io.write(text, "\n")

want(text:find("IN COMBAT", 1, true) ~= nil, "in-combat samples were captured")
want(text:find("out of combat", 1, true) ~= nil, "and out-of-combat ones")
want(text:find("SECRET", 1, true) ~= nil, "a secret return is recorded as secret")
want(text:find("RAISES", 1, true) ~= nil, "a blocked route is recorded as raising")
want(text:find("aura up", 1, true) ~= nil, "ground truth is labelled when readable")
want(text:find("aura unknown", 1, true) ~= nil, "and unknown in combat, which is the gap")
-- The decisive property: in combat, the route answers differently with
-- the buff up than with it down.
local upSample = text:match("IN COMBAT[^\n]*\n%s+secrecy policy[^\n]*\n%s+secrecy detail[^\n]*\n%s+cooldown aura%s+(SECRET[^\n]*)")
want(upSample ~= nil, "in combat with the buff up the route returns something")

S.CHAT = {}
SlashCmdList["WICKSPROBE"]("aura stop")
want(table.concat(S.CHAT):find("stopped", 1, true) ~= nil, "stop says so")

-- Four states were visited, so four rows. A volatile pointer inside a
-- returned table must not turn every sample into its own row.
local rows = 0
for _ in text:gmatch("%[%d+%]") do rows = rows + 1 end
want(rows == 4, "one row per distinct answer, got " .. rows)

if fails > 0 then error(fails .. " failed", 0) end
io.write("PASS\n")

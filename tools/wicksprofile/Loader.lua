-- Wick's Profile
-- A baked copy of the suite's settings, put back at load.
--
-- On this beta the client writes every addon's saved variables at logout
-- and hands back nothing at load. Addon files themselves load perfectly
-- well, so this sidesteps the bug entirely: the settings live in
-- Profile.lua, which is an ordinary addon file, and get assigned before
-- any Wick addon starts.
--
-- Nothing here is clever. It does not watch, save or guess. Profile.lua
-- is regenerated from outside the game by
-- WickSuite/tools/make-profile.py, which reads what the game wrote to
-- WTF the last time you logged out.
--
-- It never overwrites a global that already has something in it, so a
-- client that starts loading saved variables properly wins.
--
-- The snapshot is only as new as the last bake. An old one does not
-- merely miss changes, it puts the old values back over them, so the
-- login line says when it was taken.
--
-- Throw the whole thing away once Blizzard fixes the client.

local ADDON = ...
local Profile = {}
_G.WicksProfile = Profile

Profile.restored = {}
Profile.skipped = {}

local function out(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff4FC778Wick's Profile|r: " .. tostring(msg))
    end
end

local function looksPopulated(v)
    return type(v) == "table" and next(v) ~= nil
end

function Profile:Apply()
    local data = rawget(_G, "WicksProfileData")
    if type(data) ~= "table" then return 0 end
    local n = 0
    for name, value in pairs(data) do
        if type(value) == "table" then
            if looksPopulated(rawget(_G, name)) then
                self.skipped[#self.skipped + 1] = name
            else
                _G[name] = value
                self.restored[#self.restored + 1] = name
                n = n + 1
            end
        end
    end
    table.sort(self.restored)
    table.sort(self.skipped)
    return n
end

-- At file scope on purpose. This addon loads before the ones it is
-- restoring for, so the globals are in place by the time they read them.
local applied = Profile:Apply()

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if applied > 0 then
        local stamp = rawget(_G, "WicksProfileStamp")
        out(("put back %d saved variable%s, as of %s. Settings you change now last until the next reload, so re-bake when you are happy with them.")
            :format(applied, applied == 1 and "" or "s", stamp or "an unknown date"))
    elseif #Profile.skipped > 0 then
        out("nothing to do, the client supplied its own settings. This addon can go.")
    end
end)

SLASH_WICKSPROFILE1 = "/wprofile"
SlashCmdList.WICKSPROFILE = function(msg)
    msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "list" then
        out("put back: " .. (#Profile.restored > 0 and table.concat(Profile.restored, ", ") or "nothing"))
        out("left alone: " .. (#Profile.skipped > 0 and table.concat(Profile.skipped, ", ") or "nothing"))
        return
    end
    local stamp = rawget(_G, "WicksProfileStamp")
    out(("%d put back, %d left alone.%s"):format(#Profile.restored, #Profile.skipped,
        stamp and (" Baked " .. stamp .. ".") or ""))
    out("Settings changed in game are not captured here. Log out, run make-profile.py, and they are.")
end

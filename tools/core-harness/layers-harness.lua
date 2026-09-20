-- Wick's Layers, offline. The interesting part is not that it records a
-- GUID, it is that it refuses to be fooled by NPCs standing in crowds.

--   args: coreDir, addonsDir, mode, stubPath

local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern

local failures, passes = 0, 0
local function check(cond, label)
    io.write(cond and "  ok    " or "  FAIL  ", label, "\n")
    if cond then passes = passes + 1 else failures = failures + 1 end
end

S.loadAddon(CORE_DIR, "WickCore", {
    "LibStub.lua", "Core.lua", "Client.lua", "Dialect.lua", "Restrict.lua",
    "Locale.lua", "Chrome.lua", "Theme.lua", "Profiles.lua", "Options.lua",
    "Launcher.lua", "Version.lua", "Talents.lua", "Checklist.lua",
    "Racials.lua", "Cooldowns.lua", "Kit.lua",
})
S.fire("ADDON_LOADED", "WickCore")

io.write("== Layers ==\n")
local ns = S.loadAddon(ADDONS_DIR .. "/WicksLayers", "WicksLayers",
    { "Core.lua", "Layers.lua", "Comms.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksLayers")
S.fire("PLAYER_LOGIN")

local L = ns.Layers
check(L ~= nil, "layers module loaded")
check(L:GetCurrentLayerLabel() == "unknown", "no layer before anything is seen")

-- A creature on layer one.
local function see(unit, guid)
    S.GUIDS = S.GUIDS or {}
    S.GUIDS[unit] = guid
    S.fire("NAME_PLATE_UNIT_ADDED", unit)
end

see("nameplate1", "Creature-0-6783-1-69299-3018-0000302B91")
check(L:GetCurrentLayerLabel() == "Layer 1", "first creature mints Layer 1: " .. L:GetCurrentLayerLabel())
check(L.diag.sampled == 1, "one sample recorded")

-- The same creature again, same spawn. Still layer one, no new layer.
see("nameplate1", "Creature-0-6783-1-69299-3018-0000302B91")
check(#L:GetKnownLayers() == 1, "the same spawn does not mint a second layer")

-- A different creature, and we already know where we are, so it joins
-- this layer rather than inventing one.
see("nameplate2", "Creature-0-6783-1-69299-4055-0000401C22")
check(#L:GetKnownLayers() == 1, "a new creature on a known layer does not mint one either")

-- Now the crowd problem: creature 3018 turns up with a second spawn in
-- the same session, which means there are several of it standing about
-- and it can never tell one layer from another.
see("nameplate3", "Creature-0-6783-1-69299-3018-0000999999")
check(L:QuarantinedCount() == 1, "a creature with two spawns at once is set aside")
local bucket = L:Bucket()
check(bucket.spawns["3018"] == nil, "and everything it taught us is dropped")

-- A player GUID is not a creature and must be ignored.
local before = L.diag.sampled
see("nameplate4", "Player-4619-006648E8")
check(L.diag.sampled == before, "player GUIDs are not sampled")

-- Wiping starts over.
L:Reset()
check(L:GetCurrentLayerLabel() == "unknown" and #L:GetKnownLayers() == 0, "wipe clears the realm")

-- Channels: it listens, and it never claims it can post.
S.CHANNELS = {}
S.fire("PLAYER_ENTERING_WORLD")
check(ns.Comms.ownChannelNum > 0, "joins its own channel")
check(ns.Comms.CanSend() == false, "and knows it cannot post on this client")

S.fire("CHAT_MSG_CHANNEL", "anyone on layer 2?", "Someone", nil, nil, nil, nil, nil, nil, "WicksLayer")
check(ns.Comms.heard[2] ~= nil, "a layer call-out in the channel is noted")
check(ns.Comms:ClaimLine():find("Layer") ~= nil or ns.Comms:ClaimLine():find("unknown") ~= nil,
    "a claim line is offered to paste: " .. ns.Comms:ClaimLine())
check(ns.Comms:RequestLine(3) == "layer 3 invite please", "and a request line: " .. ns.Comms:RequestLine(3))

-- The panel.
ns.UI:Toggle()
check(_G.WicksLayersPanel ~= nil and _G.WicksLayersPanel:IsShown(), "panel opens")
see("nameplate1", "Creature-0-6783-1-69299-7001-0000700111")
check(_G.WicksLayersPanel.rows[1] ~= nil and _G.WicksLayersPanel.rows[1]:IsShown(), "and lists the layer once one is known")

S.CHAT = {}
SlashCmdList.WICKSLAYERS("status")
check(#S.CHAT >= 2, "/wl status prints")

local miss = S.missingReport()
if #miss > 0 then
    io.write("== missing globals reached during the run ==\n  ", table.concat(miss, " "), "\n")
end
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, failures))
return failures

-- Offline load test for WickCore.
-- Drives the library end to end against the shared stub client.
--   args: addonDir, mode ("modern" | "legacy"), stubPath

local ADDON_DIR, MODE, STUB = ...
MODE = MODE or "modern"
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern
local fire, SECRET = S.fire, S.SECRET

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end

-- ---------- load the library -------------------------------------------
io.write("== load (", MODE, ") ==\n")
S.loadAddon(ADDON_DIR, "WickCore", { "LibStub.lua", "Core.lua", "Client.lua", "Restrict.lua", "Dialect.lua",
    "Locale.lua", "Chrome.lua", "Theme.lua", "Profiles.lua", "Options.lua", "Launcher.lua", "Version.lua",
    "Talents.lua", "Checklist.lua", "Racials.lua", "Cooldowns.lua", "Kit.lua" })
check(type(WickCore) == "table", "WickCore global")
local Core = WickCore

-- ---------- client --------------------------------------------------------
io.write("== client ==\n")
check(Core.Client:Flavor() == (MODERN and "forever" or "tbc"), "flavor " .. Core.Client:Flavor())
check(Core.Client.isModern == MODERN, "dialect detection")
check(Core.Client.hasSecrets == MODERN, "secrets detection")
check(#Core.Client:Report() == 2, "client report")

-- ---------- lifecycle -----------------------------------------------------
io.write("== lifecycle ==\n")
fire("ADDON_LOADED", "WickCore")
fire("PLAYER_LOGIN")
check(Core.self.initialized and Core.self.enabled, "WickCore self addon initialized + enabled")
check(type(WickCoreDB) == "table" and WickCoreDB.global.minimap.angle == 220, "WickCoreDB defaults")
check(type(SlashCmdList.WICK_WICKCORE) == "function", "/wickcore registered")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("")
check(#S.CHAT >= 3, "/wickcore prints report")
SlashCmdList.WICK_WICKCORE("dialect")
check(#S.CHAT > 5, "/wickcore dialect prints paths")

local initFlag, enableFlag = false, false
local A = Core:NewAddon("WicksTest", {
    title = "Wick's Test", version = "1.2.3", savedVar = "WicksTestDB",
    defaults = { profile = { locked = false, nested = { a = 1 }, list = { "x" } }, global = { seen = 0 } },
})
function A:OnInitialize() initFlag = true end
function A:OnEnable() enableFlag = true end
fire("ADDON_LOADED", "WicksTest")
check(initFlag and enableFlag, "product OnInitialize + OnEnable (post-login init enables immediately)")
check(A.db and A.db.profile.locked == false and A.db.profile.nested.a == 1, "product db defaults applied")
check(A.db.global.seen == 0, "product global defaults")
check(Core:GetAddon("WicksTest") == A, "GetAddon")

-- ---------- dialect -------------------------------------------------------
io.write("== dialect ==\n")
local D = Core.Dialect
local item = D.GetItemInfo(6948)
check(item and item.name == "Hearthstone" and item.classID == 15, "GetItemInfo normalized")
check(D.GetItemInfoInstant(6948).itemID == 6948, "GetItemInfoInstant")
check(D.GetItemCount(6948) == 1, "GetItemCount")
check(D.GetItemIcon(6948) ~= nil, "GetItemIcon")
check(D.GetItemStats("link").ITEM_MOD_STAMINA_SHORT == 10, "GetItemStats")
check(D.GetItemSpell(6948).spellID == 8690, "GetItemSpell")
local sp = D.GetSpellInfo(133)
check(sp and sp.name == "Fireball" and sp.spellID == 133 and sp.castTime == 3500, "GetSpellInfo normalized")
check(D.GetSpellName(133) == "Fireball", "GetSpellName")
check(D.GetSpellTexture(133) ~= nil, "GetSpellTexture")
local cd = D.GetSpellCooldown(133)
check(cd and cd.duration == 0 and cd.enabled, "GetSpellCooldown normalized at rest")
check(D.IsSpellKnown(133), "IsSpellKnown")
check(D.GetContainerNumSlots(0) == (MODERN and 20 or 16), "GetContainerNumSlots")
check(D.GetContainerNumFreeSlots(0) == (MODERN and 17 or 13), "GetContainerNumFreeSlots")
local ci = D.GetContainerItemInfo(0, 1)
check(ci and ci.itemID == 6948 and ci.hyperlink and ci.stackCount == 1, "GetContainerItemInfo normalized")
check(D.GetContainerItemLink(0, 1) ~= nil and D.GetContainerItemID(0, 1) == 6948, "container link + id")
local aura = D.GetAura("player", 1)
check(aura and aura.name == "Lightning Shield" and aura.spellId == 324, "GetAura at rest")
local n = 0
for a in D.IterateAuras("player") do n = n + 1 end
check(n == 2, "IterateAuras yields 2 at rest")
check(D.GetAuraBySpellName("player", "Water Shield") ~= nil, "GetAuraBySpellName")
local q = D.GetQuestLogEntry(3)
check(q and q.title == "Quest 3" and q.questID == 103, "GetQuestLogEntry")
check(select(1, D.GetNumQuestLogEntries()) == 12, "GetNumQuestLogEntries")
check(D.GetNumGroupMembers() == 0, "GetNumGroupMembers solo")
IN_GROUP = true
check(D.GetNumGroupMembers() == 5, "GetNumGroupMembers grouped")
IN_GROUP = false
check(D.CoinString(12345) == "12345c", "CoinString")
check(D.SendAddonMessage("WICK", "hi", "PARTY") == true, "SendAddonMessage at rest")
local ts = D.GetTradeSkillLine()
check(ts and ts.name == "Alchemy" and ts.rank == 150, "GetTradeSkillLine")
local totem = D.GetTotemInfo(1)
check(totem and totem.haveTotem == true and not totem.secret, "GetTotemInfo at rest")
check(#D:Report() > 15, "Dialect report")
if MODERN then check(D.GetActiveTalentConfigID() == 4242, "talent config id (traits)")
else check(D.GetActiveTalentConfigID() == nil, "talent config id nil on legacy") end

-- ---------- restriction --------------------------------------------------
io.write("== restrict ==\n")
local R = Core.Restrict
check(R:IsCombat() == false, "not in combat")
local changes = {}
R:OnChange(function(kind, active) changes[#changes + 1] = kind .. "=" .. tostring(active) end)
COMBAT = true
if MODERN then fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 2) else fire("PLAYER_REGEN_DISABLED") end
check(R:IsCombat() == true, "in combat detected")
check(changes[1] == "Combat=true", "OnChange fired: " .. tostring(changes[1]))
if MODERN then
    check(R:AurasBlocked(), "auras blocked in combat")
    local a, why = D.GetAura("player", 1)
    check(a == nil and why == "restricted", "GetAura returns nil,restricted in combat")
    local cnt = 0
    for _ in D.IterateAuras("player") do cnt = cnt + 1 end
    check(cnt == 0, "IterateAuras yields nothing in combat")
    check(R:IsSecret(SECRET) and not R:IsSecret(5), "IsSecret")
    check(R:Plain(SECRET, "n/a") == "n/a" and R:Plain(7, 0) == 7, "Plain fallback")
    check(R:CooldownsSecret(), "cooldowns secret in combat")
    local t2 = D.GetTotemInfo(1)
    check(t2 and t2.secret == true, "GetTotemInfo flags secret in combat")
    local cd2 = D.GetSpellCooldown(133)
    check(cd2 and R:IsSecret(cd2.duration), "cooldown duration secret in combat")
else
    check(not R:AurasBlocked(), "auras readable in combat on legacy")
    check(D.GetAura("player", 1) ~= nil, "GetAura works in combat on legacy")
end
COMBAT = false
if MODERN then fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0) else fire("PLAYER_REGEN_ENABLED") end
check(changes[2] == "Combat=false", "OnChange fired on clear")
check(D.GetAura("player", 1) ~= nil, "auras readable again")
check(type(R:Summary()) == "string", "Summary")

-- ---------- chrome --------------------------------------------------------
io.write("== chrome ==\n")
local Chrome = Core.Chrome
local win = {}
local panel = Chrome:NewPanel("WicksTestFrame", { title = "Wick's Test", width = 300, height = 200, resizable = true, db = win })
check(panel.content and panel.title and panel.close and panel.grip and panel.brackets.TOPLEFT, "panel parts")
check(Chrome:TitleMarkup("Wick's Test"):find("4FC778") and Chrome:TitleMarkup("Wick's Test"):find("D4C8A1"), "two-tone title")
panel:Show(); panel:Toggle()
check(panel:IsShown() == false, "Toggle")
Chrome:SavePosition(panel, win)
check(win.point == "CENTER" and win.x == 12 and win.width == 300, "SavePosition")
local flag = false
local cb = Chrome:Check(panel.content, "Lock", function() return flag end, function(v) flag = v end)
cb.__scripts.OnClick()
check(flag == true, "Check toggles")
check(Chrome:Button(panel.content, "Go").label:GetText() == "Go", "Button label")

-- ---------- themes --------------------------------------------------------
io.write("== themes ==\n")
check(#Chrome.Themes == 10 and Chrome.ThemeByClass.WARLOCK.id == "fel" and Chrome.ThemeByID.custom, "nine class themes plus custom, warlock is fel")
check(Chrome.activeTheme == "fel" and WickCoreDB.global.theme == "fel", "fel applied from saved default")
local felBefore = Chrome.Colors.fel[3]
local bracket = panel.brackets.TOPLEFT[1]
local titleFS = Chrome:Text(panel.content, 11, Chrome.Colors.text)
Chrome:SetTheme("shaman")
check(Chrome.activeTheme == "shaman" and WickCoreDB.global.theme == "shaman", "SetTheme persists")
check(Chrome:SavedThemeSetting() == "shaman", "saved setting readable back")
WickCoreDB.global.theme = "wiped by something else"
Core.self.db = nil                                  -- profile unbound, as if init never ran
Chrome:SetTheme("druid")
check(WickCoreDB.global.theme == "druid", "SetTheme still writes with no profile bound")
S.fire("PLAYER_LOGOUT")
check(WickCoreDB.global.theme == "druid", "logout flush rewrites the live choice")
Core.self.db = Core.Profiles:Init(Core.self, "WickCoreDB", Core.self.opts.defaults)
Chrome:SetTheme("shaman")
check(Chrome.Colors.fel[3] ~= felBefore and Chrome.Colors.fel[3] > 0.8, "palette mutated in place")
check(bracket.__color and math.abs(bracket.__color[1] - Chrome.Colors.fel[1]) < 0.001, "bracket re-tinted live")
check(titleFS.__textColor and math.abs(titleFS.__textColor[1] - Chrome.Colors.text[1]) < 0.001, "token text re-tinted live")
check(Chrome.ThemeByID.shaman.hex.fel == "0070DD", "shaman accent is the client class color")
check(Chrome:TitleMarkup("Wick's Test"):find("0070DD") ~= nil, "title markup follows theme")
check(Core.COLOR_ACCENT == "|cff0070DD", "chat accent follows theme")
check(Chrome.ThemeByID.priest.colors.void[1] < 0.12, "bright accents keep the darks dark")
Chrome:SetTheme("auto")
check(WickCoreDB.global.theme == "auto" and Chrome.activeTheme == "shaman", "auto resolves to the class theme")
check(Chrome:ResolveTheme("nonsense") == "fel", "unknown theme falls back to fel")
Chrome:SetClassColorSet("classic")
check(Chrome.ThemeByID.mage.hex.fel == "69CCF0" and WickCoreDB.global.classColors == "classic", "classic class color set swaps the mage accent")
Chrome:SetClassColorSet("client")
check(Chrome.ThemeByID.mage.hex.fel == "3FC7EB", "client set restored")
local ct = Chrome:SetCustomColors("2A4A2A", "FFAA00")
check(ct and ct.hex.fel == "FFAA00" and WickCoreDB.global.custom.main == "2A4A2A", "custom colors saved and accent applied verbatim")
check(ct.colors.void[2] > ct.colors.void[1] and ct.colors.border[2] > ct.colors.border[1], "custom darks derived from the main color's hue")
Chrome:SetTheme("custom")
check(Chrome.activeTheme == "custom" and Core.COLOR_ACCENT == "|cffFFAA00", "custom theme applies")
check(Chrome:SetCustomColors("zzz", nil).hex.void == ct.hex.void, "bad hex is ignored")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("theme custom 102040 ff00ff")
check(Chrome.customColors.main == "102040" and Chrome.customColors.accent == "FF00FF" and S.CHAT[1]:find("custom theme"), "/wickcore theme custom <main> <accent>")
Chrome:SetTheme("fel")
check(Chrome.Colors.fel[3] == felBefore and Core.COLOR_ACCENT == "|cff4FC778", "back to fel restores brand values")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("theme list")
check(#S.CHAT >= 3 and table.concat(S.CHAT, " "):find("shaman") ~= nil, "/wickcore theme list prints")

-- ---------- profiles ------------------------------------------------------
io.write("== cooldown bar ==\n")
do
    local prevClass = CLASS
    CLASS = "HUNTER"
    local bar = Core.Cooldowns:New(A, { key = "cdbar" })
    check(#bar:List() > 0, "seeded from the class default")
    bar:Build()
    bar:SetShown(true)
    check(bar.frame:IsShown(), "bar shows")
    check(#bar.buttons > 0 and bar.buttons[1]:GetAttribute("spell") ~= nil, "a secure cast button per spell")
    local before = #bar:List()
    check(bar:Add("Arcane Shot") and #bar:List() == before + 1, "add a spell by name")
    check(not bar:Add("Arcane Shot"), "the same spell is not added twice")
    check(bar:Remove("Arcane Shot") and #bar:List() == before, "remove a spell")
    local str = bar:Export()
    check(str:find("^WICKCD1:") ~= nil, "export string is tagged and readable")
    check(bar:Import("WICKCD1:Sprint;Evasion") and #bar:List() == 2, "import replaces the list")
    check(bar:Import("Vanish", true) and #bar:List() == 3, "import can append")
    COMBAT = true
    local okCD, errCD = pcall(function() bar:Refresh() end)
    check(okCD, "refresh in combat with secret cooldowns " .. tostring(errCD or ""))
    COMBAT = false
    bar:SetShown(false)
    check(not bar.frame:IsShown(), "bar hides")
    CLASS = prevClass
end

io.write("== profiles ==\n")
local db = A.db
db.profile.locked = true
db.profile.nested.a = 42
db.profile.tricky = "pipes | and ~ tildes ~p and :colons: and\nnewlines"
local s = Core.Serialize({ a = 1, b = "two", c = { d = true, e = { 1, 2, 3 } }, f = -1.5 })
local back = Core.Deserialize(s)
check(back.a == 1 and back.b == "two" and back.c.d == true and back.c.e[3] == 3 and back.f == -1.5, "Serialize roundtrip")
local export = db:Export()
check(export:sub(1, 6) == "WICK1:", "Export prefix")
check(not export:find("|", 1, true), "Export has no raw pipes")
db:SetProfile("Alt")
check(db:GetCurrentProfile() == "Alt" and db.profile.locked == false, "SetProfile creates fresh profile with defaults")
local ok, payload = db:Import(export)
check(ok and db.profile.locked == true and db.profile.nested.a == 42, "Import restores values")
check(db.profile.tricky == "pipes | and ~ tildes ~p and :colons: and\nnewlines", "Import preserves tricky string")
check(payload.addon == "WicksTest" and payload.version == "1.2.3", "Import payload metadata")
local bad, why = db:Import("garbage")
check(bad == false and why, "Import rejects garbage")
check(#db:GetProfiles() == 2, "two profiles exist")
db:SetProfile("Default")
db:CopyProfile("Alt")
check(db.profile.nested.a == 42, "CopyProfile")
db:ResetProfile()
check(db.profile.nested.a == 1 and db.profile.locked == false, "ResetProfile")
db:SetKeyMode("spec")
check(db:GetKeyMode() == "spec" and db.key:find("^spec:SHAMAN"), "SetKeyMode spec -> " .. tostring(db.key))
db:SetKeyMode("mode")
check(db.key:find("^mode:"), "SetKeyMode mode -> " .. tostring(db.key))
db:SetKeyMode("char")
check(db.key == "Wick - Classic Beta PvP", "SetKeyMode char")
check(db:DeleteProfile("Alt") == true and #db:GetProfiles() == 1, "DeleteProfile")
check(db:DeleteProfile("Default") == false, "cannot delete Default")

-- ---------- options -------------------------------------------------------
io.write("== options ==\n")
local built = false
local page = A:RegisterOptions(function(body, addon)
    built = true
    local O = Core.Options
    local y = O:Heading(body, "General", 0)
    y = O:Check(body, "Lock", function() return addon.db.profile.locked end, function(v) addon.db.profile.locked = v end, y)
    y = O:Note(body, "note text", y)
    y = O:ProfileSection(body, addon, y)
    check(y < -100, "layout helpers advance y")
end)
check(page ~= nil and Core.Options.pages.WicksTest, "options page registered")
page:Show()
check(built, "options page builds on show")
Core.Options.root.frame:Show()
check(Core.Options.root.frame.built, "root page builds on show")
check(Core.Options.root.frame.themeAuto ~= nil and Core.Options.root.frame.themeNote ~= nil, "theme picker on the root page")
A:OpenOptions()
check(OPENED ~= nil, "OpenOptions")
Core.Options:ShowExport(A, "WICK1:abc")
check(Core.Options.exportPanel and Core.Options.exportPanel.editBox:GetText() == "WICK1:abc", "ShowExport")

-- ---------- launcher ------------------------------------------------------
io.write("== launcher ==\n")
local clicked = false
A:RegisterLauncher({ onClick = function() clicked = true end })
check(Core.Launcher.entries.WicksTest ~= nil, "launcher registered")
check(Core.Launcher.button ~= nil, "minimap button exists")
Core.Launcher:ToggleHub()
check(Core.Launcher.hub and Core.Launcher.hub:IsShown() and #Core.Launcher.hub.rows == 1, "hub shows one product row")
Core.Launcher.hub.rows[1].__scripts.OnClick(nil, "LeftButton")
check(clicked, "hub row click routes to product")
Core.Launcher:SetMinimapHidden(true)
check(WickCoreDB.global.minimap.hidden == true, "minimap hidden persisted")

-- ---------- locale ---------------------------------------------------------
io.write("== locale ==\n")
local L = A:NewLocale("enUS", true)
L["Open"] = true
L["Close window"] = "Close window"
local Lde = A:NewLocale("deDE")
check(Lde == nil, "non-matching locale table skipped")
check(A.L["Open"] == "Open" and A.L["Close window"] == "Close window", "default locale strings")
check(A.L["Missing key"] == "Missing key", "unknown key falls back to itself")

-- ---------- version --------------------------------------------------------
io.write("== version ==\n")
check(Core.Version.registered.WicksTest == A, "product registered for version broadcast")
IN_GROUP = true
S.SENT = {}
Core.Version:Broadcast(true)
local sentTest = false
for _, m in ipairs(S.SENT) do if m[1] == "WICK" and tostring(m[2]):find("WicksTest") then sentTest = true end end
check(sentTest, "broadcast sends on WICK prefix")
IN_GROUP = false
S.CHAT = {}
fire("CHAT_MSG_ADDON", "WICK", "V\tWicksTest\t2.0.0", "PARTY", "Someone")
check(#S.CHAT == 1 and S.CHAT[1]:find("newer version"), "newer version notice")
S.CHAT = {}
fire("CHAT_MSG_ADDON", "WICK", "V\tWicksTest\t2.0.0", "PARTY", "Someone")
check(#S.CHAT == 0, "notice only once per session")
check(Core.compareVersions("1.2.10", "1.2.9") == 1 and Core.compareVersions("1.0", "1.0.0") == 0, "compareVersions")

-- ---------- slash -----------------------------------------------------------
io.write("== slash ==\n")
local got
A:RegisterSlash(function(self, msg) got = msg end, "/wtest", "/wt")
check(SLASH_WICK_WICKSTEST1 == "/wtest" and SLASH_WICK_WICKSTEST2 == "/wt", "slash globals")
SlashCmdList.WICK_WICKSTEST("  hello  ")
check(got == "hello", "slash handler trims and receives message")

io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")

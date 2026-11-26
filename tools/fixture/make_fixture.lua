-- Builds tools/fixture/RPChronicler.lua: a SavedVariables file made by the
-- real addon code in the mock harness (one dungeon run with a story, one
-- open-world run with a story). StoryViewer.html is checked against it
-- with tools/test_viewer.js.
--   python tools/harness/run.py tools/fixture/make_fixture.lua
local ns = NS
local function P(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end io.write(table.concat(t, " "), "\n") end
local errors = {}
local oldDebug = ns.Debug
ns.Debug = function(cat, msg) if cat == "error" then table.insert(errors, msg) end end

NOW = os.time({ year = 2026, month = 11, day = 25, hour = 22, min = 11, sec = 0 })
RPChroniclerDB = { setupVersion = ns.SETUP_VERSION }
Fire("PLAYER_LOGIN")
UNITS.player = { short = "Aloria", full = "Aloria Sunwhisper", guid = "Player-1", level = 13, class = "Hunter", role = "DAMAGER" }
UNITS.pet = { short = "Jack", npc = true }
Fire("PLAYER_ENTERING_WORLD", true, false); RunTimers()

-- Dungeon: Ragefire Chasm with four companions
UNITS.party1 = { short = "Morai", full = "Morai Galeclaw", guid = "Player-2", level = 22, class = "Druid", role = "TANK" }
UNITS.party2 = { short = "Hexer", full = "Hexer Tazira", guid = "Player-3", level = 13, class = "Priest", role = "HEALER" }
UNITS.party3 = { short = "Valeria", full = "Valeria Duskward", guid = "Player-4", level = 13, class = "Paladin", role = "DAMAGER" }
UNITS.party4 = { short = "Malagan", full = "Malagan Zuluni", guid = "Player-5", level = 16, class = "Priest", role = "DAMAGER" }
Fire("GROUP_ROSTER_UPDATE"); RunTimers()
INSTANCE = { name = "Ragefire Chasm", type = "party", id = 389 }
Fire("PLAYER_ENTERING_WORLD", false, false)
ns.Set("instanceRecord", "AUTO")
Fire("PLAYER_ENTERING_WORLD", false, false); RunTimers()
local run = assert(ns.GetActiveAdventure(), "dungeon run did not start")
local function Step(sec) NOW = NOW + sec end
Step(40); ns.RecordAdventureChat("Party", "Morai Galeclaw", "Stay behind me, the fire burns hotter below.")
Step(60); ns.RecordRunNote("Aloria remembers the smell of the Barrens after rain.")
Step(120); Fire("PLAYER_REGEN_DISABLED"); ns.RecordAdventureBossEngage("Oggleflint")
Step(45); ns.RecordAdventureBossKill("Oggleflint"); Fire("PLAYER_REGEN_ENABLED")
Step(5); ns.RecordAdventureScreenshot("boss", "Defeated Oggleflint")
-- 0.6.4: loot with quality, icon and kind (StoryViewer.html colors and draws it)
C_Item = { GetItemInfoInstant = function(id)
  if id == 15287 then return id, "Weapon", "Crossbows", "INVTYPE_RANGEDRIGHT", 135530, 2, 18 end
  if id == 15485 then return id, "Armor", "Leather", "INVTYPE_CHEST", 132719, 4, 2 end
end }
Step(10); ns.RecordAdventureLoot("|cff1eff00|Hitem:15287::::::::13:::::::|h[Barbaric Crossbow]|h|r", "Barbaric Crossbow", "Aloria Sunwhisper", "from Oggleflint", true)
Step(10); ns.RecordAdventureLoot("|cff1eff00|Hitem:15485::::::::13:::::::|h[Native Vest of Stamina]|h|r", "Native Vest of Stamina", "Morai Galeclaw", "looted", true)
Step(300); ns.RecordAdventureChat("Party", "Hexer Tazira", "The light holds. Onward.")
Step(200); Fire("PLAYER_REGEN_DISABLED"); ns.RecordAdventureBossEngage("Taragaman the Hungerer")
Step(80); ns.RecordAdventureBossKill("Taragaman the Hungerer"); Fire("PLAYER_REGEN_ENABLED")
Step(5); ns.RecordAdventureScreenshot("boss", "Defeated Taragaman the Hungerer")
Step(400); ns.RecordAdventureBossKill("Bazzalan")
Step(600)
INSTANCE = nil
Fire("PLAYER_ENTERING_WORLD", false, false); RunTimers()
local dungeon = RPChroniclerDB.adventures[1]
assert(dungeon and dungeon.title == "Ragefire Chasm", "dungeon run not saved")
local code = ns.RunCode and ns.RunCode(dungeon) or dungeon.code

local dungeonStory = table.concat({
  "Title: Chronicle of Ragefire Chasm: Fire, Crabs, and Lazy Goblins",
  "Ragefire Chasm | 31m | Orgrimmar",
  "Date: " .. tostring(dungeon.startDate) .. " | Party: Aloria Sunwhisper, Morai Galeclaw, Hexer Tazira, Valeria Duskward, Malagan Zuluni",
  "",
  "|cffffd100Chapter 1: Beneath the City|r",
  "The heat rose from the chasm like breath from a sleeping beast. |cffff7d0aMorai Galeclaw|r raised a hand: \"Stay behind me, the fire burns hotter below.\"",
  "[Shot " .. tostring(code) .. "-1]",
  "Oggleflint dropped a |cffffd700Barbaric Crossbow|r, and Morai pulled on a Native Vest of Stamina.",
  "",
  "|cffffd100Chapter 2: The Hungerer|r",
  "|cffdc143cTaragaman the Hungerer|r fell, and |cffC0C0C0Hexer Tazira|r whispered, \"The light holds. Onward.\"",
  "[Shot " .. tostring(code) .. "-2]",
  "",
  "Bosses defeated: 3 | Wipes: 0 | Deaths: 0",
  "Run ID: " .. tostring(code),
}, "\n")
local ok, why = ns.ImportStory(dungeonStory, nil)
assert(ok, "dungeon story import failed: " .. tostring(why))

-- Open world: a short quest walk in Durotar
UNITS.party1, UNITS.party2, UNITS.party3, UNITS.party4 = nil, nil, nil, nil
Fire("GROUP_ROSTER_UPDATE")
ZONE = "Durotar"
Step(3600)
local world = assert(ns.StartRun(), "world run did not start")
Step(300); ns.RecordAdventureLine("[QUEST] Aloria Sunwhisper completed Vile Familiars")
Step(200); ns.RecordRunNote("The wind smells of salt and old battles.")
Step(400); ns.RecordAdventureScreenshot("manual", "Sunset over Sen'jin")
Step(300)
ns.EndAdventure("Completed")
local worldRun = RPChroniclerDB.adventures[1]
local wcode = ns.RunCode and ns.RunCode(worldRun) or worldRun.code
local worldStory = table.concat({
  "Title: Salt Wind over Durotar",
  "Durotar | 20m | Durotar",
  "Date: " .. tostring(worldRun.startDate),
  "",
  "|cffffd100Chapter 1: Vile Familiars|r",
  "|cffABD473Aloria Sunwhisper|r walked the red earth with Jack at her heel.",
  "[Shot " .. tostring(wcode) .. "-1]",
  "",
  "Quests completed: 1",
  "Run ID: " .. tostring(wcode),
}, "\n")
ok, why = ns.ImportStory(worldStory, nil)
assert(ok, "world story import failed: " .. tostring(why))

assert(#errors == 0, "addon errors: " .. tostring(errors[1]))
local out = io.open(ROOT .. "/tools/fixture/RPChronicler.lua", "w")
out:write("-- Test fixture made by tools/fixture/make_fixture.lua (do not edit by hand)\n")
out:write("RPChroniclerDB = " .. Serialize(RPChroniclerDB) .. "\n")
out:close()
P("fixture written:", #RPChroniclerDB.adventures, "runs,", #(ns.GetStories()), "stories; codes", code, wcode)

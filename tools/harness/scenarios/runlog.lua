-- 0.7.1 run log: loot dedupe with two-word names, dungeon fight outcomes,
-- the rich boss line, saves, the interrupted-run end stamp and item marks.
local fails = 0
local function Check(name, cond) io.write(cond and "ok   " or "FAIL ", name, "\n") if not cond then fails = fails + 1 end end

LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ROLL_WON = "%s won: %s"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_GREED = "%s has selected Greed for: %s"
LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s"

UNITS.player = { short = "Aloria", full = "Aloria Sunwhisper", guid = "P-1", class = "Hunter", level = 19 }
UNITS.party1 = { short = "Barnabas", full = "Barnabas Vonhausen", guid = "P-2", class = "Priest", level = 15 }
INSTANCE = { name = "Ruins of Lordaeron", type = "party", id = 9001 }
ZONE = "Ruins of Lordaeron"
Fire("ADDON_LOADED", "RPChronicler"); Fire("PLAYER_LOGIN"); RunTimers()

local run = NS.StartAdventure("Ruins of Lordaeron", false)
Check("run started", run ~= nil)

local function Link(id, name) return "|cff1eff00|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end
local girdle = Link(1001, "Soldier's Girdle of the Boar")
local function Loot(msg, author) Fire("CHAT_MSG_LOOT", msg, author or "") end
-- someone else wins: greed chatter, the roll result, then the hand-over
Loot("Aloria Sunwhisper has selected Greed for: " .. girdle)
Loot("Greed Roll - 45 for " .. girdle .. " by Aloria Sunwhisper")
Loot("Barnabas Vonhausen won: " .. girdle)
NOW = NOW + 6
Loot("Barnabas Vonhausen receives loot: " .. girdle .. ".", "Barnabas Vonhausen")
-- you win one
local buckler = Link(1002, "Inscribed Buckler")
Loot("You won: " .. buckler)
Loot("You receive loot: " .. buckler .. ".")

local tl = table.concat(run.fullTimeline, "\n")
local _, girdleLines = tl:gsub("Soldier's Girdle", "")
Check("one line for the girdle", girdleLines == 1)
Check("girdle went to Barnabas, won roll", tl:find("Barnabas Vonhausen received %[Soldier's Girdle of the Boar%] %(won roll%)") ~= nil)
Check("nothing credited to Aloria for the girdle", not tl:find("Aloria Sunwhisper received %[Soldier's"))
Check("buckler is yours, won roll", tl:find("received %[Inscribed Buckler%] %(won roll%)") ~= nil)
local n = 0
for _, e in ipairs(run.keyLoot or {}) do if e.plain == "[Soldier's Girdle of the Boar]" then n = n + 1 end end
Check("Notable Loot holds the girdle once", n == 1)
Check("loot keeps the item id", run.keyLoot[1] and run.keyLoot[1].id == 1001)

-- a dungeon trash fight: names hidden, a flee emote, the party lives
NS.FightBegin()
NS.FightFled("Druid of the Fang")
NOW = NOW + 30
NS.FightFlush()
tl = table.concat(run.fullTimeline, "\n")
Check("trash fight is won, not escaped", tl:find("Druid of the Fang tried to flee once %- the party won") ~= nil and not tl:find("it escaped"))

-- a boss fight: a death, a save, a cry, then the kill
NS.FightBegin()
NS.RecordAdventureBossEngage("Witherfang", nil, 77)
NOW = NOW + 10
NS.RecordAdventureSave("Barnabas Vonhausen", "Healing Potion")
NS.RecordAdventureChat("Party", "Barnabas Vonhausen", "oom!!")
NS.RecordAdventureDeath("Barnabas Vonhausen", false)
NOW = NOW + 25
NS.RecordAdventureBossKill("Witherfang")
NS.FightFlush()
tl = table.concat(run.fullTimeline, "\n")
Check("[SAVED] line", tl:find("%[SAVED%] Barnabas Vonhausen pulled back from the brink %(Healing Potion%)") ~= nil)
local kill = tl:match("%[BOSS KILL%][^\n]*")
io.write("     ", tostring(kill), "\n")
Check("kill has the length", kill and kill:find("after a 35s fight") ~= nil)
Check("kill has the fall", kill and kill:find("Barnabas Vonhausen fell") ~= nil)
Check("kill has the save", kill and kill:find("pulled back from the brink") ~= nil)
Check("no unknown-foes fight line", not tl:find("unknown foes"))

-- a wipe then a kill: second attempt
NS.FightBegin()
NS.RecordAdventureBossEngage("The Butcher", nil, 78)
NOW = NOW + 20
NS.EndAdventureBossPull()
NS.FightFlush()
NS.FightBegin()
NS.RecordAdventureBossEngage("The Butcher", nil, 78)
NOW = NOW + 15
NS.RecordAdventureBossKill("The Butcher")
NS.FightFlush()
tl = table.concat(run.fullTimeline, "\n")
Check("reset line has length", tl:find("%[BOSS RESET%] The Butcher survived the pull after 20s") ~= nil)
Check("won on the 2nd attempt", tl:find("The Butcher after a 15s fight %- won on the 2nd attempt") ~= nil)

-- item marks in the book
local st = { keyLoot = run.keyLoot }
local out = NS.DecorateStoryItems("He tied on [item: Soldier's Girdle of the Boar = the boar-hide belt] and grinned.", st)
io.write("     ", out, "\n")
Check("mark becomes icon link and words", out:find("|Hrpcitem:1001:", 1, true) ~= nil and out:find("the boar%-hide belt and grinned") ~= nil)
Check("no full name left", not out:find("Soldier's Girdle", 1, true))
local unknown = NS.DecorateStoryItems("A [item: Made Up Thing = shiny trinket] here.", st)
Check("unknown item keeps words only", unknown == "A shiny trinket here.")

-- interrupted run: idle for hours, then a new login
run.interruptedAt = time() + 3 * 3600
run.lastSeen = run.interruptedAt
RPChroniclerDB.activeRun = run
NS._resetActiveForTest = true
io.write("done, ", fails, " failed\n")
if fails > 0 then error(fails .. " checks failed") end

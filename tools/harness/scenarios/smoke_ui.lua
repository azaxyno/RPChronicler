-- 0.7.0 smoke test: loads the fixture, opens every section and a book
local ok, err = pcall(function()
  dofile(ROOT .. "/tools/fixture/RPChronicler.lua")
  Fire("ADDON_LOADED", "RPChronicler"); Fire("PLAYER_LOGIN"); RunTimers()
  RPChronicler_Open("")
  io.write("default section: ", tostring(NS.state.section), "\n")
  for _, k in ipairs({ "ADVENTURES", "PLAYERS", "COPY", "OPTIONS", "BOOK" }) do
    NS.UI.ShowSection(k); RunTimers()
    io.write("shown ", k, " -> ", tostring(NS.state.section), "\n")
  end
  io.write("shelves: ", #NS.GetShelves(), "  waiting runs: ", #NS.RunsWithoutStory(), "  stories: ", #NS.GetStories(), "\n")
  local st = NS.GetStories()[1]
  if st then
    NS.UI.OpenStoryBook(st.id); RunTimers()
    io.write("book mode: ", tostring(NS.UI.bookMode), "\n")
    NS.UI.ShowSection("ADVENTURES")
    io.write("book mode after: ", tostring(NS.UI.bookMode), "\n")
    local sh = NS.CreateShelf("Alt road")
    NS.MoveStoryToShelf(st.id, sh.id)
    io.write("on shelf: ", NS.StoryShelf(st), "\n")
    NS.DeleteShelf(sh.id)
    io.write("after delete: ", NS.StoryShelf(st), "\n")
  end
  for _, opt in ipairs({ "GENERAL", "SLICES", "RECORDING", "COMPANIONS", "AI", "PRIVACY" }) do NS.UI.ShowOptionsPage(opt) end
  NS.Set("rpCopy", false); NS.UI.ShowOptionsPage("GENERAL")
  NS.UI.RefreshPlaque()
  RPChronicler_StartRun(); NS.UI.RefreshPlaque(); RPChronicler_EndRun()
end)
io.write(ok and "SMOKE OK\n" or ("SMOKE FAIL: " .. tostring(err) .. "\n"))
if PRINTED and PRINTED:find("rror") then io.write("PRINTED: ", PRINTED, "\n") end
for _, l in ipairs((RPChroniclerDB and RPChroniclerDB.debugLog) or {}) do
  if l:find("error") then io.write("DEBUG: ", l, "\n") end
end
-- 0.7.0 Build B checks
local ok2, err2 = pcall(function()
  io.write("terrain: ", tostring(NS.ZoneTerrain("The Barrens - Ratchet")), " ", tostring(NS.ZoneTerrain("Elwynn Forest")), " ", tostring(NS.ZoneTerrain("Nowhere")), "\n")
  local st = NS.GetStories()[1]
  st.story = "|cffffd100Title: Test|r\n\n|cffffd100Chapter 1: The Road|r\n[emblem:travel]\nThey walked.\n|cffffd100Chapter 2: The End|r\n[emblem:nonsense]\nThey won."
  local em = NS.StoryEmblems(st)
  io.write("emblems: ", table.concat(em, ","), "\n")
  io.write("plain has emblem: ", tostring(NS.GetStoryPlainText(st):find("emblem") ~= nil), "\n")
  io.write("path: ", NS.EmblemPath("sea"), "\n")
  NS.UI.OpenStoryBook(st.id); RunTimers()
  local K = NS.UI.book
  if K and K.list then
    local n = 0
    for _, pg in ipairs(K.list) do for _, it in ipairs(pg.items) do if it.emblem then n = n + 1 end end end
    io.write("emblem items in book: ", n, "\n")
  end
  io.write("role icon: ", NS.RoleIconText({ classFile = "MAGE" }) ~= "" and "yes" or "no", "\n")
  io.write("template has emblem rule: ", tostring(NS.DUNGEON_STORY_TEMPLATE:find("%[emblem:<key>%]") ~= nil), "\n")
end)
io.write(ok2 and "B OK\n" or ("B FAIL: " .. tostring(err2) .. "\n"))
-- 0.7.0 fixes: share picker, right-click menu, outside click, drag, closed book
local ok3, err3 = pcall(function()
  NS.UI.ShowSection("BOOK"); RunTimers()
  local S = NS.UI.shelf
  local st = NS.GetStories()[1]
  S.OpenShelfMenu(S.shareBtn, nil, "PICK")
  S.OpenPeople(S.shareBtn, st)
  S.OpenShelfMenu(S.shareBtn, nil, st.id)
  Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  local sp = S.spines[1]
  if sp then S.BeginDrag(sp); S.EndDrag(sp) end
  NS.UI.OpenStoryBook(st.id); RunTimers()
  NS.UI.book.PlaceCovers()
  io.write("default sharing: ", tostring(NS.Get("storySharing")), "\n")
end)
io.write(ok3 and "FIX OK\n" or ("FIX FAIL: " .. tostring(err3) .. "\n"))

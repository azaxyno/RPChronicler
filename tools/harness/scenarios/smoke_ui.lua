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

# Credits & Third-Party Licenses

RP Chronicler itself is licensed under the GNU General Public License v3.0 (see LICENSE). The parts below keep their own licenses.

## Cinzel (Story Viewer title font)

- **Source**: https://fonts.google.com/specimen/Cinzel
- **Copyright**: Copyright 2020 The Cinzel Project Authors (Natanael Gama)
- **License**: SIL Open Font License 1.1 (https://openfontlicense.org)

A small ASCII subset of Cinzel is embedded in StoryViewer.html for story titles.

## Adventure icons (game-icons.net)

- **Source**: https://game-icons.net (https://github.com/game-icons/icons)
- **Authors**: Lorc (https://lorcblog.blogspot.com), Delapouite (https://delapouite.com), Sbed and Caro Asercion
- **License**: Creative Commons Attribution 3.0 (CC BY 3.0, https://creativecommons.org/licenses/by/3.0/)

The icons in `Media/Icons` are game-icons.net glyphs, recolored in gold and set on our own tinted backgrounds and frames (`tools/icons/make_icons.py`). Glyphs used: spyglass, treasure-map, snowflake-2, mountains, wave-crest, wheat, wolf-head, lion, snake, wolf-howl, octopus, gears, frozen-orb, stone-tablet, crystal-growth, dragon-breath, fire-wave, crowned-skull, volcano and dragon-head by Lorc; desert, forest, palm-tree, swamp, castle, dungeon-gate, pirate-flag, cage, cross-shield, ceremonial-mask, temple-gate, fire-shrine, castle-ruins and spell-book by Delapouite; death-skull by Sbed; boar by Caro Asercion.

## Book art

The shelf and book textures in `Media/Book` (leather, gold trim, parchment, wood, wall, corners, flourish) are our own, drawn by code in `tools/book/make_book_art.py` (GPL-3.0 with the rest of the addon). The book uses the game's own Morpheus font and spellbook sounds.

## Story scene paintings and boss looks (0.6.8)

The paintings of places behind the story scenes (`Media/Scene/bg_*.png`) are our own, drawn by code in `tools/scenes/make_backdrops.py` (GPL-3.0 with the rest of the addon). The boss list in `SceneData.lua` holds only the game's own ID numbers for each boss (its NPC and display IDs), checked against the boss data of the AtlasLootClassic and DungeonJournal addons; no code, text or art of theirs is included. The book's music is the game's own, played by file ID.

## LibDeflate (0.7.0)

- **Source**: https://github.com/SafeteeWoW/LibDeflate (v1.0.2)
- **Author**: Haoqian He (SafeteeWoW)
- **License**: zlib License (the full text is at the top of `Libs/LibDeflate.lua`)

Compresses shared books (Story sharing) and makes share codes. **Altered:** the command-line test part at the end of the file is removed, and the library is handed to RP Chronicler's own table instead of a global; the notes at the top of the file say so.

## Library art and chapter emblems (0.7.0)

The ribbons, plaque, seal, rune ring, quill, unbound pages and key in `Media/Book`, and the chapter emblems in `Media/Emblems`, are our own, made by `tools/book/make_ui_art.py` (GPL-3.0 with the rest of the addon).

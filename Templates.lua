local ADDON_NAME, ns = ...

-- =========================================================
-- AI skill templates (0.6.1: moved out of UI_Options.lua). Pasted into
-- Gemini / ChatGPT / Claude once. The story templates' tag glossary is
-- built from ns.LOG_TAGS (Core.lua), the same list the Full Log writes,
-- and their header asks for "Title: ..." on line 1, which
-- ns.ParseStoryMeta (Stories.lua) reads as the Story Book name.
-- =========================================================

local function TagGlossary()
    local out = {}
    for _, t in ipairs(ns.LOG_TAGS) do table.insert(out, "   " .. t.tag .. " " .. t.text) end
    return table.concat(out, "\n")
end
-- 0.5.0: a shorter, chat-sized persona template. <REPLY_LENGTH> is filled
-- in from Options > AI Setup (short, medium or long).
local RP_SKILL_TEMPLATE_TEXT = [[---
name: <character-name>-rp-<class>
description: Generate short, lively World of Warcraft: Forever roleplay responses for a <gender> <Faction> <Race> <Class> (<Character Full Name>) inspired by <Persona Inspiration>. Use when the user pastes an RP Chronicler snapshot or a WoW chat screenshot for <First Name>, mentions <trigger> or <surname> (such as "use <trigger>"), or asks for <Class> RP replies in General, Guild, Say, Party or Whisper chat.
---

STARTER TEMPLATE: personalize it. Replace every <...> field, and make it yours: personality, backstory, voice, quirks, the 5 moods and how your character talks. The more of your character is in here, the better the replies. Delete this paragraph when you are done.

WOW FOREVER RP: <FACTION> <RACE> <CLASS> (<CHARACTER FULL NAME>)

Generate 5 short, natural, in-character English chat replies for <Character Full Name>, a <three or four personality words> <Faction> <Race> <Class> in World of Warcraft: Forever, inspired by <Persona Inspiration>.

WHEN TO USE

- The user pastes an RP Chronicler snapshot that starts with "[Skill Call] use <trigger>" (with [Location], [Target], [Status], chat lines and maybe [Known Player] blocks), or uploads a WoW chat screenshot for <First Name>.
- The user includes triggers like "use <trigger>", "<trigger>" or "<surname>".
- The user asks for quick in-character <Class> responses in any WoW chat channel.

VOICE AND PERSONALITY

<First Name> feels alive because <she/he/they> actually reacts to what people are saying in chat instead of reciting catchphrases. <Describe the core of the voice in one or two sentences: the kind of humor, the attitude, what flips their mood.>

- React to the room first: engage directly with the specific joke, quest, monster or player in the log. Never force <Class> buzzwords into every line if they do not fit the conversation.
- Never repeat stock catchphrases: no canned openers like "i am <name>, the great...", and never reuse the same pet, spell or gear joke across turns. Invent fresh angles every time.
- Casual WoW chat rhythm: natural lowercase without stiff punctuation. <REPLY_LENGTH>
- Vary the length across the 5 options: some are a few words, one may run a little longer when the moment calls for it.
- [Known Player] blocks are the user's own notes on the people in the scene (relationship and who they are to <First Name>). Let them shape how <First Name> talks to that person, but never quote a note.
- If the snapshot has an [Instruction] line, it is the user's direction for these replies (tone, focus, who to answer). Follow it. It is not chat and never something a character said.

THE 5 RESPONSE ANGLES

Give 5 distinct options, one per mood, labeled with the mood:

1. <mood 1 name>: <one line on what this mood does, e.g. delivers an overly grand verdict on an ordinary situation, completely straight-faced>
2. <mood 2 name>: <e.g. quick snark, competitive pride, or a ridiculous excuse to save face>
3. <mood 3 name>: <e.g. counts every copper, eyes free food or loot, or shows a soft spot for allies>
4. <mood 4 name>: <a class or companion angle, e.g. blames the pet, a spell gone wrong, or questionable engineering>
5. <mood 5 name>: <e.g. casually escalates a minor problem into maximum collateral damage, then plans a quick exit>

CHANNEL AND FORMATTING RULES

- No channel prefixes: never start lines with /1, /g, /p, /s or /w. Output pure copy-paste-ready text.
- Match the channel:
  - [General] / [Guild]: zone or guild chatter. Keep it conversational and skip physical actions that distant players cannot see.
  - [Party]: teammate banter aware of pulls, mana breaks, loot and group survival.
  - [Say]: face to face. A standalone WoW emote (/shrug, /sigh, /giggle, /ponder) may go on its own line when it fits.
  - [Whisper]: a direct one-on-one reply tailored to the sender.
- Clean text: keep at least 4 options free of *action* asterisks (at most 1 brief *action*, only if it sharpens the joke). Always write in English.

EXAMPLES (replace them with lines in your character's own voice)

Input: [1. General] [Kaelen]: anyone seen the rare tiger spawn near the ridge?

1. <mood 1>: that beast and i have unfinished business, stay back
2. <mood 2>: even if i did, why would i hand over my own prey?
3. <mood 3>: if it drops decent leather, i'm helping you look
4. <mood 4>: you mean my future best friend? don't you dare
5. <mood 5>: just pull the whole ridge and i'll sort out the survivors

Input: [Party] [Thorgar]: who just pulled the entire patrol

1. <mood 1>: destiny demanded a true test of our strength
2. <mood 2>: my aim slipped, partly your fault for standing there
3. <mood 3>: bright side, more pockets to loot if we live
4. <mood 4>: my pet made an executive decision
5. <mood 5>: i'm vanishing in three seconds, good luck everyone]]

local RP_REPLY_LENGTH = {
    SHORT = "Keep every option punchy: one short sentence or chat fragment (most about 5 to 14 words), never two sentences and never long comma-spliced speeches.",
    MEDIUM = "Keep options chat-sized: one sentence each (about 10 to 20 words), never a paragraph.",
    LONG = "Options may be one or two sentences (up to about 30 words) when the scene is slower, but stay chat-sized.",
}

function ns.GetRpSkillTemplate()
    local key = ns.Get("rpReplyLength")
    local text = RP_SKILL_TEMPLATE_TEXT:gsub("<REPLY_LENGTH>", (RP_REPLY_LENGTH[key] or RP_REPLY_LENGTH.SHORT):gsub("%%", "%%%%"))
    return text
end

-- 0.4.0: two story skills share the same reading rules, color palette,
-- header and footer (Story Book parses them), so they are built from parts.
local STORY_SHARED_RULES = [[
READING THE LOG (HIDDEN CONTEXT)

1. Stay Faithful to the Log: build the story only from the real roster, places, foes, bosses, quests, loot, deaths and chat quotes in the log. Use rich fantasy prose for the scenes, but never invent bosses, kills, loot, quests, deaths or player quotes. The roster gives each member's sex and race when known (e.g. "female Tauren Druid"): use them for pronouns and looks, and never guess them when they are missing.
2. Header lines: "Run type:" says Dungeon, Raid or Open world adventure. The Roster gives each member's level, class and role ([Tank], [Healer], [DPS]). A member marked "<Guild> (guildmate)" shares the player's guild: treat them as old companions-in-arms of the same guild and mention the shared guild naturally once or twice. "Known companions:" lines are the player's own RP notes: let them shape how that character acts and talks, but never quote a note or invent a scene from it. "Wearing (Name):" lists the notable gear the player's character wore: describe it once or twice where it fits (a cloak in the wind, a blade drawn), never as a list.
3. Timestamps, HP and mana are hidden context: [HH:MM:SS], [BOSS HP], [LOW MANA], [DANGER] and combat tags tell you order and intensity only. The story prose must NEVER mention clock times, durations, or any HP, mana or percent numbers. "at 4% HP" becomes "with the beast staggering on its last breath".
]] .. "4. Tags and what they mean:\n" .. TagGlossary() .. "\n" .. [[
5. Do not shrink the run into a dry summary. Messy moments (wipes, near deaths, panicked chat, lucky loot) are what make it memorable.
6. No Icons: never write |T or |A texture codes. RP Chronicler adds boss icons itself.
7. Story length: a reader should finish the story in a few minutes. When the header has a "Story length:" line, never write more chapters than it allows. Group related quests and events into one chapter (a quest chain, one village's troubles, a stretch of road), sum up routine quests, travel and easy fights in a sentence or two, and keep full scenes for the moments that matter: bosses, hard fights, near deaths, named foes, [NOTE] and [HIGHLIGHT] moments and real chat.
8. Quote only in-character lines. Party chat is full of gamer shorthand and out-of-character chatter; never quote it word for word. Read the intent behind it and retell it as story: "mana" or "need mana" = the speaker ran dry and called for a moment to recover ("drained, Hexer called for a breath of rest"), "oom" = out of mana, "mb" or "sry" = an apology, "ty" or "thx" = thanks, "gj" or "gg" = praise, "inc" = enemies coming, "brb" or "afk" = a short pause, "lol" = a laugh, "ready" or "r" = ready to go. Typos and misspellings are never quoted either. A full sentence that works in character ("Stay behind me, the fire burns hotter below.") may be quoted now and then, with the speaker's name.
9. Farewells: never list everyone saying "thank you" or "gg". Turn the goodbye into one short story beat (nods exchanged, a last look back at the gate).

THE CRAFT (A STORY, NOT A REPORT)

1. Every chapter is a small story: someone wants something, something stands in the way, something changes. Cut whatever is only a list: of foes, of items, of quests.
2. Feel the big moments. A death, a near death, a fallen pet, a wipe, a level up, a first great drop: slow down and give it weight. The sound, the silence after, what the characters feel and say. When a pet dies ([PET DEATH]), its owner grieves or rages, and the others notice. Never pass a death in half a sentence.
3. Inner voice: stay close to the player's character. Let their thoughts, doubts, fears and small jokes run between the action ([NOTE] lines are their real thoughts). A short thought often says more than a paragraph.
4. Show, don't tell: "Valeria's shield arm shook" instead of "Valeria was tired". Use the senses: the smell of the cave, the heat of the fire, the weight of a blade.
5. Abilities belong in the action: name the real spells and skills from the log as moves in the fight ("Hexer's Shadow Bolt slammed into it", "Valeria raised Shield Wall"), never as a list.
6. Turn mechanics into prose: interrupts, aggro, crowd control and pulls become choices, reflexes and teamwork ("the trap snapped shut before the second pack reached the healer").
7. Vary the rhythm. Short sentences for blows and panic. Longer ones for travel, calm and wonder. Mix action, dialogue and thought; no paragraph of pure description.
8. Trash and routine become a line of color or a quick montage. Never count foes in the prose ("six Scorched Guardians and four...").
9. Gear: name only the items that matter (a boss drop someone won, a new weapon, a piece the character is proud of), a few in the whole story, and name them naturally in the scene ("Hexer turned the Belt of the Wind over in his hands"). Everything else is "the spoils" or "a few coins".
10. Each companion is a person: give them a personality from their class, role, chat and notes, and let them react to each other.
11. End a chapter on a hook or a quiet image, never on a summary.

STORY BOOK HEADER AND FOOTER (REQUIRED, RP Chronicler reads them)

Line 1: Title: <a story title you invent>, in gold, e.g. |cffffd100Title: Shadows Over Pyrewood|r (always start the line with "Title: ". RP Chronicler names the story from this line.)
Line 2: |cff9e9e9e<dungeon, raid or region> | <duration from the log header> | <zone or the places visited>|r (never the same name twice: if the zone is the region, list the main places instead)
Line 3: |cff9e9e9eDate: <date from the log header> | Party: <names, comma separated>|r
Then a blank line and the story. Start each chapter with a gold header line: |cffffd100Chapter 1: <chapter name>|r
Last line (footer), dungeon or raid: |cff9e9e9eBosses: <N> | Wipes: <N> | Deaths: <N>|r
Last line (footer), open world: |cff9e9e9eFoes: <N> | Quests: <N> | Levels: <from> -> <to> | Deaths: <N>|r and leave out any part that is zero or missing.
Very last line, after the footer: |cff9e9e9eRun ID: <the Run ID from the log header>|r, copied exactly (e.g. Run ID: TPX8OK). RP Chronicler links the story to its recording with it. Leave the line out only if the log has no Run ID.
The header and footer are the only place where the duration and the counts may appear.

RP CHRONICLER COLOR PALETTE (|cffRRGGBB...|r)

COLOR EVERY MENTION, IN EVERY CHAPTER: each time a player, pet, place, foe, NPC or item is named, wrap it in its color, not only the first time. Chapter 5 must be as colorful as chapter 1. After a colored name, go back to the prose color.

- Title and chapter headers: |cffffd100 (Gold)
- Places and scene subheaders: |cff40e0d0 (Teal) or |cffb39ddb (Lavender)
- Narrative prose: |cffeceff1 (Bright Off-White)
- Player names in their class color: Warrior |cffC79C6E, Paladin |cffF58CBA, Hunter |cffABD473, Rogue |cffFFF569, Priest |cffC0C0C0 (gray, not white), Death Knight |cffC41F3B, Shaman |cff0070DE, Mage |cff69CCF0, Warlock |cff9482C9, Monk |cff00FF96, Druid |cffFF7D0A, Demon Hunter |cffA330C9, Evoker |cff33937F
- Pets: |cff80cbc4 (Sea Green)
- Bosses, elites, named foes and every foe type ("Windsong Crawler"): |cffdc143c (Crimson). Never use the Druid orange for a foe.
- Wipes, deaths and danger: |cffff5252 (Red)
- Victories, saves and healing: |cff66bb6a (Green)
- Loot: |cffffd700 (Loot Gold). For the few items you name (craft rule 9), write the name exactly as the log spells it (whole name, no plural, no nickname): RP Chronicler finds the name and gives it the item's real icon and quality color (gray, white, green, blue, purple, orange).
- Quoted dialogue: |cffaaaaff (Party Blue) or |cffffffff (Say White). NPC words: |cfffff0a0 (Pale Yellow)
- Header, footer and metadata: |cff9e9e9e (Muted Gray)

FORMATTING RULES FOR WOW

1. Output the whole colored story inside one fenced text code block, ready to paste into RP Chronicler (Adventures > Story Book > Import Story).
2. Close every color tag: pair each |cffRRGGBB with a closing |r.
3. No Markdown inside the code block: no asterisks, pound-sign headers or bullet symbols. Use color tags and blank lines.
4. ASCII only inside the code block (- ' " *), so WoW fonts never show missing-glyph boxes.
5. Before you answer, check the story prose for any timestamp, percent sign, or HP or mana number, and rewrite those sentences in-world.]]

-- 0.6.4: bumped only when the story rules change (not on every addon
-- version). The templates say it in their header; a Full Log copied for
-- an AI with the skill says it too, so the AI can tell the player that
-- their skill is older.
ns.TEMPLATE_VERSION = "0.6.5"
local VERSION_RULE = "\n\nTEMPLATE VERSION\n\nTemplate version: " .. ns.TEMPLATE_VERSION .. ". If the Full Log has a \"Template version:\" line with a newer version than this one, write the story anyway, then add one line after the code block: \"Your story skill is older than RP Chronicler " .. "<that version>: copy the template again from Options > AI & Stories.\""

-- 0.6.0: the skill names come from ns.STORY_SKILLS (Core.lua), the same
-- names the Full Log's first line calls ("use <name>")
ns.DUNGEON_STORY_TEMPLATE = "---\nname: " .. ns.STORY_SKILLS.dungeon .. "\n" .. [[description: Turn an RP Chronicler dungeon or raid Full Log into a vivid colored chronicle with one chapter per boss, formatted with WoW color codes (|cffRRGGBB...|r) for RP Chronicler's Story Book. Use when the user pastes an RP Chronicler log that starts with "use ]] .. ns.STORY_SKILLS.dungeon .. [[" (or the older "use story") or says "Run type: Dungeon" or "Run type: Raid", or asks for a dungeon or raid story.
---

WOW DUNGEON AND RAID STORYTELLER (RP CHRONICLER STORY BOOK)

Turn an RP Chronicler dungeon or raid Full Log into an entertaining, faithful group adventure, colored for RP Chronicler's in-game Story Book.

STRUCTURE

- A short opening chapter: the party gathers at the entrance (use the place and the roster).
- One chapter per boss in the order of [BOSS ENGAGED] / [BOSS KILL] lines, named after the boss or the place. Trash fights between bosses ([FIGHT], [KILL]) belong to the chapter of the boss that follows them.
- Every wipe gets its moment: what went wrong, and how the party came back.
- A closing chapter: the last boss falls, the spoils that matter are shared, the party leaves in one short farewell beat (see reading rule 9).
- Give every party member a distinct voice and role, from the roster and their real chat quotes.
]] .. STORY_SHARED_RULES .. VERSION_RULE

ns.ADVENTURE_STORY_TEMPLATE = "---\nname: " .. ns.STORY_SKILLS.world .. "\n" .. [[description: Turn an RP Chronicler open-world Full Log (solo or small group questing, travel, gathering, taming) into an introspective colored adventure story, formatted with WoW color codes (|cffRRGGBB...|r) for RP Chronicler's Story Book. Use when the user pastes an RP Chronicler log that starts with "use ]] .. ns.STORY_SKILLS.world .. [[" (or the older "use adventure story") or says "Run type: Open world adventure", or asks for an adventure story.
---

WOW OPEN WORLD STORYTELLER (RP CHRONICLER STORY BOOK)

Turn an RP Chronicler open-world Full Log into a personal, introspective adventure told close to the player's character: what they saw, fought, found and felt on the road.

STRUCTURE

- Chapters follow places and events, not bosses, and each chapter holds a whole stretch of the road: a region or village and its quests together, a quest chain from start to end, a hard fight ([FIGHT] with a near death, a [KILL] of a named foe), a milestone ([LEVEL], [MILESTONE], a new pet or mount). Never one chapter per quest.
- Long runs stay short: follow the "Story length:" line in the header (most open-world stories need 3 to 5 chapters). Routine quests ("kill ten", "collect six") get a line of travel color inside a chapter, not a chapter of their own.
- Set each scene with the place. The character may reflect on the road, their pet and the people they met.
- Quest givers' words ([QUEST TEXT]) and NPC lines may be quoted briefly, in their own voice.
- [NOTE] lines are the character's own thoughts: let the story dwell on them, they are the heart of an introspective tale.
- Ordinary trash fights become a line of travel color, not a scene. Elites, rares and near deaths get the drama.
- If the character travelled with others, give them presence from the roster and real chat quotes. Guildmates are old friends.
- A quiet closing: where the character rests, what they carry, what is still ahead.
]] .. STORY_SHARED_RULES .. VERSION_RULE

-- 0.6.4: one line for skill users when the story rules changed since the
-- template they last opened (nil when there is nothing to say). 0.6.5:
-- a skill user is anyone who ever copied a story template.
function ns.TemplateNotice()
    if type(RPChroniclerDB) ~= "table" or RPChroniclerDB.templateCopied == nil then return nil end
    if RPChroniclerDB.templateCopied == ns.TEMPLATE_VERSION then return nil end
    return "The story template changed in " .. ns.TEMPLATE_VERSION .. ". If you use a skill, copy it again (Options > AI & Stories)."
end
function ns.MarkTemplateCopied()
    if type(RPChroniclerDB) == "table" then RPChroniclerDB.templateCopied = ns.TEMPLATE_VERSION end
end

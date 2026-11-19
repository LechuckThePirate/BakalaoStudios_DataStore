local _, ns = ...

-- Raid attunements and dungeon keys of Classic content, per character. An attunement is done when one of its
-- quests is completed (the game remembers), a key when the character has the item anywhere (bags, bank or
-- worn; Forever has no keyring, keys go in the bags). rec.quests[questID] = true for the quests below.
-- `faction` picks the quest the game offers that faction (for Completao!!'s "show the quest").
ns.ATTUNEMENTS = {
    { key = "mc", short = "MC", name = "Molten Core", quests = { 7848, 7487 } },
    { key = "ony", short = "Ony", name = "Onyxia's Lair", quests = { 6502, 6602 }, item = 16309,
        questFor = { Alliance = 6502, Horde = 6602 } },
    { key = "bwl", short = "BWL", name = "Blackwing Lair", quests = { 7761 } },
    { key = "naxx", short = "Naxx", name = "Naxxramas", quests = { 9378, 9121, 9122, 9123 }, questFor = { Alliance = 9121, Horde = 9121 } },
    { key = "ubrs", short = "UBRS", name = "Upper Blackrock Spire", quests = { 4743 }, item = 12344 },
    { key = "brd", short = "BRD", name = "Blackrock Depths", quests = { 3802 }, item = 11000 },
    { key = "scholo", short = "Scholo", name = "Scholomance", quests = { 5505, 5511 }, item = 13704,
        questFor = { Alliance = 5505, Horde = 5511 } },
    { key = "strat", short = "Strat", name = "Stratholme", item = 12382 },
    { key = "dm", short = "DM", name = "Dire Maul", item = 18249 },
    { key = "sm", short = "SM", name = "Scarlet Monastery", item = 7146 },
    { key = "zf", short = "ZF", name = "Zul'Farrak", item = 9240 },
    { key = "gnomer", short = "Gnomer", name = "Gnomeregan", item = 6893 },
}

local function questDone(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok then return done == true end
    end
    if IsQuestFlaggedCompleted then
        local ok, done = pcall(IsQuestFlaggedCompleted, questID)
        if ok then return done == true end
    end
    return false
end

-- The attunements' quests, and any other an addon asked to follow (ns.WatchQuest: a goal "complete this quest").
function ns.Attunements_Scan()
    local rec = ns.Me()
    rec.quests = rec.quests or {}
    local before = 0
    for _ in pairs(rec.quests) do before = before + 1 end
    for _, a in ipairs(ns.ATTUNEMENTS) do
        for _, q in ipairs(a.quests or {}) do
            if questDone(q) then rec.quests[q] = true end
        end
    end
    for q in pairs(ns.db.watchedQuests or {}) do
        if questDone(q) then rec.quests[q] = true end
    end
    local after = 0
    for _ in pairs(rec.quests) do after = after + 1 end
    if after ~= before then ns.Changed("quests") end
end

-- Follows a quest for every character from now on (saved: each character records it when it logs in).
function ns.WatchQuest(questID)
    if type(questID) ~= "number" then return false end
    ns.db.watchedQuests = ns.db.watchedQuests or {}
    ns.db.watchedQuests[questID] = true
    if questDone(questID) then
        local rec = ns.Me()
        rec.quests = rec.quests or {}
        rec.quests[questID] = true
    end
    return true
end

-- Whether a character has completed a quest: asked from the game for the one playing, from its copy otherwise
-- (only the attunements' and the watched quests are known for the others).
function ns.QuestDone(key, questID)
    if ns.IsMe(key) then return questDone(questID) end
    local rec = ns.GetChar(key)
    return rec ~= nil and rec.quests ~= nil and rec.quests[questID] == true
end

local function hasItem(rec, itemID)
    return ((rec.bags and rec.bags[itemID]) or 0) + ((rec.bank and rec.bank[itemID]) or 0)
        + ((rec.equipped and rec.equipped[itemID]) or 0) > 0
end

-- "done", "key" (has the key item; for a key-only entry that is done too) or nil; and the quest that did it.
function ns.Attunements_Status(rec, a)
    for _, q in ipairs(a.quests or {}) do
        if rec.quests and rec.quests[q] then return "done", q end
    end
    if a.item and hasItem(rec, a.item) then return a.quests and "key" or "done" end
    return nil
end

-- The quest to show in Completao!! for a character: the one of its faction, else the first.
function ns.Attunements_Quest(a, faction)
    if a.questFor and faction and a.questFor[faction] then return a.questFor[faction] end
    return a.quests and a.quests[1] or nil
end

function ns.Attunements_Init()
    ns.On("QUEST_TURNED_IN", function() ns.Debounce("attunements", 1, ns.Attunements_Scan) end)
end

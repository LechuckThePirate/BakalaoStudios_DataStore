local _, ns = ...

-- The account's characters, saved account-wide in BakalaoDataStoreDB and shared by every BakalaoStudios addon:
--   chars[key]  = everything known about one character (key "Name-Realm"); the game can't tell anything about a
--                 character that isn't playing, so each one saves its own copy when it plays
--   guilds[key] = the guild banks seen ("Guild-Realm")
--   account     = the account-wide (warband) bank, when the client has one
--   items[id]   = { n = name, q = quality, c = classID, s = subclassID } of the items seen, to search and sort
--                 without the game's item cache
--   resets      = { daily =, weekly = } the next resets, learned while playing
--   settings    = the store's own options (autoPlayed)
-- Nothing in a record belongs to one addon: what an addon adds about a character (notes, hidden...) it keeps in
-- its own saved variables.
ns.DB_VERSION = 1
ns.DEFAULTS = {
    autoPlayed = true, -- ask the game for the played time at login (without the chat lines)
}

function ns.InitDB()
    BakalaoDataStoreDB = BakalaoDataStoreDB or {}
    local db = BakalaoDataStoreDB
    db.version = db.version or ns.DB_VERSION
    db.chars = db.chars or {}
    db.guilds = db.guilds or {}
    db.items = db.items or {}
    db.resets = db.resets or {}
    db.settings = db.settings or {}
    ns.db = db
    ns.settings = setmetatable({}, {
        __index = function(_, key)
            local value = db.settings[key]
            if value == nil then return ns.DEFAULTS[key] end
            return value
        end,
        __newindex = function(_, key, value) db.settings[key] = value end,
    })
end

function ns.MyKey()
    return ns.PlayerName() .. "-" .. ns.RealmName()
end

-- The playing character's record (created the first time).
function ns.Me()
    local key = ns.MyKey()
    local rec = ns.db.chars[key]
    if not rec then
        rec = { name = ns.PlayerName(), realm = ns.RealmName(), firstSeen = ns.Now() }
        ns.db.chars[key] = rec
    end
    return rec
end

function ns.IsMe(key)
    return key == ns.MyKey()
end

function ns.GetChar(key)
    return ns.db and ns.db.chars[key]
end

-- Every character: { { key =, rec = } } by level (highest first) and name.
function ns.Characters()
    local list = {}
    for key, rec in pairs(ns.db.chars) do list[#list + 1] = { key = key, rec = rec } end
    table.sort(list, function(a, b)
        local la, lb = a.rec.level or 0, b.rec.level or 0
        if la ~= lb then return la > lb end
        return (a.rec.name or a.key) < (b.rec.name or b.key)
    end)
    return list
end

-- Finds a character by name (what is typed in a command, a mail recipient...): spaces and case ignored, the realm
-- optional.
function ns.FindCharByName(name)
    if not name then return nil end
    local wanted = name:gsub("%s", ""):lower()
    for key, rec in pairs(ns.db.chars) do
        local plain = (rec.name or ""):gsub("%s", ""):lower()
        if plain == wanted or key:gsub("%s", ""):lower() == wanted then return key, rec end
    end
    return nil
end

-- Deletes everything saved about a character (not the one playing). It comes back the next time it logs in.
function ns.Forget(key)
    if not ns.db.chars[key] or ns.IsMe(key) then return false end
    ns.db.chars[key] = nil
    ns.Changed("forget", key)
    return true
end

-- Takes a record saved by an addon before the store existed (Alterao 0.1.0): kept when the store has nothing newer.
function ns.Import(key, rec)
    if type(key) ~= "string" or type(rec) ~= "table" then return false end
    local mine = ns.db.chars[key]
    if mine and (mine.lastSeen or 0) >= (rec.lastSeen or 0) then return false end
    ns.db.chars[key] = rec
    if ns.Character_Repair then ns.Character_Repair(rec) end
    return true
end

function ns.ImportShared(guilds, items, account, resets)
    for key, g in pairs(guilds or {}) do
        local mine = ns.db.guilds[key]
        if not mine or (mine.time or 0) < (g.time or 0) then ns.db.guilds[key] = g end
    end
    for id, entry in pairs(items or {}) do
        if not ns.db.items[id] then ns.db.items[id] = entry end
    end
    if account and (not ns.db.account or (ns.db.account.time or 0) < (account.time or 0)) then ns.db.account = account end
    for kind, at in pairs(resets or {}) do
        if not ns.db.resets[kind] then ns.db.resets[kind] = at end
    end
end

---------------------------------------------------------------------------------------------------
-- Item names and classes
---------------------------------------------------------------------------------------------------
local function nameFromLink(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

local function qualityFromLink(link)
    local color = type(link) == "string" and link:match("|c(%x%x%x%x%x%x%x%x)")
    if not color or not ITEM_QUALITY_COLORS then return nil end
    for quality, c in pairs(ITEM_QUALITY_COLORS) do
        if c.hex and c.hex:lower():find(color:lower(), 1, true) then return quality end
    end
    return nil
end

-- Remembers what an item is called and what it is, from its link or the game's cache.
function ns.Items_Remember(itemID, link)
    if not itemID then return end
    local entry = ns.db.items[itemID]
    if entry and entry.n and entry.c then return end
    entry = entry or {}
    local name, _, quality = ns.ItemInfo(itemID)
    entry.n = entry.n or name or nameFromLink(link)
    entry.q = entry.q or quality or qualityFromLink(link)
    if not entry.c then
        local _, _, classID, subclassID = ns.ItemInstant(itemID)
        entry.c, entry.s = classID, subclassID
    end
    ns.db.items[itemID] = entry
end

function ns.Items_Name(itemID)
    local entry = ns.db.items[itemID]
    if entry and entry.n then return entry.n end
    local name = ns.ItemInfo(itemID)
    if name then
        ns.Items_Remember(itemID)
        return name
    end
    return ("item:%d"):format(itemID)
end

function ns.Items_Class(itemID)
    local entry = ns.db.items[itemID]
    if entry and entry.c then return entry.c, entry.s end
    local _, _, classID, subclassID = ns.ItemInstant(itemID)
    return classID, subclassID
end

function ns.Items_Icon(itemID)
    local _, icon = ns.ItemInstant(itemID)
    return icon or 134400 -- the question mark
end

function ns.Items_Quality(itemID)
    local entry = ns.db.items[itemID]
    if entry and entry.q then return entry.q end
    local _, _, quality = ns.ItemInfo(itemID)
    return quality
end

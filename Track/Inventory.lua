local _, ns = ...

-- What each character carries (bags), keeps in its bank (seen the last time at a banker), wears, and what the
-- guild banks and the account-wide bank hold. Each is saved as { [itemID] = count }:
--   rec.bags, rec.bank (rec.bankAt), rec.equipped; mail counts live in rec.mail.items (Track/Mail.lua)
--   db.guilds["Guild-Realm"] = { name =, realm =, faction =, money =, time =, tabs = { [i] = { name =, items = } } }
--   db.account = { items =, time = }  (the warband bank, on clients that have one)

local atBank, atGuildBank = false, false

local function itemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Counts what a list of bags holds; also whether any slot was read at all (a bank that isn't loaded reads as
-- bags without slots).
local function countBags(bagIDs)
    local counts, slots = {}, 0
    for _, bag in ipairs(bagIDs) do
        local n = ns.ContainerNumSlots(bag)
        slots = slots + n
        for slot = 1, n do
            local id, count, link = ns.ContainerItem(bag, slot)
            if id then
                counts[id] = (counts[id] or 0) + count
                ns.Items_Remember(id, link)
            end
        end
    end
    return counts, slots
end

function ns.Inventory_SaveBags()
    local rec = ns.Me()
    local counts, slots = countBags(ns.BagIDs())
    -- right after login the bags may not be loaded yet: an empty read doesn't replace a good copy
    if slots == 0 or (not next(counts) and rec.bags and next(rec.bags) and GetTime() - (ns.session.start or 0) < 10) then
        return
    end
    rec.bags = counts
    rec.bagsAt = ns.Now()
    -- free slots of the bags, for the summary
    local free, total = 0, 0
    for _, bag in ipairs(ns.BagIDs()) do
        local n = ns.ContainerNumSlots(bag)
        total = total + n
        if C_Container and C_Container.GetContainerNumFreeSlots then
            local ok, f = pcall(C_Container.GetContainerNumFreeSlots, bag)
            free = free + ((ok and ns.Num(f)) or 0)
        end
    end
    rec.bagSlots, rec.bagFree = total, free
end

function ns.Inventory_SaveBank()
    if not atBank then return end
    local rec = ns.Me()
    local counts, slots = countBags(ns.BankBagIDs())
    if slots > 0 then
        rec.bank = counts
        rec.bankAt = ns.Now()
    end
    local accountIDs = ns.AccountBankBagIDs()
    if #accountIDs > 0 then
        local accountCounts, accountSlots = countBags(accountIDs)
        if accountSlots > 0 then ns.db.account = { items = accountCounts, time = ns.Now() } end
    end
end

function ns.Inventory_SaveEquipped()
    if not GetInventoryItemID then return end
    local rec = ns.Me()
    local counts, gear = {}, {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            counts[id] = (counts[id] or 0) + 1
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
            ns.Items_Remember(id, link)
            -- the full link (enchant, random suffix, gems) for the paper doll's tooltips; the id when there is none
            gear[slot] = (type(link) == "string" and not ns.IsSecret(link)) and link or ("item:" .. id)
        end
    end
    rec.equipped = counts
    rec.gear = gear
end

---------------------------------------------------------------------------------------------------
-- Guild bank: every tab the character can see is asked for (the client only knows a tab's items once asked)
-- and read when its items arrive. A tab that reads as empty keeps the copy it had (its items may not have
-- arrived yet).
---------------------------------------------------------------------------------------------------
local function guildKey()
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil end
    return guild .. "-" .. ns.CurrentRealm(), guild
end

function ns.Inventory_SaveGuildBank()
    if not atGuildBank or not GetNumGuildBankTabs then return end
    local key, guild = guildKey()
    if not key then return end
    local entry = ns.db.guilds[key] or { name = guild, realm = ns.CurrentRealm(), tabs = {} }
    entry.faction = UnitFactionGroup("player")
    entry.money = ns.Num(GetGuildBankMoney and GetGuildBankMoney()) or entry.money
    entry.time = ns.Now()
    local perTab = MAX_GUILDBANK_SLOTS_PER_TAB or 98
    for tab = 1, ns.Num(GetNumGuildBankTabs()) or 0 do
        local name, icon, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            local counts = {}
            for slot = 1, perTab do
                local link = GetGuildBankItemLink(tab, slot)
                local id = itemIDFromLink(link)
                if id then
                    local _, count = GetGuildBankItemInfo(tab, slot)
                    counts[id] = (counts[id] or 0) + (ns.Num(count) or 1)
                    ns.Items_Remember(id, link)
                end
            end
            local old = entry.tabs[tab]
            if next(counts) or not old then
                entry.tabs[tab] = { name = name, icon = icon, items = counts }
            else
                old.name, old.icon = name, icon
            end
        end
    end
    ns.db.guilds[key] = entry
end

local function queryGuildTabs()
    if not (GetNumGuildBankTabs and QueryGuildBankTab) then return end
    for tab = 1, ns.Num(GetNumGuildBankTabs()) or 0 do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            C_Timer.After(tab * 0.3, function() if atGuildBank then pcall(QueryGuildBankTab, tab) end end)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Opening and closing the bank and the guild bank. The modern bank may never fire BANKFRAME_OPENED (Blizzard
-- opens it through the interaction manager), so every signal there is is listened to, and the bank window's own
-- show and hide too.
---------------------------------------------------------------------------------------------------
local function bankOpened()
    atBank = true
    C_Timer.After(0.5, function() ns.SafeCall(ns.Inventory_SaveBank) end)
end

local function bankClosed()
    if atBank then ns.SafeCall(ns.Inventory_SaveBank) end
    atBank = false
end

local function guildBankOpened()
    atGuildBank = true
    queryGuildTabs()
    C_Timer.After(1, function() ns.SafeCall(ns.Inventory_SaveGuildBank) end)
end

local function interactionType(name)
    return Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType[name]
end

local hookedBankFrame = false
local function hookBankFrame()
    local frame = _G.BankFrame
    if hookedBankFrame or not frame or not frame.HookScript then return end
    hookedBankFrame = true
    frame:HookScript("OnShow", bankOpened)
    frame:HookScript("OnHide", bankClosed)
end

function ns.Inventory_IsAtBank() return atBank end

function ns.Inventory_Init()
    ns.On("BAG_UPDATE_DELAYED", function()
        ns.Debounce("bags", 0.5, function()
            ns.Inventory_SaveBags()
            if atBank then ns.Inventory_SaveBank() end
            ns.Changed("items")
        end)
    end)
    ns.On("PLAYERBANKSLOTS_CHANGED", function() ns.Debounce("bank", 0.5, ns.Inventory_SaveBank) end)
    ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Debounce("equipped", 0.5, ns.Inventory_SaveEquipped) end)
    ns.On("BANKFRAME_OPENED", bankOpened)
    ns.On("BANKFRAME_CLOSED", bankClosed)
    ns.On("GUILDBANKFRAME_OPENED", guildBankOpened)
    ns.On("GUILDBANKFRAME_CLOSED", function()
        ns.SafeCall(ns.Inventory_SaveGuildBank)
        atGuildBank = false
    end)
    ns.On("GUILDBANKBAGSLOTS_CHANGED", function() ns.Debounce("guildbank", 0.5, ns.Inventory_SaveGuildBank) end)
    ns.On("GUILDBANK_UPDATE_MONEY", function() ns.Debounce("guildbank", 0.5, ns.Inventory_SaveGuildBank) end)
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
        if kind == nil then return end
        if kind == interactionType("Banker") or kind == interactionType("AccountBanker") then bankOpened() end
        if kind == interactionType("GuildBanker") then guildBankOpened() end
    end)
    ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
        if kind == nil then return end
        if kind == interactionType("Banker") or kind == interactionType("AccountBanker") then bankClosed() end
        if kind == interactionType("GuildBanker") then
            ns.SafeCall(ns.Inventory_SaveGuildBank)
            atGuildBank = false
        end
    end)
    ns.On("ADDON_LOADED", hookBankFrame)
    hookBankFrame()
end

---------------------------------------------------------------------------------------------------
-- Questions: who has an item, and finding items by name.
---------------------------------------------------------------------------------------------------
local function count(t, id) return (t and t[id]) or 0 end

-- { chars = { { key =, rec =, bags =, bank =, mail =, equipped =, total = } }, guilds = { { name =, count = } },
--   account =, total = } for one item; opts.faction limits the characters (and guilds) to that faction.
function ns.Inventory_Holders(itemID, opts)
    opts = opts or {}
    local result = { chars = {}, guilds = {}, account = 0, total = 0 }
    for key, rec in pairs(ns.db.chars) do
        if (not opts.faction or rec.faction == opts.faction) and (opts.includeMe ~= false or not ns.IsMe(key)) then
            local mailItems = rec.mail and rec.mail.items
            local row = {
                key = key, rec = rec,
                bags = count(rec.bags, itemID), bank = count(rec.bank, itemID),
                mail = count(mailItems, itemID), equipped = count(rec.equipped, itemID),
            }
            row.total = row.bags + row.bank + row.mail + row.equipped
            if row.total > 0 then
                result.chars[#result.chars + 1] = row
                result.total = result.total + row.total
            end
        end
    end
    table.sort(result.chars, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return (a.rec.name or "") < (b.rec.name or "")
    end)
    if opts.guilds ~= false then
        for _, guild in pairs(ns.db.guilds) do
            if not opts.faction or not guild.faction or guild.faction == opts.faction then
                local n = 0
                for _, tab in pairs(guild.tabs or {}) do n = n + count(tab.items, itemID) end
                if n > 0 then
                    result.guilds[#result.guilds + 1] = { name = guild.name, count = n }
                    result.total = result.total + n
                end
            end
        end
        table.sort(result.guilds, function(a, b) return a.name < b.name end)
    end
    result.account = count(ns.db.account and ns.db.account.items, itemID)
    result.total = result.total + result.account
    return result
end

-- Every item held anywhere whose name contains the text: { { id =, name =, total = } } by name.
function ns.Inventory_Search(text)
    text = (text or ""):lower()
    local ids = {}
    local function addAll(t) for id in pairs(t or {}) do ids[id] = true end end
    for _, rec in pairs(ns.db.chars) do
        addAll(rec.bags) addAll(rec.bank) addAll(rec.equipped)
        addAll(rec.mail and rec.mail.items)
    end
    for _, guild in pairs(ns.db.guilds) do
        for _, tab in pairs(guild.tabs or {}) do addAll(tab.items) end
    end
    addAll(ns.db.account and ns.db.account.items)
    local list = {}
    local wantedID = tonumber(text)
    for id in pairs(ids) do
        local name = ns.Items_Name(id)
        if text == "" or name:lower():find(text, 1, true) or id == wantedID then
            local holders = ns.Inventory_Holders(id)
            if holders.total > 0 then list[#list + 1] = { id = id, name = name, total = holders.total } end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- What a character carries of one class of items (consumables, ammo...): { { id =, count = } } by name.
function ns.Inventory_OfClass(rec, classID, subclassID)
    local list = {}
    for id, n in pairs(rec.bags or {}) do
        local c, s = ns.Items_Class(id)
        if c == classID and (subclassID == nil or s == subclassID) then list[#list + 1] = { id = id, count = n } end
    end
    table.sort(list, function(a, b) return ns.Items_Name(a.id) < ns.Items_Name(b.id) end)
    return list
end

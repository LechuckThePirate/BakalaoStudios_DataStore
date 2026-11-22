local _, ns = ...

-- What the playing character is: level, experience and rested experience, money (and its daily history), where it
-- is and where its hearthstone is bound, guild, item level, durability, played time (and per level), professions,
-- currencies and PvP rank. Saved in the character's record as things change, and all of it once more at logout.

local MAX_LEVEL_FALLBACK = 60
local GOLD_HISTORY_DAYS = 120

local session = { start = nil, xpGained = 0, moneyAtLogin = nil }
ns.session = session

function ns.MaxLevel()
    local f = GetMaxPlayerLevel or (GetMaxLevelForPlayerExpansion)
    if f then
        local ok, level = pcall(f)
        level = ok and ns.Num(level)
        if level and level > 0 then return level end
    end
    return MAX_PLAYER_LEVEL or MAX_LEVEL_FALLBACK
end

---------------------------------------------------------------------------------------------------
-- Experience
---------------------------------------------------------------------------------------------------
-- Whether a level is the top one. The retail engine may answer the retail level cap, so the game's own "at max
-- level" counts too, and an empty XP bar from level 60 up.
function ns.IsMaxLevel(level, xpMax)
    if not level or level <= 0 then return false end
    if level >= ns.MaxLevel() then return true end
    if IsLevelAtEffectiveMaxLevel then
        local ok, answer = pcall(IsLevelAtEffectiveMaxLevel, level)
        if ok and answer then return true end
    end
    return level >= MAX_LEVEL_FALLBACK and xpMax == 0
end

-- The XP bar is only trusted when the game gives a level and a bar: while logging out it answers zeros, which would
-- turn every character into a max level one with no rested experience.
local function saveXP(rec)
    local level = ns.Num(UnitLevel("player"))
    local xp, xpMax = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player"))
    if not level or level <= 0 then return end
    rec.level = level
    rec.maxLevel = ns.IsMaxLevel(level, xpMax)
    if xp and xpMax and xpMax > 0 then
        if session.lastXP and session.lastLevel == rec.level and xp > session.lastXP then
            session.xpGained = session.xpGained + (xp - session.lastXP)
        end
        session.lastXP, session.lastLevel = xp, rec.level
        rec.xp, rec.xpMax = xp, xpMax
        rec.rested = ns.Num(GetXPExhaustion and GetXPExhaustion()) or 0
    end
    rec.resting = IsResting and IsResting() and true or false
    rec.restedAt = ns.Now()
end

-- At logout only what can be trusted then: when and where (resting or not) the character stops, which the rested
-- experience of the coming days depends on. Money, experience, bags... were saved while playing.
function ns.Character_SaveLogout()
    local rec = ns.Me()
    rec.lastSeen = ns.Now()
    rec.restedAt = ns.Now()
    if IsResting then rec.resting = IsResting() and true or false end
end

-- Mends records saved by 0.1.0 at logout, when the game answered zeros: a low level marked as max level, an empty
-- XP bar, no money (the last money of the history that wasn't zero comes back).
function ns.Character_Repair(rec)
    if rec.maxLevel and rec.level and rec.level < MAX_LEVEL_FALLBACK then rec.maxLevel = false end
    if rec.xpMax == 0 then rec.xp, rec.xpMax = nil, nil end
    if rec.money == 0 and rec.goldHistory then
        local bestDay, best
        for day, money in pairs(rec.goldHistory) do
            if money > 0 and (not bestDay or day > bestDay) then bestDay, best = day, money end
        end
        if best then
            rec.money = best
            for day, money in pairs(rec.goldHistory) do
                if money == 0 and day > bestDay then rec.goldHistory[day] = best end
            end
        end
    end
end

-- Experience per hour of this session, and the time to the next level at that pace.
function ns.Session_XPRate()
    if not session.start then return nil end
    local elapsed = GetTime() - session.start
    if elapsed < 300 or session.xpGained <= 0 then return nil end
    return session.xpGained / elapsed * 3600
end

function ns.Session_TimeToLevel(rec)
    local rate = ns.Session_XPRate()
    if not rate or not rec.xp or not rec.xpMax then return nil end
    return (rec.xpMax - rec.xp) / rate * 3600
end

---------------------------------------------------------------------------------------------------
-- Money and its history: one value per calendar day (the last of the day), kept for GOLD_HISTORY_DAYS.
---------------------------------------------------------------------------------------------------
local function saveMoney(rec)
    local money = ns.Num(GetMoney())
    if not money then return end
    rec.money = money
    session.moneyAtLogin = session.moneyAtLogin or money
    rec.goldHistory = rec.goldHistory or {}
    rec.goldHistory[ns.DayKey()] = money
    ns.Gold_Prune(rec)
end

function ns.Gold_Prune(rec)
    local oldest = ns.DayKey(ns.Now() - GOLD_HISTORY_DAYS * 86400)
    for day in pairs(rec.goldHistory or {}) do
        if day < oldest then rec.goldHistory[day] = nil end
    end
end

-- The money a character had at the end of a day: that day's value or the last one before it.
function ns.Gold_OnDay(rec, day)
    local best, bestDay
    for d, money in pairs(rec.goldHistory or {}) do
        if d <= day and (not bestDay or d > bestDay) then best, bestDay = money, d end
    end
    return best
end

-- The account's total per day, oldest first: { { day =, total = } } over `days` days ending today.
function ns.Gold_History(chars, days, now)
    now = now or ns.Now()
    local list = {}
    for i = days - 1, 0, -1 do
        local day = ns.DayKey(now - i * 86400)
        local total = 0
        for _, c in ipairs(chars) do total = total + (ns.Gold_OnDay(c.rec, day) or 0) end
        list[#list + 1] = { day = day, total = total }
    end
    return list
end

function ns.Session_MoneyChange()
    local rec = ns.Me()
    if not session.moneyAtLogin or not rec.money then return 0 end
    return rec.money - session.moneyAtLogin
end

---------------------------------------------------------------------------------------------------
-- Where, guild, gear
---------------------------------------------------------------------------------------------------
local function saveZone(rec)
    rec.zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or rec.zone
    rec.subzone = GetSubZoneText and GetSubZoneText() or nil
    if rec.subzone == "" then rec.subzone = nil end
    rec.bind = GetBindLocation and GetBindLocation() or rec.bind
end

local function saveGuild(rec)
    if not GetGuildInfo then return end
    local guild, rank = GetGuildInfo("player")
    if guild then
        rec.guild, rec.guildRank = guild, rank
    elseif IsInGuild and not IsInGuild() then
        rec.guild, rec.guildRank = nil, nil
    end
end

local function saveGear(rec)
    if GetAverageItemLevel then
        local ok, overall, equipped = pcall(GetAverageItemLevel)
        equipped = ok and (ns.Num(equipped) or ns.Num(overall))
        if equipped and equipped > 0 then rec.ilvl = math.floor(equipped * 10 + 0.5) / 10 end
    end
    if GetInventoryItemDurability then
        local lowest, sumCur, sumMax = nil, 0, 0
        for slot = 1, 19 do
            local cur, max = GetInventoryItemDurability(slot)
            cur, max = ns.Num(cur), ns.Num(max)
            if cur and max and max > 0 then
                local pct = cur / max
                if not lowest or pct < lowest then lowest = pct end
                sumCur, sumMax = sumCur + cur, sumMax + max
            end
        end
        rec.durability = lowest
        rec.durabilityAvg = sumMax > 0 and sumCur / sumMax or nil
    end
end

local function saveRepair(rec)
    if not (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost) then return end
    local cost = ns.Num(GetRepairAllCost())
    if cost then rec.repairCost, rec.repairAt = cost, ns.Now() end
end

---------------------------------------------------------------------------------------------------
-- Played time: asked once at login (the game's two chat lines are kept out), then followed with GetTime.
-- rec.levels[L] = the played time when the character reached level L (from the levels seen with the addon).
---------------------------------------------------------------------------------------------------
local hiddenFrames
local function hidePlayedLines()
    hiddenFrames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            hiddenFrames[#hiddenFrames + 1] = frame
        end
    end
end

local function showPlayedLines()
    for _, frame in ipairs(hiddenFrames or {}) do frame:RegisterEvent("TIME_PLAYED_MSG") end
    hiddenFrames = nil
end

function ns.RequestPlayed()
    if not RequestTimePlayed then return end
    hidePlayedLines()
    RequestTimePlayed()
    C_Timer.After(10, showPlayedLines) -- an answer that never comes doesn't keep the lines away
end

local function onPlayed(_, total, levelTime)
    showPlayedLines()
    total, levelTime = ns.Num(total), ns.Num(levelTime)
    if not total then return end
    local rec = ns.Me()
    rec.played, rec.playedLevel, rec.playedAt = total, levelTime, ns.Now()
    rec.levels = rec.levels or {}
    if levelTime and rec.level and not rec.levels[rec.level] then rec.levels[rec.level] = total - levelTime end
end

-- The played time now: the last answer plus the time since.
function ns.PlayedNow(rec)
    if not rec.played then return nil end
    if rec == ns.Me() and rec.playedAt then return rec.played + (ns.Now() - rec.playedAt) end
    return rec.played
end

local function onLevelUp(_, newLevel)
    local rec = ns.Me()
    newLevel = ns.Num(newLevel)
    if not newLevel then return end
    rec.levels = rec.levels or {}
    local played = ns.PlayedNow(rec)
    if played then rec.levels[newLevel] = played end
    rec.level = newLevel
    if rec.playedAt then rec.playedLevel = 0 end
    session.lastXP = 0
    session.lastLevel = newLevel
end

-- { { level =, seconds = } } the time each level took, from the levels reached with the addon.
function ns.LevelTimes(rec)
    local list = {}
    for level, at in pairs(rec.levels or {}) do
        local nextAt = rec.levels[level + 1]
        if nextAt and nextAt >= at then list[#list + 1] = { level = level, seconds = nextAt - at } end
    end
    table.sort(list, function(a, b) return a.level > b.level end)
    return list
end

---------------------------------------------------------------------------------------------------
-- Professions, currencies, PvP
---------------------------------------------------------------------------------------------------
local function saveProfessions(rec)
    if not (GetProfessions and GetProfessionInfo) then return end
    local indices = { GetProfessions() }
    local list = {}
    for slot = 1, 6 do
        local index = indices[slot]
        if index then
            local ok, name, icon, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, index)
            if ok and name then
                list[#list + 1] = { name = name, icon = icon, rank = ns.Num(rank), max = ns.Num(maxRank),
                    skillLine = skillLine, primary = slot <= 2, slot = slot }
            end
        end
    end
    -- right after login the list can still be empty: an empty answer doesn't replace a good one
    if #list > 0 or not rec.professions then rec.professions = list end
end

local function saveCurrencies(rec)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo) then return end
    local ok, size = pcall(C_CurrencyInfo.GetCurrencyListSize)
    if not ok or not ns.Num(size) then return end
    local list = {}
    for i = 1, size do
        local okInfo, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        if okInfo and type(info) == "table" and not info.isHeader and info.name then
            local qty = ns.Num(info.quantity)
            if qty and qty > 0 then list[#list + 1] = { name = info.name, qty = qty, icon = info.iconFileID } end
        end
    end
    rec.currencies = list
end

local function savePvP(rec)
    local pvp = rec.pvp or {}
    if UnitPVPRank and GetPVPRankInfo then
        local ok, rank = pcall(UnitPVPRank, "player")
        rank = ok and ns.Num(rank)
        if rank then
            pvp.rank = rank
            local okName, name = pcall(GetPVPRankInfo, rank)
            pvp.rankName = okName and name or nil
        end
    end
    if GetPVPThisWeekStats then
        local ok, hk, honor = pcall(GetPVPThisWeekStats)
        if ok then pvp.weekHK, pvp.weekHonor = ns.Num(hk), ns.Num(honor) end
    end
    if GetPVPLifetimeStats then
        local ok, hk = pcall(GetPVPLifetimeStats)
        if ok then pvp.lifetimeHK = ns.Num(hk) end
    end
    if next(pvp) then rec.pvp = pvp end
end

---------------------------------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------------------------------
function ns.Character_SaveBasics()
    local rec = ns.Me()
    local _, class = UnitClass("player")
    local localClass = UnitClass("player")
    local race, raceFile = UnitRace("player")
    rec.name = ns.PlayerName()
    if ns.RealmName() ~= "" then rec.realm = ns.RealmName() end -- (none since late November 2026: keep the one it had)
    rec.class, rec.classLocal = class, localClass
    rec.race, rec.raceFile = race, raceFile
    rec.faction = UnitFactionGroup("player")
    rec.sex = UnitSex and UnitSex("player") or nil
    rec.lastSeen = ns.Now()
end

function ns.Character_SaveAll()
    local rec = ns.Me()
    ns.Character_SaveBasics()
    ns.SafeCall(saveXP, rec)
    ns.SafeCall(saveMoney, rec)
    ns.SafeCall(saveZone, rec)
    ns.SafeCall(saveGuild, rec)
    ns.SafeCall(saveGear, rec)
    ns.SafeCall(saveProfessions, rec)
    ns.SafeCall(saveCurrencies, rec)
    ns.SafeCall(savePvP, rec)
end

local function refresh()
    ns.Changed("character")
end

function ns.Character_Init()
    session.start = GetTime()
    ns.On("PLAYER_XP_UPDATE", function() saveXP(ns.Me()) refresh() end)
    ns.On("UPDATE_EXHAUSTION", function() saveXP(ns.Me()) end)
    ns.On("PLAYER_UPDATE_RESTING", function() saveXP(ns.Me()) end)
    ns.On("PLAYER_LEVEL_UP", function(...) onLevelUp(...) saveXP(ns.Me()) refresh() end)
    ns.On("PLAYER_MONEY", function() saveMoney(ns.Me()) ns.Changed("money") end)
    ns.On("ZONE_CHANGED_NEW_AREA", function() saveZone(ns.Me()) end)
    ns.On("ZONE_CHANGED", function() saveZone(ns.Me()) end)
    ns.On("HEARTHSTONE_BOUND", function() saveZone(ns.Me()) end)
    ns.On("PLAYER_GUILD_UPDATE", function() saveGuild(ns.Me()) end)
    ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Debounce("gear", 1, function() saveGear(ns.Me()) end) end)
    ns.On("UPDATE_INVENTORY_DURABILITY", function() ns.Debounce("gear", 1, function() saveGear(ns.Me()) end) end)
    ns.On("MERCHANT_SHOW", function() saveRepair(ns.Me()) end)
    ns.On("TIME_PLAYED_MSG", onPlayed)
    ns.On("SKILL_LINES_CHANGED", function() ns.Debounce("professions", 1, function() saveProfessions(ns.Me()) end) end)
    ns.On("CURRENCY_DISPLAY_UPDATE", function() ns.Debounce("currencies", 2, function() saveCurrencies(ns.Me()) end) end)
    ns.On("PLAYER_PVP_KILLS_CHANGED", function() ns.Debounce("pvp", 2, function() savePvP(ns.Me()) end) end)
    ns.On("PLAYER_PVP_RANK_CHANGED", function() savePvP(ns.Me()) end)
end

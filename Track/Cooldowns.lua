local _, ns = ...

-- Long profession cooldowns (transmutes, Mooncloth, the Salt Shaker) and the hearthstone, per character:
--   rec.cooldowns[key] = { name =, icon =, readyAt = (nil when ready), alert = true/false }
-- The game answers with GetTime()-based start and duration; they are turned into time() so they still mean
-- something once the character logs out.

-- Spells that share one cooldown are one entry (every transmute shares the alchemist's).
ns.COOLDOWN_SPELLS = {
    { key = "transmute", name = "Transmute", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564,
        17565, 17566, 25146 } },
    { key = "mooncloth", spells = { 18560 } },
}
ns.COOLDOWN_ITEMS = {
    { key = "saltshaker", item = 15846 },
    { key = "hearthstone", item = 6948, alert = false },
}

local function itemCount(itemID)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, itemID)
    return ok and ns.Num(n) or 0
end

function ns.Cooldowns_Scan()
    local rec = ns.Me()
    local list = {}
    for _, def in ipairs(ns.COOLDOWN_SPELLS) do
        for _, spellID in ipairs(def.spells) do
            if ns.KnowsSpell(spellID) then
                local start, duration = ns.SpellCooldown(spellID)
                local name = def.name and ns.L[def.name] or ns.SpellName(spellID) or def.key
                list[def.key] = { name = name, icon = ns.SpellIcon(spellID), readyAt = ns.CooldownReadyAt(start, duration),
                    alert = def.alert ~= false }
                break
            end
        end
    end
    for _, def in ipairs(ns.COOLDOWN_ITEMS) do
        if itemCount(def.item) > 0 then
            local start, duration = ns.ItemCooldown(def.item)
            list[def.key] = { name = ns.Items_Name(def.item), icon = ns.Items_Icon(def.item),
                readyAt = ns.CooldownReadyAt(start, duration), alert = def.alert ~= false }
        end
    end
    -- keeps what was noted as announced (Notify.lua)
    for key, entry in pairs(list) do
        local old = rec.cooldowns and rec.cooldowns[key]
        if old and old.readyAt == entry.readyAt then entry.announced = old.announced end
    end
    rec.cooldowns = list
    ns.Changed("cooldowns")
end

-- Every cooldown of the characters listed: { { key =, rec =, cd =, id = } } soonest first (ready ones first).
function ns.Cooldowns_All(chars, alertOnly)
    local list = {}
    for _, c in ipairs(chars or ns.Chars()) do
        for id, cd in pairs(c.rec.cooldowns or {}) do
            if not alertOnly or cd.alert then list[#list + 1] = { key = c.key, rec = c.rec, cd = cd, id = id } end
        end
    end
    table.sort(list, function(a, b)
        local ra, rb = a.cd.readyAt or 0, b.cd.readyAt or 0
        if ra ~= rb then return ra < rb end
        return (a.rec.name or "") < (b.rec.name or "")
    end)
    return list
end

function ns.Cooldowns_IsReady(cd, now)
    return cd.readyAt == nil or cd.readyAt <= (now or ns.Now())
end

function ns.Cooldowns_Init()
    ns.On("SPELL_UPDATE_COOLDOWN", function() ns.Debounce("cooldowns", 2, ns.Cooldowns_Scan) end)
    ns.On("BAG_UPDATE_COOLDOWN", function() ns.Debounce("cooldowns", 2, ns.Cooldowns_Scan) end)
    ns.On("TRADE_SKILL_LIST_UPDATE", function() ns.Debounce("cooldowns", 2, ns.Cooldowns_Scan) end)
end

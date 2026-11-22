local ADDON, ns = ...

-- Entry point: loaded last. On load the saved variables are prepared and the trackers start listening; on entering
-- the world the playing character is saved whole, and a few seconds later the game is asked for what it answers by
-- event (lockouts, played time). At logout only what can be trusted then is saved (the rest was saved while playing:
-- the game answers zeros while logging out).

function ns.Version()
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Saves everything about the playing character that can be read at any time.
function ns.SaveAll()
    ns.Character_SaveAll()
    ns.SafeCall(ns.Inventory_SaveBags)
    ns.SafeCall(ns.Inventory_SaveEquipped)
    ns.SafeCall(ns.Cooldowns_Scan)
    ns.SafeCall(ns.Reputation_Scan)
    ns.SafeCall(ns.Attunements_Scan)
    ns.SafeCall(ns.Resets_Save)
end

local started = false
local function onEnterWorld()
    ns.SaveAll()
    ns.Changed("character")
    if started then return end
    started = true
    C_Timer.After(3, function()
        if RequestRaidInfo then RequestRaidInfo() end
        if ns.settings.autoPlayed then ns.RequestPlayed() end
    end)
    C_Timer.After(6, function()
        ns.SafeCall(ns.SaveAll)
        ns.Changed("character")
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ns.InitDB()
        ns.DB_MergeRealmless()
        for _, rec in pairs(ns.db.chars) do ns.Character_Repair(rec) end
        ns.Character_Init()
        ns.Inventory_Init()
        ns.Mail_Init()
        ns.Cooldowns_Init()
        ns.Lockouts_Init()
        ns.Reputation_Init()
        ns.Attunements_Init()
    elseif event == "PLAYER_ENTERING_WORLD" and ns.db then
        ns.SafeCall(onEnterWorld)
    elseif event == "PLAYER_LOGOUT" and ns.db then
        ns.SafeCall(ns.Character_SaveLogout)
    end
end)

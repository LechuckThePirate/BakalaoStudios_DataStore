local _, ns = ...

-- Raid and dungeon lockouts, per character, from the game's saved instances:
--   rec.lockouts = { { name =, id =, resetAt =, difficulty =, isRaid =, players =, killed =, bosses =, extended = } }
-- A lockout whose reset has passed is gone, whatever the copy says.

function ns.Lockouts_Scan()
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
    local list = {}
    local now = ns.Now()
    for i = 1, ns.Num(GetNumSavedInstances()) or 0 do
        local name, id, reset, _, locked, extended, _, isRaid, players, difficultyName, bosses, killed =
            GetSavedInstanceInfo(i)
        reset = ns.Num(reset)
        if name and reset and reset > 0 and (locked or extended) then
            list[#list + 1] = {
                name = name, id = id, resetAt = now + reset, isRaid = isRaid and true or false,
                players = ns.Num(players), difficulty = difficultyName, bosses = ns.Num(bosses),
                killed = ns.Num(killed), extended = extended and true or nil,
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    ns.Me().lockouts = list
end

-- The lockouts of a character still running.
function ns.Lockouts_Active(rec, now)
    now = now or ns.Now()
    local list = {}
    for _, l in ipairs(rec.lockouts or {}) do
        if l.resetAt and l.resetAt > now then list[#list + 1] = l end
    end
    return list
end

-- The names of every instance any character listed is saved to (raids first), for the columns of the window.
function ns.Lockouts_Instances(chars, now)
    local seen, list = {}, {}
    for _, c in ipairs(chars) do
        for _, l in ipairs(ns.Lockouts_Active(c.rec, now)) do
            if not seen[l.name] then
                seen[l.name] = true
                list[#list + 1] = { name = l.name, isRaid = l.isRaid }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isRaid ~= b.isRaid then return a.isRaid end
        return a.name < b.name
    end)
    return list
end

function ns.Lockouts_Find(rec, instanceName, now)
    for _, l in ipairs(ns.Lockouts_Active(rec, now)) do
        if l.name == instanceName then return l end
    end
    return nil
end

function ns.Lockouts_Init()
    ns.On("UPDATE_INSTANCE_INFO", function() ns.Debounce("lockouts", 0.5, function()
        ns.Lockouts_Scan()
        ns.Changed("lockouts")
    end) end)
    ns.On("BOSS_KILL", function() C_Timer.After(3, function() if RequestRaidInfo then RequestRaidInfo() end end) end)
    ns.On("ENCOUNTER_END", function() C_Timer.After(3, function() if RequestRaidInfo then RequestRaidInfo() end end) end)
end

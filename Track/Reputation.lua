local _, ns = ...

-- Reputations, per character: rec.reps[factionID] = { name =, standing = 1..8, cur =, max = }.
-- Every faction of the reputation window is read (the folded headers' ones too, when the client allows asking by
-- id), and the factions in KEY_FACTIONS are always asked by id, so they show up even under a folded header.

-- Factions of Classic content worth comparing between characters (ids are the same on every client).
ns.KEY_FACTIONS = {
    529,  -- Argent Dawn
    576,  -- Timbermaw Hold
    609,  -- Cenarion Circle
    59,   -- Thorium Brotherhood
    749,  -- Hydraxian Waterlords
    910,  -- Brood of Nozdormu
    270,  -- Zandalar Tribe
    809,  -- Shen'dralar
    909,  -- Darkmoon Faire
    87,   -- Bloodsail Buccaneers
    21,   -- Booty Bay
    369,  -- Gadgetzan
    470,  -- Ratchet
    577,  -- Everlook
    349,  -- Ravenholdt
    589,  -- Wintersaber Trainers
    72, 47, 69, 54, 930, -- Stormwind, Ironforge, Darnassus, Gnomeregan, Exodar
    76, 81, 68, 530, 911, -- Orgrimmar, Thunder Bluff, Undercity, Darkspear Trolls, Silvermoon
    730, 890, 509, -- Stormpike Guard, Silverwing Sentinels, League of Arathor
    729, 889, 510, -- Frostwolf Clan, Warsong Outriders, The Defilers
}

local function store(reps, f)
    if not f or not f.name or (f.isHeader and not f.hasRep) or not f.standing then return end
    local id = f.id or f.name
    reps[id] = { name = f.name, standing = f.standing, cur = f.cur, max = f.max }
end

function ns.Reputation_Scan()
    local reps = {}
    for i = 1, ns.FactionCount() do store(reps, ns.FactionByIndex(i)) end
    for _, id in ipairs(ns.KEY_FACTIONS) do
        if not reps[id] then
            local f = ns.FactionByID(id)
            -- an unknown faction reads as Neutral 0/0 on some clients: only kept when there is something in it
            if f and f.name and f.standing and (f.standing ~= 4 or (f.cur or 0) > 0) then store(reps, f) end
        end
    end
    if next(reps) then
        ns.Me().reps = reps
        ns.Changed("reputation")
    end
end

-- Every faction any of the characters has: { { id =, name = } } by name.
function ns.Reputation_Factions(chars)
    local seen, list = {}, {}
    for _, c in ipairs(chars) do
        for id, r in pairs(c.rec.reps or {}) do
            if not seen[id] then
                seen[id] = true
                list[#list + 1] = { id = id, name = r.name }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- A comparable value of a standing (for sorting): standing * 100000 + progress.
function ns.Reputation_Value(r)
    if not r then return -1 end
    return (r.standing or 0) * 100000 + (r.cur or 0)
end

function ns.Reputation_Init()
    ns.On("UPDATE_FACTION", function() ns.Debounce("reputation", 2, ns.Reputation_Scan) end)
end

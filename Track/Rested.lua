local _, ns = ...

-- Rested experience of a character that isn't playing, worked out from what it had when it was last saved: it
-- grows 5% of the level's bar every 8 hours in an inn or a city (a quarter of that anywhere else) up to a level
-- and a half (150% of the bar).
local RATE_RESTING = 0.05 / (8 * 3600) -- share of the bar per second
local OUTSIDE_FACTOR = 0.25
local CAP = 1.5

-- rested (experience points), share of the bar (0..1.5) and the seconds until it is full; nil at max level or
-- with nothing known.
function ns.Rested_Project(rec, now)
    if not rec or rec.maxLevel or not rec.xpMax or rec.xpMax <= 0 then return nil end
    now = now or ns.Now()
    local rested = rec.rested or 0
    local cap = rec.xpMax * CAP
    if rec.restedAt then
        local rate = rec.xpMax * RATE_RESTING * (rec.resting and 1 or OUTSIDE_FACTOR)
        rested = rested + math.max(0, now - rec.restedAt) * rate
    end
    rested = math.min(rested, cap)
    local share = rested / rec.xpMax
    local untilFull
    if rested < cap then
        local rate = rec.xpMax * RATE_RESTING * (rec.resting and 1 or OUTSIDE_FACTOR)
        untilFull = (cap - rested) / rate
    else
        untilFull = 0
    end
    return math.floor(rested), share, untilFull
end

-- The record of the character playing is live: no projection.
function ns.Rested_ForKey(key, now)
    local rec = ns.GetChar(key)
    if not rec then return nil end
    if ns.IsMe(key) then
        if rec.maxLevel or not rec.xpMax or rec.xpMax <= 0 then return nil end
        local rested = math.min(rec.rested or 0, rec.xpMax * CAP)
        local rate = rec.xpMax * RATE_RESTING * (rec.resting and 1 or OUTSIDE_FACTOR)
        return rested, rested / rec.xpMax, math.max(0, (rec.xpMax * CAP - rested) / rate)
    end
    return ns.Rested_Project(rec, now)
end

function ns.Rested_IsFull(key, now)
    local _, share = ns.Rested_ForKey(key, now)
    return share ~= nil and share >= CAP - 0.001
end

ns.RESTED_CAP = CAP

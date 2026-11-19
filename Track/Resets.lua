local _, ns = ...

-- The daily and weekly resets of the server, learned while playing (db.resets = { daily =, weekly = }: the next
-- one of each) and moved forward a day / a week at a time while the account is away.
local DAY, WEEK = 86400, 7 * 86400

function ns.Resets_Save()
    ns.db.resets.daily = ns.NextDailyReset() or ns.db.resets.daily
    ns.db.resets.weekly = ns.NextWeeklyReset() or ns.db.resets.weekly
end

-- The last reset of that kind ("daily" or "weekly") before `now`, or nil when it was never learned.
function ns.Resets_Last(kind, now)
    now = now or ns.Now()
    local nextAt = ns.db.resets[kind]
    local period = kind == "weekly" and WEEK or DAY
    if not nextAt then return nil end
    while nextAt <= now do nextAt = nextAt + period end
    while nextAt - period > now do nextAt = nextAt - period end
    return nextAt - period
end

-- The next reset of that kind after `now`.
function ns.Resets_Next(kind, now)
    local last = ns.Resets_Last(kind, now)
    if not last then return nil end
    return last + (kind == "weekly" and WEEK or DAY)
end

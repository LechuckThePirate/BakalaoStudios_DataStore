local _, ns = ...

-- Small helpers every module uses: printing, the event dispatcher, safe calls, debouncing, secret values, time, and
-- the callbacks the addons using the store register to hear about changes.

function ns.Print(...)
    print("|cffd94fb0BakalaoStudios DataStore|r:", ...)
end

-- "Secret values": Forever (like Retail 12.x) hides some numbers from addons. A secret can be handed to a widget
-- but comparing it or doing arithmetic with it is a Lua error, so every value read from the game that is compared
-- or saved goes through this first.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A number from the game, or nil when it is missing or hidden.
function ns.Num(value)
    if value == nil or ns.IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

-- Runs f; an error is shown the game's way (the error frame, BugSack...) but doesn't stop the caller, so a client
-- that lacks one API only loses that one piece of information.
function ns.SafeCall(f, ...)
    local handler = geterrorhandler and geterrorhandler() or print
    return xpcall(f, handler, ...)
end

---------------------------------------------------------------------------------------------------
-- Events: every module registers through ns.On; one frame dispatches them. An event the client doesn't know is
-- skipped (registering an unknown event is an error on some clients).
---------------------------------------------------------------------------------------------------
local handlers = {}
local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        ns.SafeCall(fn, event, ...)
    end
end)

function ns.On(event, fn)
    if not handlers[event] then
        if not pcall(dispatcher.RegisterEvent, dispatcher, event) then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

-- Calls fn once, `delay` seconds after the last of a burst of calls with the same id.
local pending = {}
function ns.Debounce(id, delay, fn)
    if pending[id] then return end
    pending[id] = true
    C_Timer.After(delay, function()
        pending[id] = nil
        ns.SafeCall(fn)
    end)
end

---------------------------------------------------------------------------------------------------
-- Callbacks for the addons using the store: fn(kind, key, ...) after something about a character changed.
-- Kinds: "character" (level, XP, rested, zone, gear, played...), "money", "items" (bags, bank, worn, guild and
-- account banks), "mail" (a mailbox read), "mailSent" (key = the receiver, then { [itemID] = count }), "cooldowns",
-- "lockouts", "reputation", "quests", "forget".
---------------------------------------------------------------------------------------------------
local callbacks = {}

function ns.RegisterCallback(fn)
    if type(fn) ~= "function" then return nil end
    callbacks[#callbacks + 1] = fn
    return #callbacks
end

function ns.Changed(kind, key, ...)
    key = key or (ns.MyKey and ns.MyKey())
    for _, fn in ipairs(callbacks) do ns.SafeCall(fn, kind, key, ...) end
end

---------------------------------------------------------------------------------------------------
-- Tables and time
---------------------------------------------------------------------------------------------------
function ns.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = ns.Copy(v) end
    return copy
end

function ns.Now()
    return time()
end

-- The local calendar day of a time, as "2026-11-18" (sorts as text).
function ns.DayKey(t)
    return date("%Y-%m-%d", t or ns.Now())
end

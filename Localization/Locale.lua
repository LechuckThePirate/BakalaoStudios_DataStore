local _, ns = ...

-- The few texts the store hands out (names of cooldowns and standings when the game has none). Keys are the English
-- text; on esES/esMX clients they are replaced by the Spanish one (a test checks every key has one).
local es = {
    ["Transmute"] = "Transmutación",
    ["Hated"] = "Odiado",
    ["Hostile"] = "Hostil",
    ["Unfriendly"] = "Adverso",
    ["Neutral"] = "Neutral",
    ["Friendly"] = "Amistoso",
    ["Honored"] = "Honorable",
    ["Revered"] = "Venerado",
    ["Exalted"] = "Exaltado",
}

local locale = GetLocale and GetLocale() or "enUS"
local active = (locale == "esES" or locale == "esMX") and es or {}

-- English text is the key: a missing translation shows the English one.
ns.L = setmetatable({}, { __index = function(_, key) return active[key] or key end })
ns.L_ES = es -- for the tests

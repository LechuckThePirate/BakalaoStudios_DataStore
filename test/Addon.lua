-- Loading the addon in tests: the files in TOC order (like the game), each with (name, ns). LoadAddon() loads
-- everything; StartAddon(ns, db) simulates entering the game with those saved variables.

function TocFiles(toc, dir)
    local files = {}
    dir = dir or ""
    for line in io.lines(dir .. (toc or "BakalaoStudios_DataStore.toc")) do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^##") and line:match("%.lua$") then
            files[#files + 1] = dir .. (line:gsub("\\", "/"))
        end
    end
    return files
end

function LoadAddon()
    local ns = {}
    for _, f in ipairs(TocFiles()) do
        local chunk = assert(loadfile(f))
        chunk("BakalaoStudios_DataStore", ns)
    end
    return ns
end

-- Every frame that registered the event and has an OnEvent receives it (as if the game fired it).
function FireEvent(event, ...)
    for _, f in ipairs(WowMock.frames) do
        local handler = f._scripts.OnEvent
        if handler and f._events and f._events[event] then handler(f, event, ...) end
    end
end

function StartAddon(ns, db)
    BakalaoDataStoreDB = db
    FireEvent("ADDON_LOADED", "BakalaoStudios_DataStore")
    FireEvent("PLAYER_ENTERING_WORLD")
    return ns
end

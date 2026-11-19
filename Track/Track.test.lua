dofile("setupTests.lua")

-- The trackers and the questions asked of the saved data: the character, rested experience, gold history, items,
-- mail, cooldowns, lockouts, reputations, quests and resets; the callbacks, the import and the public API.

local NOW = 1800000000
local ns

local function start(db)
    WowMock.Reset()
    ns = LoadAddon()
    StartAddon(ns, db or {})
    return ns
end

describe("the playing character", function()
    it("is saved when entering the world", function()
        start()
        local rec = BakalaoDataStoreDB.chars["Tester-Realm"]
        assert.are.equal("ROGUE", rec.class)
        assert.are.equal(20, rec.level)
        assert.are.equal(123456, rec.money)
        assert.are.equal(200, rec.rested)
        assert.are.equal("Goldshire", rec.bind)
        assert.are.equal(123456, rec.goldHistory[ns.DayKey()])
        assert.is_true(WowMock.raidInfoRequested)
        assert.is_true(WowMock.playedRequested)
    end)

    it("doesn't ask the played time when told not to", function()
        start({ settings = { autoPlayed = false } })
        assert.is_nil(WowMock.playedRequested)
    end)

    it("keeps what was saved while playing when logging out answers zeros", function()
        start()
        WowMock.char.money, WowMock.char.xp, WowMock.char.xpMax, WowMock.char.rested = 0, 0, 0, nil
        WowMock.char.resting = false
        WowMock.now = NOW + 100
        FireEvent("PLAYER_LOGOUT")
        local rec = ns.Me()
        assert.are.equal(123456, rec.money)
        assert.are.equal(1000, rec.xpMax)
        assert.are.equal(200, rec.rested)
        assert.is_false(rec.maxLevel)
        assert.is_false(rec.resting)
        assert.are.equal(NOW + 100, rec.lastSeen)
    end)

    it("saves the played time and the level reached", function()
        start()
        FireEvent("TIME_PLAYED_MSG", 100000, 2000)
        local rec = ns.Me()
        assert.are.equal(98000, rec.levels[20])
        WowMock.now = NOW + 500
        FireEvent("PLAYER_LEVEL_UP", 21)
        assert.are.equal(100500, rec.levels[21])
        assert.are.equal(2500, ns.LevelTimes(rec)[1].seconds)
    end)

    it("never takes a level under 60 for the top one", function()
        start()
        assert.is_false(ns.IsMaxLevel(26, 0))
        assert.is_true(ns.IsMaxLevel(60, 0))
    end)

    it("leaves secret values alone", function()
        start()
        _G.issecretvalue = function(v) return v == 777 end
        assert.is_nil(ns.Num(777))
        _G.issecretvalue = nil
    end)
end)

describe("rested experience", function()
    before_each(function() start() end)

    it("grows 5% of the level every 8 hours while resting, up to 150%", function()
        local rec = { xpMax = 1000, rested = 0, resting = true, restedAt = NOW }
        local rested, share = ns.Rested_Project(rec, NOW + 8 * 3600)
        assert.are.equal(50, rested)
        assert.near(0.05, share, 0.0001)
        rested = ns.Rested_Project(rec, NOW + 400 * 86400)
        assert.are.equal(1500, rested)
    end)

    it("grows a quarter of that outside an inn or a city", function()
        local rested = ns.Rested_Project({ xpMax = 1000, rested = 100, resting = false, restedAt = NOW }, NOW + 8 * 3600)
        assert.are.equal(112, rested)
    end)

    it("doesn't project the character playing", function()
        WowMock.now = NOW + 10 * 86400
        local _, share = ns.Rested_ForKey(ns.MyKey())
        assert.near(0.2, share, 0.0001)
    end)
end)

describe("gold history", function()
    before_each(function() start() end)

    it("adds up every character's last known money per day", function()
        local day = function(n) return ns.DayKey(NOW - n * 86400) end
        local a = { goldHistory = { [day(3)] = 100, [day(1)] = 300 } }
        local b = { goldHistory = { [day(2)] = 50 } }
        local history = ns.Gold_History({ { rec = a }, { rec = b } }, 4, NOW)
        assert.are.same({ 100, 150, 350, 350 }, { history[1].total, history[2].total, history[3].total, history[4].total })
    end)

    it("follows the money of the session", function()
        WowMock.char.money = 123456 + 1000
        FireEvent("PLAYER_MONEY")
        assert.are.equal(1000, ns.Session_MoneyChange())
    end)
end)

describe("items", function()
    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        WowMock.AddItem(0, 1, 2447, 20, { name = "Peacebloom", classID = 7, subclassID = 9 })
        WowMock.AddItem(1, 3, 2447, 5)
        WowMock.AddItem(0, 2, 118, 3, { name = "Minor Healing Potion", classID = 0, subclassID = 1 })
        StartAddon(ns, { chars = { ["Alt-Realm"] = { name = "Alt", faction = "Horde", bags = { [2447] = 7 }, bank = { [2447] = 1 },
            mail = { items = { [2447] = 2 } } } } })
    end)

    it("counts the bags", function()
        assert.are.equal(25, ns.Me().bags[2447])
        assert.are.equal("Peacebloom", BakalaoDataStoreDB.items[2447].n)
        assert.are.equal(56 - 3, ns.Me().bagFree)
    end)

    it("counts the bank only at a banker", function()
        WowMock.AddItem(-1, 1, 2447, 100)
        FireEvent("PLAYERBANKSLOTS_CHANGED")
        assert.is_nil(ns.Me().bank)
        FireEvent("BANKFRAME_OPENED")
        assert.are.equal(100, ns.Me().bank[2447])
    end)

    it("says who has an item, and where", function()
        local h = ns.Inventory_Holders(2447)
        assert.are.equal(25 + 7 + 1 + 2, h.total)
        assert.are.equal(2, h.chars[2].mail)
        assert.are.equal(25, ns.Inventory_Holders(2447, { faction = "Alliance" }).total)
        assert.are.equal(10, ns.Inventory_Holders(2447, { includeMe = false }).total)
    end)

    it("finds items by name or id", function()
        assert.are.equal(2447, ns.Inventory_Search("bloom")[1].id)
        assert.are.equal(1, #ns.Inventory_Search("118"))
    end)

    it("saves each worn item's link by slot", function()
        WowMock.inventory[16] = 2447
        FireEvent("PLAYER_EQUIPMENT_CHANGED")
        assert.are.equal("item:2447", ns.Me().gear[16])
    end)

    it("reads the guild bank tabs it can see", function()
        WowMock.char.guild = "Los Piratas"
        _G.GetNumGuildBankTabs = function() return 2 end
        _G.GetGuildBankTabInfo = function(tab) return "Tab" .. tab, nil, tab == 1 end
        _G.GetGuildBankItemLink = function(tab, slot) if tab == 1 and slot == 5 then return "|Hitem:2447::|h[Peacebloom]|h" end end
        _G.GetGuildBankItemInfo = function() return nil, 40 end
        _G.GetGuildBankMoney = function() return 1000000 end
        _G.QueryGuildBankTab = function() end
        FireEvent("GUILDBANKFRAME_OPENED")
        assert.are.equal(40, BakalaoDataStoreDB.guilds["Los Piratas-Realm"].tabs[1].items[2447])
        assert.are.equal(40, ns.Inventory_Holders(2447).guilds[1].count)
    end)
end)

describe("mail", function()
    before_each(function()
        start({ chars = { ["Alt Two-Realm"] = { name = "Alt Two", faction = "Alliance", class = "MAGE" } } })
    end)

    it("reads the mailbox and the letter that expires first", function()
        WowMock.inbox = {
            { sender = "A", money = 500, daysLeft = 10, items = { { id = 2447, count = 4 } } },
            { sender = "B", daysLeft = 2.5 },
        }
        ns.Mail_Scan()
        local mail = ns.Me().mail
        assert.are.equal(2, mail.count)
        assert.are.equal(4, mail.items[2447])
        assert.are.equal(NOW + math.floor(2.5 * 86400), mail.expiresAt)
    end)

    it("adds what is sent to another character of the account, and tells", function()
        local heard
        ns.RegisterCallback(function(kind, key, items) if kind == "mailSent" then heard = { key, items } end end)
        WowMock.sendItems = { { id = 2447, count = 10 } }
        SendMail("Alt Two", "hi", "")
        FireEvent("MAIL_SEND_SUCCESS")
        assert.are.equal(10, BakalaoDataStoreDB.chars["Alt Two-Realm"].mail.items[2447])
        assert.are.equal("Alt Two-Realm", heard[1])
        assert.are.equal(10, heard[2][2447])
    end)

    it("ignores mail to anyone else", function()
        WowMock.sendItems = { { id = 2447, count = 10 } }
        SendMail("Stranger", "hi", "")
        FireEvent("MAIL_SEND_SUCCESS")
        assert.is_nil(BakalaoDataStoreDB.chars["Alt Two-Realm"].mail)
    end)
end)

describe("cooldowns, lockouts, reputation, quests, resets", function()
    before_each(function() start() end)

    it("turns a running cooldown into the time it ends", function()
        WowMock.spells[17187] = true
        WowMock.time = 1000
        WowMock.cooldowns[17187] = { 900, 86400 }
        ns.Cooldowns_Scan()
        assert.are.equal(NOW + 86300, ns.Me().cooldowns.transmute.readyAt)
        -- without a list of characters: every character
        local all = BakalaoDataStore.Cooldowns()
        assert.are.equal(1, #all)
        assert.is_false(BakalaoDataStore.CooldownReady(all[1].cd))
    end)

    it("reads the lockouts and forgets the expired ones", function()
        WowMock.char.saved = { { name = "Molten Core", reset = 3600, bosses = 10, killed = 3 } }
        FireEvent("UPDATE_INSTANCE_INFO")
        assert.are.equal(1, #ns.Lockouts_Active(ns.Me()))
        assert.are.equal(0, #ns.Lockouts_Active(ns.Me(), NOW + 7200))
    end)

    it("reads the reputations", function()
        WowMock.char.factions = {
            { factionID = 529, name = "Argent Dawn", reaction = 6, currentReactionThreshold = 9000,
                nextReactionThreshold = 21000, currentStanding = 12000 },
        }
        ns.Reputation_Scan()
        assert.are.equal(3000, ns.Me().reps[529].cur)
    end)

    it("knows attunements by quest and keys by item", function()
        WowMock.char.quests[7848] = true
        WowMock.AddItem(0, 1, 18249, 1, { name = "Crescent Key" })
        FireEvent("BAG_UPDATE_DELAYED")
        ns.Attunements_Scan()
        local byKey = {}
        for _, a in ipairs(ns.ATTUNEMENTS) do byKey[a.key] = a end
        assert.are.equal("done", ns.Attunements_Status(ns.Me(), byKey.mc))
        assert.are.equal("done", ns.Attunements_Status(ns.Me(), byKey.dm))
        assert.is_nil(ns.Attunements_Status(ns.Me(), byKey.bwl))
    end)

    it("follows any quest an addon asks for", function()
        WowMock.char.quests[1234] = true
        assert.is_true(ns.WatchQuest(1234))
        assert.is_true(ns.QuestDone(ns.MyKey(), 1234))
        BakalaoDataStoreDB.chars["Alt-Realm"] = { name = "Alt", quests = { [1234] = true } }
        assert.is_true(ns.QuestDone("Alt-Realm", 1234))
        assert.is_false(ns.QuestDone("Alt-Realm", 99))
    end)

    it("knows the last and next resets while the account is away", function()
        local last = ns.Resets_Last("weekly", NOW + 20 * 86400)
        assert.is_true(last <= NOW + 20 * 86400 and last > NOW + 13 * 86400)
        assert.are.equal(last + 7 * 86400, ns.Resets_Next("weekly", NOW + 20 * 86400))
    end)
end)

describe("callbacks, import and the public API", function()
    before_each(function() start() end)

    it("tells the addons what changed", function()
        local kinds = {}
        ns.RegisterCallback(function(kind) kinds[kind] = true end)
        FireEvent("PLAYER_MONEY")
        WowMock.char.saved = { { name = "Molten Core", reset = 3600 } }
        FireEvent("UPDATE_INSTANCE_INFO")
        assert.is_true(kinds.money)
        assert.is_true(kinds.lockouts)
    end)

    it("imports what an addon saved before the store, keeping the newest copy", function()
        assert.is_true(ns.Import("Old-Realm", { name = "Old", level = 15, maxLevel = true, lastSeen = 5 }))
        assert.is_false(BakalaoDataStoreDB.chars["Old-Realm"].maxLevel) -- mended on the way in
        assert.is_false(ns.Import("Old-Realm", { name = "Old", lastSeen = 1 }))
        ns.ImportShared({ ["G-Realm"] = { name = "G", time = 1 } }, { [1] = { n = "Thing" } }, nil, { daily = 99 })
        assert.are.equal("G", BakalaoDataStoreDB.guilds["G-Realm"].name)
        assert.are.equal("Thing", BakalaoDataStoreDB.items[1].n)
    end)

    it("forgets characters but never the one playing", function()
        BakalaoDataStoreDB.chars["Old-Realm"] = { name = "Old" }
        assert.is_true(ns.Forget("Old-Realm"))
        assert.is_false(ns.Forget(ns.MyKey()))
    end)

    it("is a global with a version and the functions it documents", function()
        local api = _G.BakalaoDataStore
        assert.are.equal(1, api.version)
        local names = { "MyKey", "IsMe", "Me", "GetCharacter", "Characters", "FindCharacter", "Forget", "ItemName", "ItemIcon",
            "ItemQuality", "ItemClass", "ItemHolders", "SearchItems", "ItemsOfClass", "Guilds", "AccountBank", "Rested",
            "IsRestedFull", "IsMaxLevel", "Played", "LevelTimes", "GoldOnDay", "GoldHistory", "SessionStart",
            "SessionMoneyChange", "SessionXPRate", "SessionTimeToLevel", "LastReset", "NextReset", "HasMail", "MailExpiresIn",
            "Cooldowns", "CooldownReady", "Lockouts", "LockoutInstances", "FindLockout", "Factions", "ReputationValue",
            "StandingName", "StandingColor", "AttunementStatus", "AttunementQuest", "WatchQuest", "QuestDone",
            "RegisterCallback", "GetOption", "SetOption", "Import", "ImportShared" }
        for _, name in ipairs(names) do assert.are.equal("function", type(api[name]), name) end
        assert.are.equal("table", type(api.ATTUNEMENTS))
        assert.are.equal("Tester-Realm", api.MyKey())
        api.SetOption("autoPlayed", false)
        assert.is_false(api.GetOption("autoPlayed"))
    end)

    it("has a Spanish text for every key", function()
        local missing = {}
        for _, path in ipairs(TocFiles()) do
            local text = assert(io.open(path, "r")):read("*a")
            for key in text:gmatch('L%["(.-[^\\])"%]') do
                if not ns.L_ES[key] then missing[#missing + 1] = path .. ": " .. key end
            end
        end
        for _, name in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted", "Transmute" }) do
            if not ns.L_ES[name] then missing[#missing + 1] = name end
        end
        assert.are.same({}, missing)
    end)
end)

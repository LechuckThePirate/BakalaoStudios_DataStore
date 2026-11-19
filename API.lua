local _, ns = ...

-- Public API: what every BakalaoStudios addon (Alterao!!, Enfocao!!, ...) knows about the account's characters, from
-- one place. A global table, versioned like the siblings' APIs (bump `version` on a breaking change; new functions
-- don't need it). Records are handed out as they are saved, to read only: an addon keeps its own data about a
-- character (notes, hidden...) in its own saved variables.
--
-- Characters
--   MyKey() / IsMe(key) / Me()            the playing character's key ("Name-Realm") and record
--   GetCharacter(key)                     a character's record: name, realm, class, race, faction, level, xp, xpMax,
--                                         rested, maxLevel, money, goldHistory, zone, bind, guild, ilvl, durability,
--                                         played, levels, professions, reps, currencies, pvp, quests, cooldowns,
--                                         lockouts, mail, bags, bank, equipped, gear (slot -> item link), lastSeen
--   Characters()                          { { key =, rec = } } every character, by level and name
--   FindCharacter(name) -> key, rec       by name (spaces and case ignored, realm optional)
--   Forget(key)                           deletes a character (not the one playing)
-- Items
--   ItemName / ItemIcon / ItemQuality(itemID), ItemClass(itemID) -> classID, subclassID
--   ItemHolders(itemID, opts)             who has it: { chars = { { key, rec, bags, bank, mail, equipped, total } },
--                                         guilds = { { name, count } }, account =, total = }
--                                         opts: faction =, includeMe = false, guilds = false
--   SearchItems(text)                     { { id =, name =, total = } } held anywhere
--   ItemsOfClass(rec, classID, subclassID) what a character carries of a class of items
--   Guilds() / AccountBank()              the guild banks seen, the warband bank
-- Experience, money, time
--   Rested(key, now) -> xp, share (0..1.5), secondsUntilFull;  IsRestedFull(key, now);  RESTED_CAP
--   IsMaxLevel(level, xpMax);  Played(rec) (seconds, now for the one playing);  LevelTimes(rec)
--   GoldOnDay(rec, "2026-11-18");  GoldHistory(chars, days, now)
--   SessionStart() (GetTime() at login), SessionMoneyChange(), SessionXPRate() (per hour), SessionTimeToLevel(rec)
--   LastReset("daily" | "weekly", now), NextReset(kind, now)
-- Mail, cooldowns, lockouts, reputation, quests
--   HasMail(rec), MailExpiresIn(rec, now)
--   Cooldowns(chars, alertOnly) -> { { key, rec, cd = { name, icon, readyAt, alert }, id } },  CooldownReady(cd, now)
--   Lockouts(rec, now), LockoutInstances(chars, now), FindLockout(rec, instanceName, now)
--   Factions(chars), ReputationValue(r), StandingName(standing), StandingColor(standing)
--   ATTUNEMENTS, AttunementStatus(rec, a) -> "done" | "key" | nil, quest;  AttunementQuest(a, faction)
--   WatchQuest(questID) (follow it for every character), QuestDone(key, questID)
-- Changes and options
--   RegisterCallback(fn)                  fn(kind, key, ...) after a change (kinds in Core/Util.lua)
--   GetOption(name) / SetOption(name, v)  the store's options: autoPlayed
-- Migration
--   Import(key, rec), ImportShared(guilds, items, account, resets)   data saved by an addon before the store

local API = { version = 1 }

API.MyKey = ns.MyKey
API.IsMe = ns.IsMe
API.Me = ns.Me
API.GetCharacter = ns.GetChar
API.Characters = ns.Characters
API.FindCharacter = ns.FindCharByName
API.Forget = ns.Forget

API.ItemName = ns.Items_Name
API.ItemIcon = ns.Items_Icon
API.ItemQuality = ns.Items_Quality
API.ItemClass = ns.Items_Class
API.ItemHolders = ns.Inventory_Holders
API.SearchItems = ns.Inventory_Search
API.ItemsOfClass = ns.Inventory_OfClass
function API.Guilds() return ns.db.guilds end
function API.AccountBank() return ns.db.account end

API.Rested = ns.Rested_ForKey
API.IsRestedFull = ns.Rested_IsFull
API.RESTED_CAP = ns.RESTED_CAP
API.IsMaxLevel = ns.IsMaxLevel
API.Played = ns.PlayedNow
API.LevelTimes = ns.LevelTimes
API.GoldOnDay = ns.Gold_OnDay
API.GoldHistory = ns.Gold_History
function API.SessionStart() return ns.session and ns.session.start end
API.SessionMoneyChange = ns.Session_MoneyChange
API.SessionXPRate = ns.Session_XPRate
API.SessionTimeToLevel = ns.Session_TimeToLevel
API.LastReset = ns.Resets_Last
API.NextReset = ns.Resets_Next

API.HasMail = ns.Mail_Has
API.MailExpiresIn = ns.Mail_ExpiresIn
API.Cooldowns = ns.Cooldowns_All
API.CooldownReady = ns.Cooldowns_IsReady
API.Lockouts = ns.Lockouts_Active
API.LockoutInstances = ns.Lockouts_Instances
API.FindLockout = ns.Lockouts_Find
API.Factions = ns.Reputation_Factions
API.ReputationValue = ns.Reputation_Value
API.StandingName = ns.StandingName
API.StandingColor = ns.StandingColor
API.ATTUNEMENTS = ns.ATTUNEMENTS
API.AttunementStatus = ns.Attunements_Status
API.AttunementQuest = ns.Attunements_Quest
API.WatchQuest = ns.WatchQuest
API.QuestDone = ns.QuestDone

API.RegisterCallback = ns.RegisterCallback
function API.GetOption(name) return ns.settings and ns.settings[name] end
function API.SetOption(name, value) if ns.settings then ns.settings[name] = value end end

API.Import = ns.Import
API.ImportShared = ns.ImportShared

BakalaoDataStore = API

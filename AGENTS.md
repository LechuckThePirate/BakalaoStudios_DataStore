# BakalaoStudios DataStore — agent guide

World of Warcraft library addon: what every BakalaoStudios addon knows about the account's characters, saved once
(`BakalaoDataStoreDB`) and shared through a public API (`BakalaoDataStore`). Each character saves its own copy while it
plays (the game can't tell anything about the others): identity, level, XP and rested, money and its daily history,
zone, guild, gear (item links per slot), played time, professions, currencies, PvP, bags, bank, mail (and mail sent
between characters), guild banks, account bank, cooldowns, lockouts, reputations, quests (attunements and any watched
quest) and the daily / weekly resets. No UI. Only WoW Forever for now (`## Interface: 16001`).

Used by **Alterao!!** (required dependency) and, planned, **Enfocao!!** (optional). Siblings with the same conventions
under `D:\Source\WowAddons\`: `Alterao` (where this code came from, 2026-11-19), `Emboscao`, `Aggreao`, `Completao`,
`Embolsao`, `Fabrikao`.

## How to work with the maintainer

- **Chat in Spanish from Spain** ("tú", never voseo). **Everything committed is in English**; Spanish only in the esES/esMX
  table of `Localization/Locale.lua` and the esES/esMX TOC notes.
- Windows machine. Multi-line commit messages: write a file and use `git commit -F <file>`.
- Merging to `master` and releasing only happen when the maintainer asks.
- **The API is a contract**: addons published on CurseForge call it. Add functions freely; change or remove one only by
  bumping `version` (and keeping the old one while the addons move). Records are handed out to read only.

## Layout

- `BakalaoStudios_DataStore.toc`, `BakalaoStudios_DataStore.lua` (entry: load, enter world, logout)
- `API.lua` — the public API (`BakalaoDataStore`), documented at the top of the file
- `Localization/Locale.lua` — the few texts it hands out (cooldown and standing names)
- `Core/` — `Util` (print, `ns.On` events, `ns.SafeCall`, `ns.Debounce`, secret values, the callbacks `ns.Changed`),
  `Compat` (every game API read: C_* first, old global as fallback), `DB` (records, keys, item names, import)
- `Track/` — one file per area: `Character` (and the gold history, played time, session), `Rested`, `Inventory`
  (holders, search), `Mail`, `Cooldowns`, `Lockouts`, `Reputation`, `Attunements` (and watched quests), `Resets`
- `test/` (WoW API mock: `WowApiMock.lua` generic, `GameMock.lua` the game state; local runner), `setupTests.lua`

## Rules learned in game (Forever)

- While logging out the game answers zeros (money, XP): at logout only `lastSeen`, `restedAt` and `resting` are saved;
  `Character_Repair` mends records an older version saved with zeros.
- Two-word names can come back cut (the second word as the realm): the key uses the longest of the game's answers.
- The modern bank may never fire BANKFRAME_OPENED: every bank signal is listened to (interaction manager, BankFrame).

## Commands (repo root)

```powershell
lua test/busted.lua
luacheck -q -- BakalaoStudios_DataStore.lua API.lua Localization Core Track test setupTests.lua
```

Deploy to the Forever client (PowerShell; robocopy exit codes 0-7 are success):
`robocopy . "D:\Games\World of Warcraft\_forever_\Interface\AddOns\BakalaoStudios_DataStore" *.lua *.toc /S /PURGE /XD test .github .git .claude /XF *.test.lua setupTests.lua`

## Code conventions

As in the siblings: Lua 5.1, `local ADDON, ns = ...` in every file, no new globals but the two saved/API tables
(`.luacheckrc`), every game read checked for secret values (`ns.Num`), each tracker inside `ns.SafeCall`, optional
events through `ns.On`. Commit style: `feat(scope):`, `fix(scope):`, `release: X.Y.Z -- short summary`.

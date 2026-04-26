# AltTracker – Copilot Agent Instructions

Trust these instructions. Only search the codebase if the information below is incomplete or appears incorrect.

---

## What This Repository Is

AltTracker is a **World of Warcraft TBC Classic addon** (patch 2.5.4, interface `20504`) written entirely in **Lua**. It tracks alt characters across multiple WoW accounts, syncing data via WoW's addon-message protocol, and displays a spreadsheet-style in-game UI showing gear, professions, reputations, and BiS status.

- **Language**: Lua (no external runtime, no build toolchain)
- **Target**: WoW TBC Classic client (interface 20504)
- **Size**: ~11 Lua source files, ~4 000 lines total
- **No CI/CD, no tests, no linter config, no package manager**

---

## File Load Order (defined in `AltTracker.toc`)

WoW loads files in this exact order — order matters:

1. `Core.lua` — addon-message protocol, sync engine, event handler, slash commands
2. `Scanner.lua` — scans the current character (gear slots, professions, stats)
3. `Reputations.lua` — scans TBC faction reputations
4. `Config.lua` — settings panel (account number, whitelist, toast toggles)
5. `Toasts.lua` — profession cooldown toast notifications
6. `BisData.lua` — static BiS gear tables per class/spec/tier (T4/T5/T6/Sunwell)
7. `Columns.lua` — column definitions (field, type, width, group)
8. `RowRenderer.lua` — renders each spreadsheet row (icons, colors, tooltips)
9. `SheetUI.lua` — main spreadsheet frame with section tabs
10. `Export.lua` — clipboard export to Google Sheets CSV format

If you add a new Lua file you **must** add it to `AltTracker.toc` in the correct position.

---

## Global Namespace

- `AltTracker` — the single global table; all public functions and data live here.
- `AltTrackerDB` — SavedVariable; character records keyed by GUID (`AltTrackerDB[guid] = { name, class, gear_*, prof_*, ... }`).
- `AltTrackerConfig` — SavedVariable; user settings (`syncMode`, `whitelist`, `accountNumber`, `sendAllAccounts`, `toastsEnabled`, `toastProfessions`).

Every file opens with `AltTracker = AltTracker or {}` to be safe at load time.

---

## WoW API Constraints

This addon targets **TBC Classic** APIs only. Do not use Retail or WotLK-only APIs. Key APIs in use:

- `GetTalentTabInfo`, `GetNumTalentTabs` — talent trees (TBC style, not DF/Retail)
- `GetSkillLineInfo`, `GetNumSkillLines` — professions and skills
- `GetTradeSkillInfo`, `GetTradeSkillCooldown`, `GetNumTradeSkills` — tradeskill window
- `C_ChatInfo.SendAddonMessage`, `C_ChatInfo.RegisterAddonMessagePrefix` — addon messages
- `C_Timer.After`, `C_Timer.NewTimer` — timers
- `GetFactionInfo`, `GetNumFactions` — reputations
- `GetInventoryItemLink`, `GetItemInfo` — gear
- `UnitGUID`, `UnitName`, `UnitClass`, `UnitRace`, `UnitLevel`, `UnitSex`, `UnitXP`, `UnitXPMax`
- `GetMoney`, `GetXPExhaustion`, `GetAverageItemLevel`, `GetGuildInfo`, `GetRealmName`
- `CreateFrame`, `BackdropTemplate` — UI frames (TBC FrameXML)

WoW addon messages are capped at **255 bytes**. The sync protocol chunks payloads at 249 bytes (`MAX_CHUNK`) with a 0.1 s inter-packet delay (`CHUNK_SEND_INTERVAL`). The protocol version constant is `PROTOCOL_VERSION = "3"` in `Core.lua` — **bump this if the serialization format changes**.

---

## Sync Protocol Summary

Messages use prefix `"ALTTRACKER"`. Format: `"CMD|payload"` via `C_ChatInfo.SendAddonMessage`.

- `REQ3` — request full DB from a peer
- `CHUNK|<bytes>` — one chunk of a chunked stream
- `DONE3|<checksum>` — end of stream, with additive checksum (hex)
- `CHAR\n<serialized>` — single-character update (legacy/backward-compat path)

Character records are serialized as `key:value\n` lines; separator between records is `==END==`.

---

## Slash Commands

| Command | Action |
|---|---|
| `/alts` | Open sheet + request sync from whitelist |
| `/alts sync <PlayerName>` | Manual whisper sync with a specific player |
| `/alts account <N>` | Set this client's account number |
| `/alts config` | Open settings panel |
| `/alts export` | Show clipboard export window |
| `/alts cleanup` | Wipe DB to current character only, then re-request |

---

## Build & Validation

There is no build step. The addon is pure Lua interpreted by the WoW client.

**Syntax check (only validation available without a running WoW client):**

```
luac -p *.lua
```

This requires `luac` (Lua 5.1 compiler — WoW uses Lua 5.1). If `luac` is not installed, install it with `winget install DEVCOM.Lua` (Windows) or `brew install lua` (macOS). Run `luac -p` on every changed `.lua` file before committing. A clean run produces no output.

**Deployment for manual testing:**

Copy the entire repository folder into the WoW TBC Classic AddOns directory:
`<WoW install>\\_classic_tbc_\\Interface\\AddOns\\AltTracker\\`

Then launch WoW and type `/alts` in-game.

**There are no automated tests and no CI/CD pipelines.** There are no GitHub Actions workflows in this repository.

---

## Key Architectural Patterns

- **Column types** (`Columns.lua`): `"name"`, `"classIcon"`, `"specIcon"`, `"raceIcon"`, `"number"`, `"gearSlot"`, `"bisCount"`, `"profSkill"`, `"rep"`, `"repCombined"`, `"cooldown"`, `"money"`, `"lastUpdate"`. Add new columns by appending to `AltTracker.Columns` and implementing the type in `RowRenderer.lua`.
- **Section groups** (`SheetUI.lua`): `"always"`, `"gear"`, `"skills"`, `"rep"`, `"cooldowns"`. Each section lists which `field` names to show.
- **BiS data** (`BisData.lua`): Indexed as `AltTracker.BisData[CLASS_FILE][SpecName][Tier][slotKey]`. Values are a string or table of strings (alternatives). Item names must match `GetItemInfo()` exactly.
- **Cooldown keys**: `cd_Mooncloth`, `cd_Shadowcloth`, `cd_Spellcloth`, `cd_Transmute`, `cd_BrilliantGlass` — stored as Unix timestamps on the character record.
- **Gear slot keys**: `head`, `neck`, `shoulder`, `back`, `chest`, `wrist`, `hands`, `waist`, `legs`, `feet`, `ring1`, `ring2`, `trinket1`, `trinket2`, `mainhand`, `offhand`, `ranged`. Fields: `gear_<key>` (ilvl), `gearq_<key>` (quality), `gearname_<key>` (name), `gearlink_<key>` (link — local only, not synced).
- **Profession flat fields**: `prof_<Name>` (skill rank), `profmax_<Name>` (max). Names match `GetSkillLineInfo` exactly (e.g., `prof_Tailoring`, `prof_Jewelcrafting`).

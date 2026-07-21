# AGENTS.md — Shared Context for Agents

Shared baseline for any agent working in this repo (Claude Code, Codex, Copilot all read
`AGENTS.md`). Keep durable project rules here. `.github/copilot-instructions.md` is a
Copilot-specific overlay — this file is the source of truth; keep the two consistent.

## What this project is

AltTracker is a **World of Warcraft TBC Classic addon** (interface `20505`, patch 2.5.x)
written entirely in **Lua 5.1** — the version WoW's client uses. It tracks alt characters
across multiple WoW accounts, syncs data over WoW's addon-message protocol, and shows a
spreadsheet-style in-game UI of gear, professions, reputations, and BiS status.

- **Language:** Lua 5.1. No external runtime, no build toolchain, no package manager.
- **Target:** WoW TBC Classic client only — use TBC-era APIs, never Retail/WotLK-only ones.
- **Namespace:** one global table `AltTracker`; every file starts `AltTracker = AltTracker or {}`.
- **SavedVariables:** `AltTrackerDB` (character records keyed by GUID) and `AltTrackerConfig`
  (user settings). Declared in `AltTracker.toc`.

## Layout

- **Core addon** — Lua files at the repo root, loaded in the order listed in `AltTracker.toc`
  (order matters; a new `.lua` file must be added there in the right position):
  `Theme.lua`, `AltTrackerRenderManifest.lua`, `Core.lua`, `Scanner.lua`, `Reputations.lua`,
  `Config.lua`, `Toasts.lua`, `BisData.lua`, `Columns.lua`, `RowRenderer.lua`, `SheetUI.lua`,
  `Export.lua`.
- **In-repo LoadOnDemand plugins** under `Plugins/`, each its own addon with its own `.toc`
  (`## Dependencies: AltTracker`, `## LoadOnDemand: 1`):
  - `Plugins/Professions/` → deploys as `AltTrackerProfessions` (recipe scanning).
  - `Plugins/Roster/` → deploys as `AltTrackerRoster`.
- `Core.lua` holds the addon-message sync engine — the most protocol-sensitive code. The
  protocol version constant (`PROTOCOL_VERSION` in `Core.lua`) must be bumped if the
  serialization format changes. Addon messages are capped at 255 bytes; the sync path chunks
  payloads (`MAX_CHUNK`) with an inter-packet delay.
- `tests/` — Lua 5.1 unit tests (see below).
- `Tools/deploy.ps1` — deploy script.

## Build & validate

There is no build step — WoW interprets the Lua directly. The Lua 5.1 toolchain lives at
`C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`).

- **Syntax-check every changed file** before committing — a clean run prints nothing:
  ```
  luac -p <file>.lua
  ```
- **Run the tests** (see next section) before committing changes to synced/serialized logic.

## Testing

A dependency-free unit harness lives in `tests/`, running under **Lua 5.1** (not whatever
newer Lua is first on `PATH`).

- **Run all tests:** `pwsh tests/run.ps1` (override the interpreter with `-Lua <path>`;
  it defaults to the path above). It runs every `tests/test_*.lua` from the repo root and
  exits non-zero on failure.
- **How it works:** `tests/wow_stubs.lua` is a minimal WoW API mock (chainable `CreateFrame`,
  a `C_Timer` that records callbacks, an addon-message capture, `strsplit`, etc.), driven via
  the exported `WoW` table (`WoW.reset()`, `WoW.flushTimers()`, `WoW.sentMessages()`, …).
  A test `dofile`s the stubs, sets up SavedVariable globals, `loadfile`s the module under
  test, and asserts. File-local internals are reached through the **`AltTracker._test = { … }`
  seam** at the bottom of `Core.lua` (harmless in-game) — extend that seam rather than
  promoting internals to real globals.
- **Add a test** as `tests/test_<area>.lua`, following `tests/test_comm.lua`; `run.ps1`
  picks it up automatically. See `tests/README.md` for details.

## Deploying for in-game testing

WoW only discovers addons as **top-level** folders under `Interface/AddOns`, but the repo
keeps plugins nested under `Plugins/`. Use the deploy script — it fans the core and each
plugin out into sibling AddOns folders:

```
pwsh Tools/deploy.ps1
# or target a specific client:
pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\Interface\AddOns"
```

Then `/reload` in-game (keep `AltTrackerProfessions` and `AltTrackerRoster` enabled in the
AddOns list). Core is copied additively; plugin folders are mirrored (stale files purged).

## Key architectural patterns

- **Columns** (`Columns.lua` + `RowRenderer.lua`): each column has a typed renderer
  (`name`, `classIcon`, `gearSlot`, `bisCount`, `profSkill`, `rep`, `cooldown`, `money`,
  `lastUpdate`, …). Add a column by appending to `AltTracker.Columns` and implementing its
  type in `RowRenderer.lua`.
- **Sections** (`SheetUI.lua`): `always`, `gear`, `skills`, `rep`, `cooldowns` — each lists
  the `field` names it shows.
- **BiS data** (`BisData.lua`): `AltTracker.BisData[CLASS_FILE][Spec][Tier][slotKey]`; item
  names must match `GetItemInfo()` exactly.
- **Character record fields:** gear as `gear_<slot>` / `gearq_<slot>` / `gearname_<slot>`
  (`gearlink_*` is local-only, not synced); professions as `prof_<Name>` / `profmax_<Name>`
  matching `GetSkillLineInfo`; cooldowns as `cd_<Name>` Unix timestamps.
- **Sync protocol** uses prefix `"ALTTRACKER"`, `"CMD|payload"` messages; records serialize
  as `key:value\n` lines separated by `==END==`. Read `Core.lua` before touching it, and
  keep a corresponding `tests/test_comm.lua` case green.

## Conventions

- **Right-size for a single maintainer.** This is a personal addon with one owner — prefer
  the simplest thing that works. Don't add enterprise-grade abstraction, config, or edge-case
  handling nobody asked for.
- **Match the surrounding code.** Follow the existing file's style (locals, `AltTracker.*`
  attachment, table-driven definitions) rather than introducing a second idiom.
- **Boy-Scout, bounded.** Small cleanups in files you're already editing are fine; keep pure
  refactors in their own commit, separate from behavioural change. No drive-by reorgs of files
  you aren't otherwise touching.
- **Propose, don't expand.** If you spot worthwhile out-of-scope work, mention it — don't
  balloon the current change to do it.

## Git conventions

- Work on a branch off `main`, not directly on `main`. Commit or push only when asked.
- **Commit messages:** short imperative subject; body only if it adds something. End with:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```
- Before committing: `luac -p` clean on changed files, and `pwsh tests/run.ps1` green when
  sync/serialization logic changed.

## Agent workflow tips

- **Prefer inline tools** (Read, Grep, Glob, Bash) over spawning subagents for a codebase
  this small — a few searches usually beat the coordination overhead. Reserve agents for
  genuinely broad surveys or parallel independent research.
- **Verify before asserting.** Paths, load order, and API usage drift; confirm against the
  repo (glob/read) rather than trusting stale notes — including the older claims in
  `.github/copilot-instructions.md`.
- **Deploy is a file copy** to the WoW AddOns folder (`pwsh Tools/deploy.ps1`) — low-stakes,
  no build.

## Cost control & model usage

Right-sizing applies to spend too — this is a small single-maintainer addon, so keep token
and context use lean.

- **Prefer inline tools over subagents.** Read, Grep, Glob, and Bash are cheaper than spawning
  an agent (see "Agent workflow tips" above). Only spawn one for a genuinely broad survey or
  parallel independent research — don't fan out for fan-out's sake; each agent starts cold and
  the coordination overhead often exceeds the benefit for a repo this size.
- **Cap parallelism.** Don't spawn more than ~2 subagents in one turn.
- **Compact / start fresh after heavy work.** Compact after a large exploration phase, big diff,
  or repeated syntax-check/test loops before moving on; start a clean session when switching to an
  unrelated task rather than carrying a huge context forward.
- **Match the model to the work — cheap for mechanical, strong for tricky:**
  - *Cheap/fast model (Haiku):* mechanical, low-judgment work — file-finding and symbol/usage
    searches, small rote edits, and **deploy / file-copy tasks** (`Tools/deploy.ps1` is delegated
    to Haiku here; a cheap model is right for a no-build file copy).
  - *Mid model (Sonnet):* routine implementation — new columns, renderers, config plumbing,
    straightforward test additions.
  - *Strong model (Opus):* tricky reasoning and audits — the `Core.lua` sync/serialization engine,
    protocol-version and chunking changes, difficult debugging, and final review of a large diff.
- **Escalate to the strong model only when the task warrants it:** protocol/sync behavior, risky
  cross-cutting changes, ambiguous debugging, or reviewing a meaningful diff. Keep tight, specific
  prompts for cheaper models — a narrow question returns a better answer and costs less than a
  broad survey.

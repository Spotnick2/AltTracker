# AltTracker tests

Automated unit tests that run under **Lua 5.1** (the interpreter WoW uses) with
no game client. Plain scripts, no external dependencies.

## Running

All tests:

```powershell
pwsh tests/run.ps1
```

A single test (from the repo root, so relative `loadfile`/`dofile` paths resolve):

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_comm.lua
```

> Use the Lua **5.1** interpreter, not a newer Lua that may be first on `PATH`.
> `run.ps1` defaults to `C:\Program Files (x86)\Lua\5.1\lua.exe`; override with
> `-Lua <path>`.

## How it works

- **`wow_stubs.lua`** — a minimal WoW API mock (chainable `CreateFrame`,
  `C_Timer` that *records* callbacks instead of waiting, injectable
  `LoadAddOn`/`IsAddOnLoaded`, `C_ChatInfo.SendAddonMessage` that captures the
  wire, `strsplit`, etc.). `dofile("tests/wow_stubs.lua")` first in every test.
  Drive/inspect it through the exported `WoW` table: `WoW.reset()`,
  `WoW.flushTimers()`, `WoW.sentMessages()`, `WoW.SetLoaded(...)`.
- Each test sets up the SavedVariable globals, `loadfile`s the addon file under
  test (which self-attaches to `AltTracker`), then asserts against the exposed
  functions. Internals that are file-local are reached through a **test seam**:
  `AltTracker._test = { … }` at the end of `Core.lua` (harmless in-game).
- Assertions use a tiny inline `check`/`eq` harness; a file prints
  `… tests passed: N` and exits non-zero on failure.

## Test files

- **`test_comm.lua`** — the sync/communication protocol in `Core.lua`: base64
  codec, checksum, character + full-DB serialize/deserialize round-trips, the
  last-write-wins merge and immutable-field validation, and the end-to-end
  chunk → reassemble receive path (including out-of-order delivery, a dropped
  chunk + auto-resync, checksum mismatch, and self-packet suppression).

  > This suite already caught a real bug: `ValidateIncoming` called `Print`
  > before the file-local `Print` was declared, so the class/name-change reject
  > path crashed on a nil global. Fixed by moving `Print` above its first use.

## Adding a test

Create `tests/test_<area>.lua` following `test_comm.lua`: `dofile` the stubs,
set up globals, `loadfile` the module, assert, print a pass count, `os.exit(1)`
on failure. `run.ps1` picks up `test_*.lua` automatically. If you need a
file-local function, add it to the `AltTracker._test` seam rather than making it
a real public global.

# AltTracker ← Altoholic / DataStore — improvement study

_Reference: `Altoholic MoP Classic v5.5.005` (the AddonFactory rewrite; multi-flavor, its
`.toc`s include `## Interface: 20505` so the code genuinely runs on TBC 2.5.5). Read-only survey
mapped to AltTracker's current state, ranked by return on effort._

## TL;DR — the three that matter

1. **Compress the sync payload with LibDeflate** (P0). Drop-in, dependency-free, pure Lua, TBC-safe.
   Insert `CompressDeflate(level=8)` + `EncodeForWoWAddonChannel` where AltTracker's hand-rolled
   base64 currently sits; delete the additive checksum (DEFLATE integrity-checks and the
   deserialize fails cleanly). The recipe payload is highly repetitive IDs → **3–6× smaller**, and
   base64's +33% overhead drops to ~+1%. A 390-chunk sync should fall to ~50–120 chunks. **This
   also largely obviates the deferred recipe-catalog dedup** — DEFLATE already collapses the
   repeated reagent strings across characters, without any of the delivery-correctness risk that
   sank the catalog plan.
2. **Add craft cooldowns** (P1). Near-verbatim drop-in that replaces AltTracker's cooldown stub —
   real TBC value (transmutes, Mooncloth, Salt Shaker, Shadowcloth…).
3. **Kill the 1s/chunk pacing** (P1). After compression, the `~1.05s/chunk` manual pacing is the
   remaining slowness. `ChatThrottleLib` (self-contained, no deps) paces at the game's real ceiling.

Everything else is genuinely useful but lower on the effort-to-payoff curve.

---

## Prioritized opportunities

### P0 — LibDeflate compression on the sync pipeline
- **Now:** `Core.lua` hand-rolls base64 (`Base64Encode`, +33% size) + an additive `ComputeChecksum`,
  then chunks at `MAX_CHUNK=168` with `CHUNK_STEADY_INTERVAL=1.05`.
- **Borrow:** `Altoholic\Comm.lua:76-82` — `serialize → CompressDeflate({level=8}) → EncodeForWoWAddonChannel`.
- **Do:** keep the existing chunker; swap `Base64Encode(chunk)` → `LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload,{level=8}))` at the payload level (compress the whole payload once, then chunk the encoded bytes), and drop the checksum path. Bump the wire version (`PROTOCOL_VERSION`) since both accounts deploy together.
- **Value: very high · Effort: low–med · TBC: yes.** `LibDeflate.lua` is one ~124 KB pure-Lua file, no `bit`/LibStub/CallbackHandler dependency.
- **Bonus:** makes the deferred catalog-dedup milestone unnecessary in practice — compression is the simpler, safe way to shrink the baseline.

### P1 — Craft cooldowns (replace the stub)
- **Now:** the Roster plugin has `cd_<Name>` fields / a `COOLDOWN_FIELDS` list but no live capture.
- **Borrow:** `DataStore_Crafts_NonRetail.lua` `ScanCooldowns` + `API/Common.lua` `_GetCraftCooldownInfo`.
  Store an **absolute expiry**: `expiresAt = GetTradeSkillCooldown(i) + time()`; display `expiresAt - time()`;
  `ClearExpiredCooldowns` sweeps entries where `expiresIn <= 0` (iterate last→first). Re-scan only
  cooldowns by hooking `DoTradeSkill` to set a flag consumed on the next `TRADE_SKILL_UPDATE`.
- **Value: high · Effort: low · TBC: yes** (`GetTradeSkillCooldown` exists in 2.5.5). Fits the
  Professions plugin cleanly and syncs with the recipe blob.

### P1 — Replace 1s/chunk pacing with ChatThrottleLib
- **Now:** AltTracker sleeps `~1.05s` between chunks (conservative, and where the minutes go).
- **Borrow:** `AddonFactory\Libs\ChatThrottleLib\ChatThrottleLib.lua` (534 lines, self-contained, no
  deps) + optionally the ~115-line CTL-based `SendChatMessage` in `AddonFactory\Core\Comm.lua`.
  Fire all chunks into `ChatThrottleLib:SendAddonMessage("BULK", …)` and let CTL drain at WoW's real
  outbound rate. (Altoholic itself dropped AceComm and reimplemented on CTL — **don't adopt AceComm**,
  it pulls in Ace3/LibStub/CallbackHandler for no gain here.)
- **Value: high · Effort: med · TBC: yes.** Do after compression; compression alone may make the
  current pacing tolerable.

### P2 — Saved-instance lockouts (raid resets per alt)
- **Now:** not tracked.
- **Borrow:** `DataStore_Agenda\API\SavedInstances.lua` — `GetNumSavedInstances`/`GetSavedInstanceInfo`
  (available in TBC), same absolute-timestamp idiom. Kara / Gruul / Mag / SSC / TK reset timers across
  alts is high raid-logistics value.
- **Value: high · Effort: low–med · TBC: yes.**

### P2 — Mail with expiry warnings
- **Borrow:** `DataStore_Mails.lua` — scan on `MAIL_SHOW`/`MAIL_INBOX_UPDATE`, store `{itemID, count, link}`
  + money + **expiry days**; warn on soon-to-expire mail. Self-contained.
- **Value: high · Effort: med · TBC: yes.**

### P3 — Bag/bank inventory ("where is item X across my alts")
- **Borrow:** `DataStore_Containers.lua` — scan bags on `BAG_UPDATE`, bank **only** while
  `BANKFRAME_OPENED..CLOSED`. Exposes `GetItemCountByID` to sum across characters.
- **Value: high · Effort: high** (new data domain + UI + it grows the sync payload — mitigated by P0
  compression) · TBC: yes. Biggest feature, do last.

### P3 — Currencies (partial)
- In TBC, Badges of Justice / Emblems are **bag items**, so most of this is better served by bag
  tracking (P3). The currency-list scan (`DataStore_Currencies`) covers honor/arena points only.
  **Low priority for TBC.**

### P3 — LibSerialize (code simplification)
- Replace the line-based `key:value` format with LibSerialize (binary, round-trips nested
  tables/ints, deletes hand-written parse/format). Caveat: **most of the byte win is recovered by
  DEFLATE anyway**, and it's a breaking wire change — do it *in the same version bump as P0* if you
  want to retire the parser, otherwise skip. Pure Lua, ~52 KB, no deps.

---

## Cross-cutting patterns worth adopting (cheap, pure Lua 5.1)

- **Scan-on-open, not on timer.** Bank/mail/tradeskill scans gated by window-open events; DataStore
  even registers `PLAYERBANKSLOTS_CHANGED` only while the bank is open. (`DataStore_Containers` OnBankFrameOpened/Closed.)
- **Startup deferral** to skip the login event storm: initial bag scan `C_Timer.After(3, …)`, mail/equipment ~5s.
- **Debounce bursty events** with a `pending` flag + `C_Timer.After(1, …)` so a burst collapses to one scan.
- **Lazy `GET_ITEM_INFO_RECEIVED` resolution.** AltTracker already registers this event (Core + the
  Professions icon cache); DataStore_Inventory's `ScanAverageItemLevel` shows the full pattern —
  bail when `GetItemInfo` is nil, finish on the cache-ready event. Worth auditing AltTracker's gear/iLvl
  scan to guarantee no blanks on cold cache.
- **String interning (Set/List).** `DataStore:CreateSetAndList` stores a repeated name once + a small
  index per character — this **is** the recipe-catalog idea, generalized. If P0 compression proves
  insufficient, this is the storage-side dedup to reach for (reagent/recipe names).
- **Numeric per-character keys.** DataStore keys module tables by an integer id derived from
  `Account.Realm.Name`, not the long string — smaller SavedVariables and cheap deletion.

## Explicitly skip (cost > payoff for a single-maintainer TBC addon)
- **AddonFactory framework** + the **metatable method-dispatch** layer + full `RegisterModule` — only
  pays off with many modules and external client addons.
- **LibBit64 bit-packing** (`count | itemID<<16`) — halves SavedVars but needs LibStub+LibBit64 and
  obscures the data; plain `{id, count}` tables are fine at AltTracker's scale.
- **AceComm** — replaced by Altoholic itself; use ChatThrottleLib instead.
- Everything gated behind `WOW_PROJECT_MAINLINE`: garrisons, battle pets, transmog, weekly currency caps.

## Suggested sequence
1. **P0 LibDeflate compression** (biggest win, low risk, and retires the catalog-dedup milestone).
2. **P1 craft cooldowns** (quick, real feature) — parallelizable with #1.
3. **P1 ChatThrottleLib** only if sync is still slow after compression.
4. **P2 saved-instance lockouts**, then **mail**.
5. **P3 bag/bank inventory** (largest), **LibSerialize** (optional, fold into #1's version bump).

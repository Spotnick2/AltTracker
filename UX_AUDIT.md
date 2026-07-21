# AltTracker — UX Audit

_Date: 2026-07-21 · Scope: 7 in-game screenshots (Account Summary, Gear Progression,
Skills, Reputations, Recipes, Roster, Options) reviewed against the current source._

## Summary

AltTracker presents account-wide alt data in a spreadsheet-style window: a frozen
**Name** column plus a horizontally-scrolling grid, with tabs down the left sidebar.
The layout is dense and information-rich, and the core machinery (sorting, pooled row
rendering, class tinting, per-cell tooltips, live rested-XP extrapolation) is solid.

This audit focuses on **readability and clarity** polish. Most findings are low/medium
severity — the app works well; these are refinements.

**Note on scope:** **Recipes** and **Roster** are separate plugin addons registered at
runtime via `AltTracker.RegisterPlugin`. Their code lives in sibling repos and **was
audited at source** for this report:
- Recipes → `C:\Projects\AltTrackerProfessions` (`AltTrackerProfessions.lua`) — _not a git repo._
- Roster → `C:\Projects\AltTrackerRoster` (`AltTrackerRoster.lua`) — remote is the old-name
  repo `Spotnick2/AltTrackerAlts`.

All issues (main addon + both plugins) are filed centrally in `Spotnick2/AltTracker` so they
track against this one audit; plugin issues are prefixed `[Recipes plugin]` / `[Roster plugin]`.

**Not an issue:** the rainbow strip along the bottom of the Options screenshot is not
AltTracker — no such element exists in the Lua source; it is another addon / the game UI
showing behind the panel.

## Resolved in this pass

| Area | Finding | Fix |
|------|---------|-----|
| Cross-cutting | **Vertical gridlines too heavy.** Body dividers were opaque, blue-tinted `{0.25,0.25,0.32,0.9}` with a 4px break at every row boundary (`RowRenderer.lua:504,680`), while header dividers used a _different_ color (`SEP`, alpha 1) — so header and body gridlines didn't even match, and both read as heavy segmented lines. | Added a dedicated faint neutral `GRIDLINE = {0.5,0.5,0.5,0.12}` constant (`Theme.lua`), used by both body (`RowRenderer.lua`) and header (`SheetUI.lua`) dividers, and made body dividers full-height so lines are continuous — a subtle, solid, spreadsheet-style gridline. Alpha is tunable in `Theme.lua`. |
| Account Summary | **"1 days" / "1 weeks".** `FormatLastOnline` always appended the plural form (`RowRenderer.lua:440-442`). | Singularizes based on count → "1 day" / "1 week". |

## Open findings (tracked as GitHub issues)

| # | Issue | Area | Finding | Severity |
|---|-------|------|---------|----------|
| I1 | [#1](https://github.com/Spotnick2/AltTracker/issues/1) | Account Summary | Rested XP renders red **0%** for level-70 characters where rested XP is N/A (`RowRenderer.lua:840`); the red reads as an error. Suggest a dim "—" at max level. | Med |
| I2 | [#2](https://github.com/Spotnick2/AltTracker/issues/2) | Gear Progression | BiS green ✓ (`RowRenderer.lua:823-826`) and the `BiS %` column have no legend/affordance; meaning is undiscoverable without hovering. | Med |
| I3 | [#3](https://github.com/Spotnick2/AltTracker/issues/3) | Skills | Profession columns are icon-only; low skill values render red (reads as an error). Add a legend / clarify color semantics; riding columns are especially opaque. | Med |
| I4 | [#4](https://github.com/Spotnick2/AltTracker/issues/4) | Options | "Preview debug mode (AltTracker Roster)" developer diagnostic is exposed to all users (`SheetUI.lua:2052-2082`). Hide behind an advanced/debug gate or remove. | Med |
| I5 | [#5](https://github.com/Spotnick2/AltTracker/issues/5) | Options | Theme **Dark**/**Class** buttons have no visible active/selected state — can't tell the current selection. | Med |
| I6 | [#6](https://github.com/Spotnick2/AltTracker/issues/6) | Sidebar | Plugin tab labels (Recipes/Roster) are colored differently than built-in tabs (`MakePluginButton` vs the built-in tab loop) — inconsistent nav. | Low |
| I7 | [#7](https://github.com/Spotnick2/AltTracker/issues/7) | Recipes _(plugin)_ | Legend uses Unicode `✓`/`✗` (`AltTrackerProfessions.lua:1197`) that render as missing-glyph boxes in the default font, and can't match the ReadyCheck **textures** the grid actually uses (`:853-854`, `:1613-1624`); every not-learned cell also draws a dim red X with no cell tooltip. Root cause detailed in the issue. | Med |
| I8 | [#8](https://github.com/Spotnick2/AltTracker/issues/8) | Reputations | Footer replaces the char/level/gold totals with the standing legend (`UpdateTotalsBar` `SheetUI.lua:1027-1041`) — inconsistent with every other tab. Consider moving the legend to a tooltip/inline strip. | Low |
| I9 | [#9](https://github.com/Spotnick2/AltTracker/issues/9) | Headers | C/S/R and icon-only headers rely entirely on hover tooltips (`COL_TOOLTIPS`, `SheetUI.lua:1210`); no persistent cue for new users. | Low |

### Plugin findings (Recipes & Roster)

| # | Area | Finding | Severity |
|---|------|---------|----------|
| [#10](https://github.com/Spotnick2/AltTracker/issues/10) | Recipes | Section header count not pluralized → "(1 recipes)" (`AltTrackerProfessions.lua:1485`). | Low |
| [#11](https://github.com/Spotnick2/AltTracker/issues/11) | Recipes | "Clear" button (`UIPanelButtonTemplate`) and missing-only checkbox (`UICheckButtonTemplate`) are stock Blizzard controls in a custom flat-dark theme — the Clear button is the source of the "red" look (`:1219-1235`). | Med |
| [#12](https://github.com/Spotnick2/AltTracker/issues/12) | Recipes | Typing in search silently mutates the profession + expansion filters (`MaybeAutoContextSearch` `:752-804`). | Med |
| [#13](https://github.com/Spotnick2/AltTracker/issues/13) | Recipes | Confusing expansion labels ("World of Warcraft" = Classic) + item-ID-threshold expansion guessing (`:1243-1259`, `:75`). | Low |
| [#14](https://github.com/Spotnick2/AltTracker/issues/14) | Roster | Pluralization/format: "1 chars", "1 total levels", "Ready in 0m" (`AltTrackerRoster.lua:762, 2838`, `DurationText :381-390`). | Low |
| [#15](https://github.com/Spotnick2/AltTracker/issues/15) | Roster | Long names/realm/spec truncate with no tooltip; iLvl/GS shown bare with no explanation; only gear buttons have tooltips (`:649-833, 862-895`). | Med |
| [#16](https://github.com/Spotnick2/AltTracker/issues/16) | Both | Activating a plugin hard-resizes the shared window and never restores it (`AltTrackerProfessions.lua:1663`, `AltTrackerRoster.lua:3425`; neither `Deactivate` restores). | Med |
| [#17](https://github.com/Spotnick2/AltTracker/issues/17) | Roster | Dead/duplicate code: orphan `AltTrackerRosterModel.lua` (~128 KB, not in `.toc`) + stale git-tracked `AltTrackerAlts.*` / `alts.tga` files. | Low |
| [#18](https://github.com/Spotnick2/AltTracker/issues/18) | Roster | Many hardcoded colors bypass the theme palette, so the tab won't follow accent/theme changes (`:2711, 2769, 3198-3290`, footer greys `:2838`). | Low |

## Per-screen notes

### Account Summary
Clean and readable. Rested-XP color semantics (I1) and the last-online grammar (fixed)
were the only real issues. Gold column with coin icons is legible; single-letter C/S/R
headers are covered by tooltips (see I9).

### Gear Progression
The densest screen (~20 gear-slot columns + BiS). This is where the gridline weight was
most noticeable — addressed. Remaining gap is the undiscoverable BiS ✓ / % (I2). Item-level
quality coloring reads well.

### Skills
Profession/skill grid is functional; icon-only headers and red-for-low values are the
clarity gap (I3).

### Reputations
Has a good color-coded standing legend — but it lives in the footer and displaces the
totals shown elsewhere (I8). Single-letter standings are compact and readable.

### Recipes _(plugin — `C:\Projects\AltTrackerProfessions`)_
Strong feature set (AH vs craft price, expansion/profession filters, per-character learned
state, collapsible profession sections). Audited at source. Findings:
- **Legend/marks mismatch (#7):** the legend is Unicode `✓`/`✗` text (`:1197`) that renders
  as boxes, while the grid uses ReadyCheck **textures** (`:853-854`) — the key can never match
  the marks. The plugin already avoids Unicode elsewhere for exactly this reason (`:982-984`).
- **Grid noise (#7):** dim red X on every not-learned cell (`:1620-1622`) plus multi-signal row
  de-emphasis (darker bg + desaturated icons + greyed text) makes a sparse account a wall of
  faint red; the cells have no tooltip to disambiguate learned / not-learned / no-data.
- **Off-theme controls (#11):** "Clear" (`UIPanelButtonTemplate`) and the missing-only checkbox
  (`UICheckButtonTemplate`) are the only stock Blizzard controls in the panel — that's why Clear
  looks "red."
- **Hidden filter mutation (#12)** and **confusing expansion labels (#13)**.
- **"(1 recipes)" (#10).** Minor extras (audit-only): `FormatMoney` drops copper in the gold
  branch and always shows silver even when 0 (`:197-209`); dead `% known` column widgets remain.
- Clean on debug: no user-facing debug toggles in this plugin.

### Roster _(plugin — `C:\Projects\AltTrackerRoster`)_
The most polished screen — offline "card" (or live 3D model on the current character) with
per-slot item levels, a detail panel (Character / Reputations / Professions tabs) covering
Status/Resources/Attributes/Combat, account grouping, and a totals footer. Audited at source.
Findings:
- **Pluralization/format (#14):** "1 chars", "1 total levels", "Ready in 0m".
- **Truncation + sparse tooltips (#15):** long names/guild/realm/spec are cut with no hover
  fallback; only gear buttons have tooltips; iLvl and GearScore are unexplained.
- **Window not restored (#16)** — shared with Recipes.
- **Debug UI reachable by users:** the "Preview debug mode" checkbox (tracked as I4/#4 in the
  main addon) overlays `Debug: …` text on the card and opens a diagnostics window.
- **Dead/duplicate code (#17)** and **hardcoded colors bypassing the theme (#18).**
- Performance smell (audit-only): every row hover re-runs the full `RenderSelector()` relayout.

### Options
Well-organized into Appearance / Roster / Presentation / Account & Sync / Sync Peers /
Toasts. Two fixes needed: the exposed debug toggle (I4) and the missing theme active
state (I5). Checkbox styling is consistent.

## Verification of the fixes in this pass

WoW addons have no automated test path. To verify:

1. Deploy changed `.lua` files to the AddOns folder and `/reload` in-game.
2. Open with `/alts` and confirm:
   - Vertical gridlines are faint, neutral (no blue tint), and continuous across rows;
     header and body match. Tune `GRIDLINE` alpha (0.08–0.18) in `Theme.lua` to taste.
   - "Last Online" shows "1 day" / "1 week" (not "1 days" / "1 weeks").

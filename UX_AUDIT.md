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
runtime via `AltTracker.RegisterPlugin`; their UI code is _not_ in this repository, so
those two screens were audited from screenshots only. Fixes for them likely live in the
respective plugin addons.

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
| I7 | [#7](https://github.com/Spotnick2/AltTracker/issues/7) | Recipes _(plugin)_ | learned/not-learned glyph legend is hard to distinguish; the grid is dominated by bright red ✗ noise for normal "not learned" state — soften it. | Low |
| I8 | [#8](https://github.com/Spotnick2/AltTracker/issues/8) | Reputations | Footer replaces the char/level/gold totals with the standing legend (`UpdateTotalsBar` `SheetUI.lua:1027-1041`) — inconsistent with every other tab. Consider moving the legend to a tooltip/inline strip. | Low |
| I9 | [#9](https://github.com/Spotnick2/AltTracker/issues/9) | Headers | C/S/R and icon-only headers rely entirely on hover tooltips (`COL_TOOLTIPS`, `SheetUI.lua:1210`); no persistent cue for new users. | Low |

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

### Recipes _(external plugin)_
Strong feature set (AH vs craft price, expansion/profession filters, per-character
learned state). Clarity gaps: the learned/not-learned glyph legend and heavy red-X noise
(I7). The red "Clear" button reads as destructive for what is just a search reset — minor.

### Roster _(external plugin)_
The most polished screen — 3D model with per-slot item levels, a detail panel with
Status/Resources/Attributes/Combat, and account grouping. No blocking issues; lower
stats scroll off the bottom of the detail panel (expected).

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

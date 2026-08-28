# Reference images

Fallback reference images for the HeroShot render pipeline. The image model anchors on the visible
reference over any text instruction, so whatever lands here *is* the gear the portrait will show.

## Where references come from now

The pipeline resolves a reference in this order (`HeroShotRenderAdapter.ResolveReferenceImagePath`):

0. **Battle.net armory render** — fetched automatically and re-fetched whenever the character logs
   out in new gear. Self-refreshing and always accurate.
1. Fresh in-game capture (`/alts updateref`, matched by `refshot_ts`).
2. Explicit `HeroShot.CharacterReferenceImages` override in `appsettings.json`.
3. **This folder**, by convention: `<realm>_<account>_<name>.png`.

For any character Blizzard renders, tier 0 wins and nothing here is ever read.

## So why is anything still here?

**Blizzard does not generate renders below level 10.** Bank mules and fresh alts get no armory
render at all, so this folder is their only possible reference — and with
`RequireReferenceImage: true`, a character with nothing here is skipped rather than rendered from
text alone.

That is the entire remaining purpose. The files for characters that *do* have armory renders were
removed in the same change that added the level gate: they were four months stale, permanently
shadowed, and would have quietly reintroduced out-of-date gear if the armory path ever fell through
to them.

## Adding one

Drop a `<realm>_<account>_<name>.png` here — a full-body shot, character roughly centred. Only worth
doing for characters under level 10; anything else is better served by logging the character out so
Blizzard regenerates its render.

# Roster "Scene" backdrops

Backdrops for the Roster plugin's **Scene** (Midnight-style character-select) view — the
camp scenes the alt cutouts stand in front of. This folder holds both the **source PNGs**
(`*-campsite.png`, the generator output) and the **deployed WoW textures** (`scene-*.tga`,
what the addon actually loads).

To add a new backdrop you: (1) generate a PNG to spec, (2) convert it to a `scene-*.tga`,
(3) register it in `RosterScene.lua`, (4) deploy. Details below.

---

## 1. Generating the image (spec)

Generate a **landscape 3:2 PNG, ideally 1536×1024**. Every backdrop follows the same recipe
— an empty camp in the foreground with a landmark blurred behind it:

> **Empty scene — NO characters, NO people, NO creatures.** Keep the **center-foreground
> open and clear** (the alts stand there). A small **campfire / cook-pot glowing at the
> lower-center** as the warm light source. The landmark (raid entrance, zone, city…) sits in
> the **background, heavily depth-of-field blurred / soft bokeh**. **No text, no UI, no
> watermark.** Wide **landscape** composition, horizon in the lower third. Cinematic game
> key-art, like the World of Warcraft character-select screen.

Composition rules that make it read well behind the carousel:

- **Campfire low-center**, foreground **open and empty** (that's where the characters are).
- **Landmark blurred in the background** — recognizable silhouette, not sharp detail.
- **Darker vignette at the edges** so the bright character cutouts pop (daytime scenes can be
  brighter, but still keep the edges a touch darker and the center-foreground clear).
- Keep the important content (campfire + landmark) **horizontally centered** — the in-game
  crop trims the sides on narrow panels and the top on tall ones (see §2).

### Per-scene descriptor

Append the scene's own line to the shared recipe. Examples we've shipped:

- **Forest Camp** — night forest clearing, blurred pines, drifting fog.
- **Karazhan** — Deadwind Pass at night, the haunted gothic tower/spire looming in purple-black
  storm clouds, dead trees.
- **Dark Portal** — Blasted-lands/Hellfire, the fel-green portal + hooded stone guardians,
  volcanic red-black terrain.
- **Sunwell Plateau** — Isle of Quel'Danas, blood-elf gold spires, the Sunwell's radiant light
  beam, twilight coast.
- **Zangarmarsh** — glowing giant mushrooms, blue nether haze, Coilfang reservoir + water.
- **Zul'Aman** — Amani troll temple, mossy stone architecture, tusk totems, waterfalls, jungle.
- **Black Temple** — Illidan's fortress interior/den, dark stone, red drapes, blue crystal light.
- **Shattrath** — the naaru city, terraced Aldor/Scryer architecture, warm dusk light.

---

## 2. Converting to a WoW texture (`scene-*.tga`)

WoW's texture loader is picky. Through hard experience these three things are **required**,
or the backdrop renders **black** (often only after a `/reload`, working on a cold boot):

1. **32-bit** (RGBA / `srgba`) — 24-bit `srgb` TGAs load black. (This is why the character
   cutouts always worked and the first backdrops didn't.)
2. **Power-of-two dimensions** — we use **1024×1024**. Oversized / non-power-of-two textures
   reload unreliably. The 3:2 image goes in the **top 682 rows**; the bottom is black-padded,
   and the addon remaps the texture coords so the padding is never shown (see §3).
3. **A fresh filename whenever the pixels change** — WoW caches textures by path and a
   `/reload` won't re-read an overwritten file. If you replace a `scene-*.tga` in place, bump
   its name (or do one full client restart to flush the cache).

Conversion command (ImageMagick 7 — `magick`):

```bash
magick <name>-campsite.png \
  -resize 1024x682! -background black -gravity north -extent 1024x1024 \
  -alpha set -type TrueColorMatte -compress none \
  scene-<id>.tga
```

- `-resize 1024x682!` → force the image into the 3:2 content box.
- `-gravity north -extent 1024x1024` → place it at the top of a 1024×1024 canvas, pad below.
- `-alpha set -type TrueColorMatte` → **32-bit** (the critical bit).
- `-compress none` → uncompressed TGA (what WoW reads).

Sanity-check: `magick identify -format "%wx%h %[channels]\n" scene-<id>.tga` must print
`1024x1024 srgba 4.0`.

> If you generate many at once, this is exactly what a `Tools/scene_backdrops.py` auto-discover
> script would automate (scan `*-campsite.png` → emit `scene-*.tga` + a manifest). Not built
> yet — see the note in `RosterScene.lua`.

---

## 3. Registering it in the addon

Add one entry to the `SCENE_BACKDROPS` table near the top of
`Plugins/Roster/RosterScene.lua` (before the `plain` entry):

```lua
{ id = "<id>", label = "<Display Name>",
  file = "Interface\\AddOns\\AltTracker\\Media\\Scene\\scene-<id>.tga", w = 1024, h = 682, texh = 1024 },
```

- `id` — stable key, persisted as the user's choice (`AltTrackerRosterDB._ui.sceneBackdrop`).
- `label` — shown in the ◄/► picker.
- `w`, `h` — the **image (content)** dims, 1024×682 for the standard crop.
- `texh` — the **texture's** full height, 1024 (the addon remaps `v` by `h/texh` so the black
  padding never shows). Omit `texh` only for a texture with no padding.

The picker order in-scene follows the table order.

---

## 4. Deploying

```powershell
pwsh Tools/deploy.ps1
```

Then `/reload` in-game → Roster → **Scene**, and cycle the ◄/► picker to the new backdrop.
If a just-replaced backdrop still shows black, do one **full client restart** (flushes the
texture cache) — new/renamed files don't need it.

---

## Naming convention

| Kind          | Pattern                    | Example                        | In repo? |
|---------------|----------------------------|--------------------------------|----------|
| Source PNG    | `<name>-campsite.png`      | `karazhan-campsite.png`        | yes      |
| WoW texture   | `scene-<id>.tga`           | `scene-karazhan.tga`           | yes      |

`<id>` in the texture name should match the `id` used in `SCENE_BACKDROPS`.

# AltTracker.RenderPipeline (MVP)

This tool reads **AltTracker SavedVariables** (`AltTracker.lua`) and produces deterministic offline render outputs + `AltTrackerRenderManifest.lua` entries for the addon.

## Render input data flow

Source of truth is `AltTrackerDB` from SavedVariables. For each character, the pipeline extracts:

- `realm`, `account`, `name`
- `faction`, `race`, `gender`, `class`, `level`
- `lastUpdate` timestamp
- equipped `gear item IDs` by slot (`gearid_*`, with item-link fallback extraction)
- equipped `gear links` by slot (if present)
- computed `gearHash`

The required model inputs are surfaced in job artifacts:

- `race`
- `gender`
- `gear item IDs` by slot

## Manual WMVx staging workflow (current realistic MVP)

1. Run pipeline to generate render jobs.
2. Open `jobs.json` and `jobs-checklist.csv` in the temp folder.
3. In WMVx, render one character per row.
4. Export images into staging folder using the expected staging filename from artifacts.
5. Re-run pipeline to convert/publish `.tga` and write manifest.

### WMVx client/profile policy

- Render source does **not** need to match WoW Classic exactly.
- Prefer `WmvxPolicy.PreferredClientProfile` (default `Retail`).
- If unavailable, use `WmvxPolicy.FallbackClientProfile` (default `Midnight`).
- If `AllowAnyWorkingClientProfile=true`, any WMVx-supported profile that can render the character is acceptable.
- If a TBC item ID cannot be rendered in that profile, apply `MissingItemPolicy`:
  - `skip` (default): omit that item from the composed visual.
  - `placeholder`: use a visible placeholder and note it in operator logs.

Final output is still a static `.tga` consumed by AltTracker.

## WowConverter backend (automated export + screenshot)

`RenderBackend` can be switched to `WowConverter` to automate render staging:

1. Submit export to `POST /api/export/character`
2. Poll `GET /api/export/character/status/{id}`
3. Resolve exported `.mdx`
4. Capture PNG from `/viewer?model=<...>` with Playwright
5. Continue existing `.png -> .tga -> manifest` flow

MVP expects wow.export + wow-converter servers to already be running. If endpoints are unavailable, jobs fail with explicit per-job errors.

### Required startup sequence (bundled wow.export + wow-converter)

Use the wow.export bundled with the same wow-converter release folder (recommended stable path: `C:\Tools\wow-converter-1.1.11`).

For this backend, treat bundled wow.export as a pre-initialized dependency:

1. Start bundled `C:\Tools\wow-converter-1.1.11\wow.export.exe`.
2. Click **Open Local Installation**.
3. Select `C:\Program Files (x86)\World of Warcraft`.
4. Select/load the Anniversary/TBC Anniversary build/product in wow.export.
5. Leave wow.export running.
6. Start bundled `C:\Tools\wow-converter-1.1.11\wow-converter.exe`.
7. Run `AltTracker.RenderPipeline`.

The adapter preflight calls:

`GET <WowExportUrl>/rest/getCascInfo`

and logs:

- wow.export URL
- wow.export process ID/path (when resolvable)
- product
- version
- wow.export version (if exposed)
- buildName
- buildKey
- locale

If wow.export is not initialized (no loaded CASC info), the pipeline fails before export with a setup message.
If active wow.export does not come from the configured wow-converter folder, the preflight logs a loud path mismatch warning.

### Base model identity guard (race/gender fallback detection)

WowConverter jobs now fail before render publish if export logs indicate a base-model mismatch versus source character race/gender (for example fallback to `race=1` human male for a non-human character).

Per-job debug payloads are written under:

`<TempPath>\wowconverter-debug\*_<manifestKey>_<character>_request.json`

### Wowhead URL namespace matters (important)

For `InputOverrides` / fallback URLs, the Wowhead namespace must match your target data context.

- Preserve namespace exactly as provided (`/classic`, `/tbc`, `/wotlk`, `/mop-classic`, or retail root).
- Do **not** rewrite/strip namespace paths before submit.
- The adapter logs the exact URL sent to wow-converter.
- Wrong namespace can produce wrong race/gender/items or export failures.

Recommended override format:

- Classic Era / Anniversary-style characters: `https://www.wowhead.com/classic/dressing-room#...`
- TBC-specific pages/gear: use matching TBC namespace URLs when the page/tool supports it.
- Do not use retail dressing-room URLs unless intentionally rendering against retail data.

### Temporary input mapping

Automatic `RenderJob -> wow-converter input` mapping is not finalized yet. Current MVP supports:

- `WowConverter.InputOverrides` (per manifest key / base name / character name)
- `WowConverter.GlobalInputFallback`

Accepted base input forms (validated by API + UI schema):

- Wowhead URL (`/npc=`, `/item=`, `/object=`, `/dressing-room#...`) -> `type=wowhead`
- Numeric display ID (digits only) -> `type=displayID`
- Local model path (`.obj`, `.m2`, `.wmo`, or local path-like input) -> `type=local`

Direct raw character JSON (`race/gender/class/items` without `character.base`) is **not** accepted by `/api/export/character`.

This enables tested dressing-room inputs while preserving pipeline structure for future automatic mapping.

`jobs.json` and `jobs-checklist.csv` include, per character:

- realm/account/name/class/race/gender/level
- manifest key
- gear hash
- all gear item IDs and links
- expected staging filename
- final addon filename/path
- WMVx client/profile + missing-item policy

## Config: render spec

`appsettings.json` includes:

```json
"RenderSpec": {
  "Width": 512,
  "Height": 512,
  "PreferTransparentBackground": true,
  "BackgroundColorFallback": "#141414",
  "FramingPreset": "fullbody_center_v1",
  "PreferredStagingExtension": ".png"
},
"WmvxPolicy": {
  "PreferredClientProfile": "Retail",
  "FallbackClientProfile": "Midnight",
  "AllowAnyWorkingClientProfile": true,
  "MissingItemPolicy": "skip",
  "PlaceholderLabel": "missing-item"
},
"WowConverter": {
  "WowExportUrl": "http://127.0.0.1:17752",
  "ConverterUrl": "http://127.0.0.1:3001",
  "ExpectedWowExportProduct": "anniversary",
  "ExpectedWowExportVersionContains": "0.2.15",
  "RequireExpectedWowExportProduct": false,
  "WowExportExecutablePath": "C:\\Tools\\wow-converter-1.1.11\\wow.export.exe",
  "ConverterExecutablePath": "C:\\Tools\\wow-converter-1.1.11\\wow-converter.exe",
  "ExportedAssetsPath": "C:\\Tools\\wow-converter-1.1.11\\exported-assets",
  "NodeExecutable": "node",
  "NpmExecutable": "npm",
  "NpxExecutable": "npx.cmd",
  "PlaywrightScriptPath": "",
  "ScreenshotWidth": 1400,
  "ScreenshotHeight": 1000,
  "ViewerWaitTimeoutSeconds": 45,
  "ExportTimeoutSeconds": 120,
  "PollIntervalMilliseconds": 100,
  "CaptureTarget": "canvas",
  "IncludeTextures": true,
  "RemoveUnusedMaterialsTextures": true,
  "GlobalInputFallback": "",
  "InputOverrides": {}
}
```

- `ExpectedWowExportProduct`: optional token that must appear in product/build (ex: `anniversary`, `tbc`, `wow_classic`).
- `ExpectedWowExportVersionContains`: optional token that must appear in wow.export/CASC version fields (ex: `0.2.15`).
- `RequireExpectedWowExportProduct`: when `true`, expected-product/version mismatches fail preflight instead of warning.

- Final output is always `.tga`.
- Render is normalized to configured width/height when converter is available.
- Transparent background is preferred; dark fallback color is used when transparency is disabled.

### Texture/material validation

WowConverter jobs fail (per-job) if texture/material signals indicate an untextured mannequin render, including:

- exported texture count is zero
- viewer texture asset requests fail
- viewer shows no texture asset requests
- captured image has very low color/material variance (white/gray untextured look)

## HeroShot backend (AI-generated hero portraits)

The `HeroShot` backend generates full-body character portraits via the OpenAI Images API (supports `gpt-image-1` and `dall-e-3`).

### Setup

**1. Set your API key:**

```powershell
$env:ALTRACKER_HEROSHOT_API_KEY = 'sk-...'
```

**2. Configure `appsettings.json`:**

```json
"RenderBackend": "HeroShot",
"HeroShot": {
  "Enabled": true,
  "Style": "realistic",
  "Width": 1024,
  "Height": 1792,
  "OutputFormat": "png",
  "OutputWidth": 512,
  "OutputHeight": 896,
  "CropMode": "cover",
  "Anchor": "center",
  "Format": "tga",
  "Provider": "openai",
  "Model": "gpt-image-1",
  "PromptTemplateVersion": "v1",
  "GenerationVersion": "1",
  "ApiBaseUrl": "https://api.openai.com/v1",
  "ApiKeyEnvVar": "ALTRACKER_HEROSHOT_API_KEY",
  "ReferenceImagesPath": "C:\\Temp\\AltTrackerHeroShot\\ReferenceImages",
  "TimeoutSeconds": 120,
  "MaxRetries": 2,
  "CharacterReferenceImages": {
    "Dreamscythe:1:Kaleid": "C:\\Path\\To\\reference.png"
  }
}
```

**3. (Optional) Reference images:**

Place a reference image at `{ReferenceImagesPath}/{outputBaseName}.png` or configure per-character overrides in `CharacterReferenceImages`.  
When a reference image is found and the model is `gpt-image-1`, the `/v1/images/edits` endpoint is used; otherwise `/v1/images/generations` is called.
Set `Provider` to `manual` to import the reference image directly (png/jpg/jpeg/tga) without AI generation.

### Style presets

| Style | Description |
|---|---|
| `realistic` | Photorealistic fantasy concept art, cinematic lighting, 8K (default) |
| `wow-like` | Semi-realistic WoW-style art, vibrant, heroic proportions |
| `cartoonish` | Stylized cartoon, bold outlines, saturated colors |

Override style at runtime:
```powershell
dotnet run ... -- --heroshot-style wow-like
```

### Caching / skip logic

The adapter computes a deterministic SHA-256 signature covering character identity, race/gender/class, gear item IDs, style, model, and output dimensions. If the signature matches the prior state and both the staging file and final output exist, generation is skipped. Use `--force-all` to regenerate unconditionally. State is persisted to `{TempPath}/heroshot/*.heroshot-state.json`.

### Run hero shot for Kaleid

```powershell
$env:ALTRACKER_HEROSHOT_API_KEY = 'sk-...'
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --render-backend HeroShot --character "Dreamscythe:1:Kaleid" --verbose
```

Dry-run (no API calls):
```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --render-backend HeroShot --dry-run --verbose
```

## Example commands

Generate jobs only (safe planning run):

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --dry-run --verbose
```

Interactive character selector (choose all / selected / stale-only):

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --render-backend HeroShot --interactive --verbose
```

Generate dry-run with WowConverter backend:

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --dry-run --render-backend WowConverter --verbose
```

Run one real WowConverter job with temporary input fallback:

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --render-backend WowConverter --character "Dreamscythe:1:Kaleid" --converter-input-fallback "<wowhead-input>" --verbose
```

Publish all pending rerenders:

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --verbose
```

Force rerender one character key:

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --character "Dreamscythe:1:Kaleid" --verbose
```

Force rerender all:

```powershell
dotnet run --project .\Tools\AltTracker.RenderPipeline -- --force-all --verbose
```

## In-game validation checklist

1. Run pipeline and confirm `.tga` output under `Media\CharacterRenders`.
2. Confirm manifest contains matching `Realm:Account:Character` key and image path under `Interface\AddOns\...`.
3. In WoW, run `/reload`.
4. Verify:
   - current player uses live model,
   - offline character with manifest entry shows static render,
   - offline character without entry shows offline identity card.

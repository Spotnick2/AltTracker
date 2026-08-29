#!/usr/bin/env python3
"""
scene_cutouts.py — produce transparent character cutouts for the Roster "Scene" (Campsite) view.

Phase B of the Midnight-style scene. This is a deliberately SEPARATE, decoupled step from the
.NET render pipeline: it does NOT touch that pipeline's manifest, gear hashes or state, so the
List-view heroshot portraits are never modified.

Cutouts come from one of two sources, in order:

  1. The cached Battle.net armory render, when the pipeline has downloaded one. It is already a
     transparent PNG of exactly this character's gear, so the cutout is just an alpha-bbox trim —
     pixel-perfect edges, no segmentation model, no guesswork.
  2. Otherwise the opaque 512x896 AI hero shot, cut out with a segmentation model
     (rembg / isnet-general-use). The model is loaded lazily, so a run fully covered by armory
     renders never pays for it.

Output:
  * <addon>/Media/SceneCutouts/<base>.tga   — 32-bit alpha cutout, trimmed to the character bbox
  * <addon>/AltTrackerSceneManifest.lua      — Realm:Account:Name -> { image, width, height }
  * <repo>/AltTrackerSceneManifest.lua        — committed snapshot (mirrors the render manifest pattern)

Requires: rembg + onnxruntime (pip), Pillow, and ImageMagick (`magick`) for the final TGA encode
(the same encoder the render pipeline trusts for WoW-readable TGAs).

Usage (from the repo root or anywhere):
    python Tools/scene_cutouts.py                 # all characters in the render manifest
    python Tools/scene_cutouts.py --only spotnick # just matching base name(s)
    python Tools/scene_cutouts.py --model isnet-general-use
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
# ALTTRACKER_APPSETTINGS points the tool at a different config - used by the tests to run
# against a sandbox tree instead of the real WoW install.
APPSETTINGS = (os.environ.get("ALTTRACKER_APPSETTINGS")
               or os.path.join(HERE, "AltTracker.RenderPipeline", "appsettings.json"))

MANIFEST_ENTRY_RE = re.compile(r'\["(?P<key>[^"]+)"\]\s*=\s*\{(?P<body>.*?)\}', re.DOTALL)
FIELD_RE = lambda name: re.compile(name + r'\s*=\s*"(?P<v>[^"]*)"')


def load_paths():
    with open(APPSETTINGS, "r", encoding="utf-8-sig") as f:
        cfg = json.load(f)
    render_dir = cfg["AddonMediaDirectory"]                    # .../AltTracker/Media/CharacterRenders
    addon_root = os.path.dirname(os.path.dirname(render_dir))  # .../AltTracker

    # Where the .NET pipeline caches raw armory renders. Read straight from the cache rather
    # than from a sidecar written per run: the render adapter only ever sees the jobs it was
    # given, so anything it emitted would omit every character not in that run.
    bnet = cfg.get("BattleNet") or {}
    armory_cache = bnet.get("CacheDirectory") or os.path.join(cfg.get("TempPath", ""), "blizzard")

    return {
        "render_dir": render_dir,
        "armory_cache": armory_cache,
        "addon_root": addon_root,
        "scene_dir": os.path.join(addon_root, "Media", "SceneCutouts"),
        "render_manifest": cfg["ManifestOutputPath"],
        "scene_manifest_deployed": os.path.join(addon_root, "AltTrackerSceneManifest.lua"),
        # Committed snapshot. Configurable rather than always REPO_ROOT: the path is derived from
        # this script's location, so without an override a run pointed at a sandbox config would
        # still write into the real repo.
        "scene_manifest_repo": cfg.get("SceneManifestRepoPath")
                               or os.path.join(REPO_ROOT, "AltTrackerSceneManifest.lua"),
    }


def parse_render_manifest(path):
    """Return [(key, base_filename)] from the render manifest — the character keys and their portraits."""
    with open(path, "r", encoding="utf-8-sig") as f:
        text = f.read()
    out = []
    for m in MANIFEST_ENTRY_RE.finditer(text):
        key, body = m.group("key"), m.group("body")
        img = FIELD_RE("image").search(body)
        if not img:
            continue
        base = re.split(r"\\+", img.group("v"))[-1]  # last path segment (double-backslash separated)
        out.append((key, base))
    return out


def find_armory_render(cache_dir, base_noext):
    """Cached raw armory render for a character, or None.

    Cache files are '<base>-<hash>.png' for the raw render and
    '<base>-<hash>-reference-<...>.png' for the prepared model reference; only the raw render is
    a clean transparent cutout of the character, so the reference variants are excluded.
    """
    if not cache_dir or not os.path.isdir(cache_dir):
        return None
    prefix = base_noext + "-"
    best = None
    for name in os.listdir(cache_dir):
        if not name.startswith(prefix) or not name.endswith(".png"):
            continue
        if "-reference-" in name:
            continue
        full = os.path.join(cache_dir, name)
        if best is None or os.path.getmtime(full) > os.path.getmtime(best):
            best = full
    return best


def encode_tga(img, out_tga, magick):
    """Trim to the alpha bbox and write a 32-bit uncompressed TGA. Returns (width, height)."""
    bbox = img.getchannel("A").getbbox() if img.mode == "RGBA" else img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp_png = tf.name
    try:
        img.save(tmp_png)                        # PNG keeps the alpha losslessly
        os.makedirs(os.path.dirname(out_tga), exist_ok=True)
        # Encode with the same tool the render pipeline uses (WoW-readable, alpha kept).
        subprocess.run([magick, tmp_png, "-compress", "none", out_tga], check=True,
                       capture_output=True)
    finally:
        try: os.remove(tmp_png)
        except OSError: pass
    return w, h


def cut_from_armory(src_png, out_tga, magick):
    """Armory renders already carry a real alpha channel — trim it, no segmentation needed."""
    from PIL import Image
    return encode_tga(Image.open(src_png).convert("RGBA"), out_tga, magick)


def cut_one(session, src_tga, out_tga, magick):
    """Segment -> trim to character bbox -> write a 32-bit alpha TGA. Returns (width, height)."""
    from rembg import remove
    from PIL import Image

    img = Image.open(src_tga).convert("RGBA")
    cut = remove(img, session=session)          # plain segmentation (alpha matting hurt dark robes)
    return encode_tga(cut, out_tga, magick)


def parse_scene_manifest(path):
    """Existing scene manifest as {key: (base, width, height)}, or {} when absent."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            text = f.read()
    except OSError:
        return {}
    out = {}
    for m in MANIFEST_ENTRY_RE.finditer(text):
        key, body = m.group("key"), m.group("body")
        img = FIELD_RE("image").search(body)
        w = FIELD_RE("width").search(body)
        h = FIELD_RE("height").search(body)
        if not (img and w and h):
            continue
        base = re.split(r"\\+", img.group("v"))[-1]  # same backslash split as parse_render_manifest
        out[key] = (base, w.group("v"), h.group("v"))
    return out


def lua_escape_path(base):
    return "Interface\\\\AddOns\\\\AltTracker\\\\Media\\\\SceneCutouts\\\\" + base


def write_scene_manifest(path, entries):
    lines = ["AltTrackerSceneManifest = {"]
    for key, base, w, h in entries:
        lines.append(f'    ["{key}"] = {{')
        lines.append(f'        image = "{lua_escape_path(base)}",')
        lines.append(f'        width = "{w}",')
        lines.append(f'        height = "{h}",')
        lines.append('        mode = "cutout",')
        lines.append("    },")
    lines.append("}")
    lines.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="isnet-general-use")
    ap.add_argument("--only", default=None, help="only process base names containing this substring")
    ap.add_argument("--magick", default="magick")
    ap.add_argument("--source", choices=("ai", "armory"), default="ai",
                    help="cutout source: 'ai' segments the hero shot (default, matches the "
                         "painted look of the List view); 'armory' trims the Battle.net render's "
                         "real alpha (exact gear, but the raw in-game model)")
    args = ap.parse_args()

    paths = load_paths()
    if not os.path.exists(paths["render_manifest"]):
        print(f"ERROR: render manifest not found: {paths['render_manifest']}", file=sys.stderr)
        return 2

    chars = parse_render_manifest(paths["render_manifest"])
    if args.only:
        chars = [(k, b) for (k, b) in chars if args.only.lower() in b.lower()]
    if not chars:
        print("No characters to process.", file=sys.stderr)
        return 1

    # The segmentation model is expensive to load and is only needed for characters with no
    # armory render, so it is created on first actual use rather than up front.
    session_holder = {}

    def get_session():
        if "s" not in session_holder:
            from rembg import new_session
            print(f"  (loading segmentation model: {args.model})")
            session_holder["s"] = new_session(args.model)
        return session_holder["s"]

    print(f"characters: {len(chars)}; source: {args.source}")

    # Start from what is already on disk so a filtered run updates its own entries instead of
    # dropping every character it did not touch.
    merged = parse_scene_manifest(paths["scene_manifest_deployed"]) \
             or parse_scene_manifest(paths["scene_manifest_repo"])
    # Preferred source first, the other as fallback: AI -> armory, or armory -> AI.
    order = ("ai", "armory") if args.source == "ai" else ("armory", "ai")
    produced, from_armory, from_model, removed = 0, 0, 0, 0

    for key, base in chars:
        base_noext = os.path.splitext(base)[0]
        out_base = base_noext + ".tga"
        out = os.path.join(paths["scene_dir"], out_base)

        src = os.path.join(paths["render_dir"], base)
        armory = find_armory_render(paths["armory_cache"], base_noext)

        # Only the sources that actually have material for this character.
        available = {}
        if os.path.exists(src):
            available["ai"] = lambda: cut_one(get_session(), src, out, args.magick)
        if armory:
            available["armory"] = lambda: cut_from_armory(armory, out, args.magick)

        size = origin = None
        for name in order:
            produce = available.get(name)
            if produce is None:
                continue
            try:
                size = produce()
                origin = name
                break
            except Exception as ex:  # noqa: BLE001 - try the next source, then move on
                print(f"  warn {key}: {name} source failed ({ex})")

        if origin is None:
            # Drop any entry carried over from the previous manifest. `merged` starts from what is
            # already on disk, so leaving a stale entry here would keep pointing the addon at an old
            # cutout file and CampHasCutouts would go on choosing cutouts instead of falling back.
            # Only characters this run actually processed are removed; those filtered out by --only
            # are never visited and keep their entries.
            if merged.pop(key, None) is not None:
                removed += 1
            print(f"  skip {key}: no AI portrait and no armory render -> framed card")
            continue

        w, h = size
        if origin == "armory":
            from_armory += 1
        else:
            from_model += 1

        merged[key] = (out_base, str(w), str(h))
        produced += 1
        print(f"  ok   {key} -> SceneCutouts\\{out_base} ({w}x{h}) [{origin}]")

    if not produced and not removed:
        print("No cutouts produced.", file=sys.stderr)
        return 1

    # A run that only REMOVED entries still has to write: those characters must stop being
    # advertised as having cutouts, or the addon keeps loading their stale files.
    if not produced:
        print(f"No cutouts produced; dropping {removed} stale entr(y/ies).", file=sys.stderr)

    entries = [(k, v[0], v[1], v[2]) for k, v in merged.items()]
    entries.sort(key=lambda e: e[0])
    write_scene_manifest(paths["scene_manifest_deployed"], entries)
    write_scene_manifest(paths["scene_manifest_repo"], entries)
    print(f"produced {produced} cutout(s): {from_model} from AI art, {from_armory} from armory renders"
          + (f"; removed {removed} stale entr(y/ies)" if removed else ""))
    print(f"wrote scene manifest ({len(entries)} entries, {len(entries) - produced} carried over):")
    print(f"  deployed: {paths['scene_manifest_deployed']}")
    print(f"  repo:     {paths['scene_manifest_repo']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

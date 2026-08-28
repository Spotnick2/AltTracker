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
APPSETTINGS = os.path.join(HERE, "AltTracker.RenderPipeline", "appsettings.json")

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
        "scene_manifest_repo": os.path.join(REPO_ROOT, "AltTrackerSceneManifest.lua"),
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
        base = re.split(r"\+", img.group("v"))[-1]
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

    print(f"characters: {len(chars)}")

    # Start from what is already on disk so a filtered run updates its own entries instead of
    # dropping every character it did not touch.
    merged = parse_scene_manifest(paths["scene_manifest_deployed"]) \
             or parse_scene_manifest(paths["scene_manifest_repo"])
    produced, from_armory, from_model = 0, 0, 0

    for key, base in chars:
        base_noext = os.path.splitext(base)[0]
        out_base = base_noext + ".tga"
        out = os.path.join(paths["scene_dir"], out_base)

        armory = find_armory_render(paths["armory_cache"], base_noext)
        src = os.path.join(paths["render_dir"], base)

        try:
            if armory:
                w, h = cut_from_armory(armory, out, args.magick)
                origin = "armory"
                from_armory += 1
            elif os.path.exists(src):
                w, h = cut_one(get_session(), src, out, args.magick)
                origin = "model"
                from_model += 1
            else:
                print(f"  skip {key}: no armory render and no source portrait ({base})")
                continue
        except Exception as ex:  # noqa: BLE001 - report and keep going on the rest
            print(f"  FAIL {key}: {ex}")
            continue

        merged[key] = (out_base, str(w), str(h))
        produced += 1
        print(f"  ok   {key} -> SceneCutouts\\{out_base} ({w}x{h}) [{origin}]")

    if not produced:
        print("No cutouts produced.", file=sys.stderr)
        return 1

    entries = [(k, v[0], v[1], v[2]) for k, v in merged.items()]
    entries.sort(key=lambda e: e[0])
    write_scene_manifest(paths["scene_manifest_deployed"], entries)
    write_scene_manifest(paths["scene_manifest_repo"], entries)
    print(f"produced {produced} cutout(s): {from_armory} from armory, {from_model} via the model")
    print(f"wrote scene manifest ({len(entries)} entries, {len(entries) - produced} carried over):")
    print(f"  deployed: {paths['scene_manifest_deployed']}")
    print(f"  repo:     {paths['scene_manifest_repo']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
scene_cutouts.py — produce transparent character cutouts for the Roster "Scene" (Campsite) view.

Phase B of the Midnight-style scene. This is a deliberately SEPARATE, decoupled step from the
.NET render pipeline: it consumes the portraits that pipeline already produced (the opaque
512x896 hero shots) and cuts each character out of its AI-painted background using a segmentation
model (rembg / isnet-general-use). It does NOT touch the render pipeline's manifest, gear hashes,
or state — so the List-view heroshot portraits are never modified.

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
    return {
        "render_dir": render_dir,
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


def cut_one(session, src_tga, out_tga, magick):
    """Segment -> trim to character bbox -> write a 32-bit alpha TGA. Returns (width, height)."""
    from rembg import remove
    from PIL import Image

    img = Image.open(src_tga).convert("RGBA")
    cut = remove(img, session=session)          # plain segmentation (alpha matting hurt dark robes)
    bbox = cut.getbbox()                         # tight bbox of non-transparent pixels
    if bbox:
        cut = cut.crop(bbox)
    w, h = cut.size

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp_png = tf.name
    try:
        cut.save(tmp_png)                        # PNG keeps the alpha losslessly
        os.makedirs(os.path.dirname(out_tga), exist_ok=True)
        # Encode the final TGA with the same tool the render pipeline uses (WoW-readable, alpha kept).
        subprocess.run([magick, tmp_png, "-compress", "none", out_tga], check=True,
                       capture_output=True)
    finally:
        try: os.remove(tmp_png)
        except OSError: pass
    return w, h


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

    from rembg import new_session
    session = new_session(args.model)
    print(f"model: {args.model}; characters: {len(chars)}")

    entries = []
    for key, base in chars:
        src = os.path.join(paths["render_dir"], base)
        if not os.path.exists(src):
            print(f"  skip {key}: source portrait missing ({base})")
            continue
        out_base = os.path.splitext(base)[0] + ".tga"
        out = os.path.join(paths["scene_dir"], out_base)
        try:
            w, h = cut_one(session, src, out, args.magick)
        except Exception as ex:  # noqa: BLE001 — report and keep going on the rest
            print(f"  FAIL {key}: {ex}")
            continue
        entries.append((key, out_base, w, h))
        print(f"  ok   {key} -> SceneCutouts\\{out_base} ({w}x{h})")

    if not entries:
        print("No cutouts produced.", file=sys.stderr)
        return 1

    entries.sort(key=lambda e: e[0])
    write_scene_manifest(paths["scene_manifest_deployed"], entries)
    write_scene_manifest(paths["scene_manifest_repo"], entries)
    print(f"wrote scene manifest ({len(entries)} entries):")
    print(f"  deployed: {paths['scene_manifest_deployed']}")
    print(f"  repo:     {paths['scene_manifest_repo']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

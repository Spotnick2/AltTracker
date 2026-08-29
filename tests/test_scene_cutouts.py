#!/usr/bin/env python3
"""
test_scene_cutouts.py — manifest parse/write round-trip for Tools/scene_cutouts.py.

Plain asserts, no pytest, matching the dependency-free style of the Lua suite next to it.
Run from the repo root:

    python tests/test_scene_cutouts.py
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "Tools"))

import scene_cutouts as sc  # noqa: E402

tests_run = 0
failures = 0


def check(cond, msg):
    global tests_run, failures
    tests_run += 1
    if not cond:
        failures += 1
        print(f"  FAIL: {msg}")


def eq(actual, expected, msg):
    check(actual == expected, f"{msg} (got {actual!r}, want {expected!r})")


def write_temp_manifest(entries):
    fd, path = tempfile.mkstemp(suffix=".lua")
    os.close(fd)
    sc.write_scene_manifest(path, entries)
    return path


# ---------------------------------------------------------------------------
# Round-trip: what write_scene_manifest emits, parse_scene_manifest must read back
# unchanged.
#
# This is the regression that matters. parse_scene_manifest originally split the
# stored path on r"\+" — a regex matching PLUS signs, not backslashes — so the
# value never reduced to its basename. write_scene_manifest then prepended the
# addon path to an already-full path, and every carried-over entry came out as
# Interface\AddOns\...\SceneCutouts\Interface\AddOns\...\SceneCutouts\<file>.tga,
# which does not exist in-game. That silently corrupted exactly the entries the
# merge was added to protect.
# ---------------------------------------------------------------------------
original = [
    ("Dreamscythe:1:Drakuzo", "dreamscythe_1_drakuzo.tga", "297", "587"),
    ("Dreamscythe:2:Elegia", "dreamscythe_2_elegia.tga", "307", "550"),
]

path = write_temp_manifest(original)
try:
    parsed = sc.parse_scene_manifest(path)

    eq(len(parsed), 2, "round-trip should read back both entries")
    eq(parsed["Dreamscythe:1:Drakuzo"], ("dreamscythe_1_drakuzo.tga", "297", "587"),
       "entry should round-trip to its basename and dimensions")
    eq(parsed["Dreamscythe:2:Elegia"], ("dreamscythe_2_elegia.tga", "307", "550"),
       "second entry should round-trip")

    # Writing what was parsed must be idempotent - this is the step that doubled
    # the prefix when the split was wrong.
    rewritten = write_temp_manifest(
        [(k, v[0], v[1], v[2]) for k, v in sorted(parsed.items())])
    try:
        with open(rewritten, encoding="utf-8") as f:
            text = f.read()
        check("SceneCutouts\\\\Interface" not in text,
              "re-written manifest must not double the addon path prefix")

        reparsed = sc.parse_scene_manifest(rewritten)
        eq(reparsed, parsed, "a second round-trip must be identical (idempotent)")
    finally:
        os.remove(rewritten)
finally:
    os.remove(path)


# ---------------------------------------------------------------------------
# The committed manifest is the real input a partial run merges into.
# ---------------------------------------------------------------------------
committed = os.path.join(REPO_ROOT, "AltTrackerSceneManifest.lua")
if os.path.exists(committed):
    entries = sc.parse_scene_manifest(committed)
    check(len(entries) > 0, "committed scene manifest should parse")
    for key, (base, w, h) in entries.items():
        check("\\" not in base and "/" not in base,
              f"{key}: parsed image should be a bare filename, not a path ({base})")
        check(base.endswith(".tga"), f"{key}: image should be a .tga ({base})")
        check(w.isdigit() and h.isdigit(), f"{key}: dimensions should be numeric ({w}x{h})")

# A missing or unreadable manifest is a first run, not an error.
eq(sc.parse_scene_manifest(os.path.join(REPO_ROOT, "does_not_exist.lua")), {},
   "absent manifest should parse as empty")


# ---------------------------------------------------------------------------
# find_armory_render: raw renders only, newest wins, reference variants excluded.
# ---------------------------------------------------------------------------
cache = tempfile.mkdtemp()
try:
    def touch(name):
        p = os.path.join(cache, name)
        with open(p, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
        return p

    raw = touch("dreamscythe_1_drakuzo-68d71ea2.png")
    touch("dreamscythe_1_drakuzo-68d71ea2-reference-d0a90b63-564767a6.png")
    touch("someone_else-11112222.png")

    found = sc.find_armory_render(cache, "dreamscythe_1_drakuzo")
    eq(os.path.basename(found or ""), os.path.basename(raw),
       "should pick the raw render, never a -reference- variant")

    eq(sc.find_armory_render(cache, "no_such_character"), None,
       "unknown character should have no armory render")
    eq(sc.find_armory_render(os.path.join(cache, "nope"), "dreamscythe_1_drakuzo"), None,
       "missing cache directory should be handled")
finally:
    for name in os.listdir(cache):
        os.remove(os.path.join(cache, name))
    os.rmdir(cache)


# ---------------------------------------------------------------------------
# A character that loses every source must stop being advertised as having a
# cutout, while characters excluded by --only keep theirs.
#
# The merged manifest starts from what is already on disk, so simply skipping a
# failed character left its old entry in place. CampHasCutouts would then go on
# choosing cutouts and the addon would load a stale file instead of falling back
# to framed cards.
# ---------------------------------------------------------------------------
sandbox = tempfile.mkdtemp()
try:
    addon = os.path.join(sandbox, "AddOns", "AltTracker")
    os.makedirs(os.path.join(addon, "Media", "CharacterRenders"))
    os.makedirs(os.path.join(addon, "Media", "SceneCutouts"))
    os.makedirs(os.path.join(sandbox, "temp", "blizzard"))

    # Render manifest names two characters; NEITHER has a portrait or an armory render.
    render_manifest = os.path.join(addon, "AltTrackerRenderManifest.lua")
    sc.write_scene_manifest(render_manifest, [
        ("Realm:1:Gone", "realm_1_gone.tga", "1", "1"),
        ("Realm:1:Kept", "realm_1_kept.tga", "1", "1"),
    ])

    # Both already have scene entries from a previous run.
    scene_manifest = os.path.join(addon, "AltTrackerSceneManifest.lua")
    sc.write_scene_manifest(scene_manifest, [
        ("Realm:1:Gone", "realm_1_gone.tga", "100", "200"),
        ("Realm:1:Kept", "realm_1_kept.tga", "110", "210"),
    ])

    cfg = os.path.join(sandbox, "appsettings.json")
    with open(cfg, "w", encoding="utf-8") as f:
        json.dump({
            "AddonMediaDirectory": os.path.join(addon, "Media", "CharacterRenders"),
            "ManifestOutputPath": render_manifest,
            "TempPath": os.path.join(sandbox, "temp"),
            "BattleNet": {"CacheDirectory": os.path.join(sandbox, "temp", "blizzard")},
            # Keep the committed-snapshot write inside the sandbox; without this the run would
            # overwrite the real AltTrackerSceneManifest.lua in the repo.
            "SceneManifestRepoPath": os.path.join(sandbox, "repo-snapshot.lua"),
        }, f)

    proc = subprocess.run(
        [sys.executable, os.path.join(REPO_ROOT, "Tools", "scene_cutouts.py"), "--only", "gone"],
        capture_output=True, text=True, cwd=REPO_ROOT,
        env={**os.environ, "ALTTRACKER_APPSETTINGS": cfg},
    )

    after = sc.parse_scene_manifest(scene_manifest)
    check("Realm:1:Gone" not in after,
          f"a character with no source must lose its manifest entry (rc={proc.returncode}, {proc.stdout.strip()[-160:]})")
    eq(after.get("Realm:1:Kept"), ("realm_1_kept.tga", "110", "210"),
       "a character excluded by --only must keep its entry untouched")
finally:
    shutil.rmtree(sandbox, ignore_errors=True)


if failures:
    print(f"scene_cutouts tests FAILED: {failures} of {tests_run}")
    sys.exit(1)
print(f"scene_cutouts tests passed: {tests_run}")

#!/usr/bin/env python3
"""Import settings for generated 3D textures, written the way the Godot editor would write them.

    python3 scripts/tools/texture_imports.py --check              # committed textures (CI, validate job)
    python3 scripts/tools/texture_imports.py --glb assets/meshes/<id>.glb ...    # after a GLB lands
    python3 scripts/tools/texture_imports.py --seed vram|lossless <png> ...      # after a PNG is written

Why: a headless import gives a new texture Godot's defaults (lossless, 3D detection pending). The first
time the editor draws it on a 3D material, ResourceImporterTexture's 3D detection switches it to VRAM
compression with mipmaps and rewrites its .import, which dirties every checkout that opens the editor
(PRs #28 and #37 committed the kit and crypt textures that way by hand). So every generator that writes a
texture used in 3D settles its .import before it's committed:

- GLB-extracted textures (assets/meshes/<glb stem>_<image>.png, written by Godot's scene importer for the
  asset pipeline's GLBs, kit pieces from scripts/tools/import_pack.py included): `detect_3d` applies exactly
  what the editor's detection would, then a headless import lets Godot rewrite the rest of the file.
  scripts/pipeline.py's validate stage calls `settle_glb` once a GLB passes.
- Generated PNGs: `seed` writes or updates the .import's params for a policy before the import, and Godot
  fills in the rest (remap, uid, the other params) and keeps them. scripts/tools/make_brush_textures.py
  seeds "vram" (as the editor detected the crypt textures); scripts/tools/make_textures.py seeds "lossless"
  (surface textures stay lossless so S3TC adds no off-palette colours: docs/trials/material-maker.md,
  decision 6).

Only the params this module names are touched; the rest of each .import is Godot's. Stdlib only.
"""
import argparse
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_timeout  # noqa: E402

GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"

# ResourceImporterTexture::CompressMode: 0 lossless, 2 VRAM compressed, 4 Basis Universal.
# detect_3d/compress_to: 0 detection off, 1 VRAM compressed, 2 Basis Universal.
DETECT_3D_TO_MODE = {"1": "2", "2": "4"}
POLICIES = {
    # What the editor's 3D detection leaves (compress_to=1, the default)
    "vram": {"compress/mode": "2", "mipmaps/generate": "true", "detect_3d/compress_to": "0"},
    # Lossless with mipmaps and detection off, so the editor never changes it
    "lossless": {"compress/mode": "0", "mipmaps/generate": "true", "detect_3d/compress_to": "0"},
}
# Committed textures by folder: (folder, policy, only textures Godot extracted from a GLB)
RULES = (
    ("assets/meshes", "vram", True),
    ("assets/textures/brush", "vram", False),
    ("assets/textures/surfaces", "lossless", False),
)
# Committed before this check, left as they are (changing a committed .import is its own decision)
EXEMPT = {
    # prop_torch's specular-glossiness map: extracted but on no material, so the editor never detects it
    "assets/meshes/prop_torch_material_specularGlossiness.png",
}
_SECTION = re.compile(r"^\[(.+)\]\s*$")


def _import_path(png):
    return Path(str(png) + ".import")


def read_params(import_path):
    """The [params] section as raw strings, as Godot writes them."""
    out, section = {}, None
    for line in Path(import_path).read_text().splitlines():
        m = _SECTION.match(line)
        if m:
            section = m.group(1)
        elif section == "params" and "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def _write_params(png, values):
    """Set `values` in the .import's [params] (creating the file, or the section, if missing).
    Returns True when the file changed."""
    path = _import_path(png)
    text = path.read_text() if path.exists() else ""
    lines = text.splitlines()
    todo, section, end = dict(values), None, None
    for i, line in enumerate(lines):
        m = _SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        if section == "params":
            end = i + 1
            k = line.split("=", 1)[0] if "=" in line else None
            if k in todo:
                lines[i] = f"{k}={todo.pop(k)}"
    if todo:
        if end is None:
            if lines and lines[-1] != "":
                lines.append("")
            lines += ["[params]", ""]
            end = len(lines)
        lines[end:end] = [f"{k}={v}" for k, v in todo.items()]
    new = "\n".join(lines) + "\n"
    if new == text:
        return False
    if path.exists():
        # Godot notices an edited .import by its modification time, in whole seconds: a write in the
        # same second as the import that wrote it would be missed by the next import
        time.sleep(max(0.0, path.stat().st_mtime + 1.05 - time.time()))
    path.write_text(new)
    return True


def detect_3d(png):
    """What the editor does when it first draws a texture on a 3D material (ResourceImporterTexture,
    3D detection): while detection is pending, compress to its target with mipmaps, then switch it off.
    Returns True when the .import changed (a headless import then rewrites the rest of the file)."""
    p = read_params(_import_path(png))
    to = p.get("detect_3d/compress_to", "1")
    if to not in DETECT_3D_TO_MODE:
        return False
    return _write_params(png, {"compress/mode": DETECT_3D_TO_MODE[to], "mipmaps/generate": "true",
                               "detect_3d/compress_to": "0"})


def seed(png, policy):
    """Write a generated PNG's import params for `policy` ("vram" or "lossless"). Returns True when the
    .import changed; run a headless import afterwards so Godot imports it and completes the file."""
    return _write_params(png, POLICIES[policy])


def _extracted(import_path):
    # Godot's scene importer records the image's md5 as generator_parameters on what it extracts
    return '"md5":' in import_path.read_text()


def extracted_textures(glb):
    """Textures Godot's scene importer extracted from `glb`: <stem>_<image>.png beside it, marked with the
    importer's md5. (A longer GLB name can share the prefix; its textures follow the same rule.)"""
    glb = Path(glb)
    return sorted(p for p in glb.parent.glob(f"{glb.stem}_*.png")
                  if _import_path(p).exists() and _extracted(_import_path(p)))


def godot_import(godot=GODOT, root=ROOT):
    proc = godot_timeout.run([godot, "--headless", "--path", root, "--import"], "texture import",
                             "GODOT_TIMEOUT_IMPORT", 900, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"godot --import failed (exit {proc.returncode}):\n{proc.stdout[-2000:]}{proc.stderr[-2000:]}")


def settle_glb(glb, godot=GODOT, root=ROOT):
    """Import (so Godot extracts the GLB's textures), apply the editor's 3D detection to them, and import
    again when that changed anything. Returns the textures changed."""
    godot_import(godot, root)
    changed = [p for p in extracted_textures(glb) if detect_3d(p)]
    if changed:
        godot_import(godot, root)
    return changed


def check(root=ROOT):
    """Committed textures under the 3D folders hold their policy's params, so the editor leaves them alone."""
    root = Path(root)
    errs = []
    for folder, policy, only_extracted in RULES:
        for png in sorted((root / folder).glob("*.png")):
            rel = png.relative_to(root).as_posix()
            imp = _import_path(png)
            if rel in EXEMPT:
                continue
            if not imp.exists():
                errs.append(f"{rel}: no .import (import it and settle it with scripts/tools/texture_imports.py)")
                continue
            if only_extracted and not _extracted(imp):
                continue
            p = read_params(imp)
            for k, want in POLICIES[policy].items():
                if p.get(k) != want:
                    errs.append(f"{rel}: {k}={p.get(k)}, want {want} ({policy}); the editor would rewrite it")
    return errs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="check the committed textures")
    ap.add_argument("--glb", nargs="+", default=[], help="settle the textures extracted from these GLBs")
    ap.add_argument("--seed", nargs="+", metavar=("POLICY", "PNG"), help="seed POLICY for these PNGs, then import")
    ap.add_argument("--godot", default=GODOT)
    args = ap.parse_args(argv)
    if args.check:
        errs = check()
        for e in errs:
            print(f"texture_imports: {e}")
        print(f"texture_imports: {'FAIL' if errs else 'ok'} ({len(errs)} problem(s))")
        return 1 if errs else 0
    if args.seed:
        policy, pngs = args.seed[0], args.seed[1:]
        if policy not in POLICIES or not pngs:
            ap.error(f"--seed takes a policy ({', '.join(POLICIES)}) and one or more PNGs")
        if [p for p in pngs if seed(Path(p).resolve(), policy)]:
            godot_import(args.godot)
    for g in args.glb:
        for p in settle_glb(Path(g).resolve(), args.godot):
            print(f"texture_imports: {p.relative_to(ROOT)}: VRAM compressed, as the editor detects it")
    return 0


if __name__ == "__main__":
    sys.exit(main())

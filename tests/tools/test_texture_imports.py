#!/usr/bin/env python3
"""Tests for scripts/tools/texture_imports.py (stdlib unittest).

    python3 tests/tools/test_texture_imports.py

Generated 3D textures must land with the import settings the editor would give them, so opening the
editor doesn't rewrite their .import files in every checkout (backlog import-pack-compress-mode).
"""
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("texture_imports", os.path.join(ROOT, "scripts", "tools", "texture_imports.py"))
ti = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ti)

# What Godot 4.7.2's scene importer writes for a texture it extracts from a GLB (the remap and deps
# sections trimmed): lossless, mipmaps on, 3D detection pending (compress_to=1, VRAM compressed).
EXTRACTED = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://bjaovuvt3j2ne"
path="res://.godot/imported/piece_texture.png-af61.ctex"
metadata={
"vram_texture": false
}
generator_parameters={
"md5": "7afa73f3c958e34e476cf55eac274c1c"
}

[deps]

source_file="res://assets/meshes/piece_texture.png"

[params]

compress/mode=0
compress/high_quality=false
mipmaps/generate=true
mipmaps/limit=-1
process/size_limit=0
detect_3d/compress_to=1
"""


def params(path):
    return ti.read_params(Path(str(path) + ".import"))


class TextureImports(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def png(self, name, import_text=None):
        p = self.dir / name
        p.write_bytes(b"\x89PNG\r\n\x1a\n")
        if import_text is not None:
            Path(str(p) + ".import").write_text(import_text)
        return p

    def test_detect_3d_mirrors_the_editor(self):
        # ResourceImporterTexture's 3D detection: compress_to 1 -> VRAM compressed (mode 2), mipmaps on,
        # detection off; the rest of the file is Godot's and stays as it was until Godot rewrites it.
        p = self.png("piece_texture.png", EXTRACTED)
        self.assertTrue(ti.detect_3d(p))
        got = params(p)
        self.assertEqual((got["compress/mode"], got["mipmaps/generate"], got["detect_3d/compress_to"]), ("2", "true", "0"))
        text = Path(str(p) + ".import").read_text()
        self.assertIn('uid="uid://bjaovuvt3j2ne"', text)
        self.assertIn('"md5": "7afa73f3c958e34e476cf55eac274c1c"', text)
        self.assertEqual(text.replace("compress/mode=2", "compress/mode=0").replace("compress_to=0", "compress_to=1"),
                         EXTRACTED)

    def test_detect_3d_leaves_a_detected_texture_alone(self):
        done = EXTRACTED.replace("compress/mode=0", "compress/mode=2").replace("compress_to=1", "compress_to=0")
        p = self.png("piece_texture.png", done)
        self.assertFalse(ti.detect_3d(p))
        # Detection off with lossless kept (the surface textures' setting) is a decision, not pending
        kept = EXTRACTED.replace("compress_to=1", "compress_to=0")
        q = self.png("kept.png", kept)
        self.assertFalse(ti.detect_3d(q))
        self.assertEqual(params(q)["compress/mode"], "0")

    def test_seed_writes_params_for_a_new_png(self):
        # Godot fills in the rest (remap, uid, the other params) on the next import and keeps these
        p = self.png("new.png")
        self.assertTrue(ti.seed(p, "lossless"))
        self.assertEqual(params(p), {"compress/mode": "0", "mipmaps/generate": "true", "detect_3d/compress_to": "0"})
        self.assertFalse(ti.seed(p, "lossless"))

    def test_seed_updates_an_existing_import_in_place(self):
        p = self.png("piece_texture.png", EXTRACTED)
        self.assertTrue(ti.seed(p, "vram"))
        self.assertEqual(params(p)["compress/mode"], "2")
        self.assertEqual(params(p)["mipmaps/limit"], "-1")
        self.assertIn('uid="uid://bjaovuvt3j2ne"', Path(str(p) + ".import").read_text())

    def test_extracted_textures_are_the_glbs_own(self):
        glb = self.dir / "piece.glb"
        glb.write_bytes(b"glTF")
        own = self.png("piece_texture.png", EXTRACTED)
        self.png("piece_hand_made.png", EXTRACTED.replace('generator_parameters={\n"md5": "7afa73f3c958e34e476cf55eac274c1c"\n}\n', ""))
        self.png("other_texture.png", EXTRACTED)
        self.assertEqual(ti.extracted_textures(glb), [own])

    def test_check_flags_pending_and_missing_imports(self):
        meshes = self.dir / "assets" / "meshes"
        surfaces = self.dir / "assets" / "textures" / "surfaces"
        meshes.mkdir(parents=True)
        surfaces.mkdir(parents=True)
        (meshes / "a_tex.png").write_bytes(b"")
        Path(str(meshes / "a_tex.png") + ".import").write_text(EXTRACTED)
        (surfaces / "b.png").write_bytes(b"")
        errs = ti.check(self.dir)
        self.assertTrue(any("a_tex.png" in e and "compress/mode" in e for e in errs), errs)
        self.assertTrue(any("b.png" in e and "no .import" in e for e in errs), errs)

    def test_committed_textures_pass_the_check(self):
        self.assertEqual(ti.check(Path(ROOT)), [])


if __name__ == "__main__":
    unittest.main()

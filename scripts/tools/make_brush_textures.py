#!/usr/bin/env python3
"""Placeholder tileable albedo textures for brush-built (.map) interiors (trial B2, docs/trials/func-godot.md).

    python3 scripts/tools/make_brush_textures.py

Writes assets/textures/brush/<name>.png: 128x128, albedo only, tileable, in art-bible palette colours
(docs/art-bible.md -> Palette), with no lighting painted in. Each is a block pattern (stone courses or
flagstones) whose blocks vary a little in value around one palette colour, with darker joints. Seeded,
so two runs write identical files. Stdlib only (zlib PNG writer), so it runs anywhere CI does.

GENERATED FILES: the PNGs are written only by this script. They are stand-ins until a texture source
is chosen (Material Maker is trial B3); the materials next to them (<name>.tres) reference them by path,
so a replacement texture of the same name drops in.

Each PNG's .import is seeded with the settings the editor's 3D detection gives it (VRAM compressed, mipmaps,
detection off; scripts/tools/texture_imports.py), and a headless import completes any it changed, so the
editor never rewrites them. Godot comes from $GODOT_BIN, else /Applications/Godot.app; it runs only then.
"""
import os
import random
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texture_imports  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "brush")
SIZE = 128  # px; at the maps' scale (32 units per metre, texture scale 1) one tile spans 4 m

# Palette hex values (docs/art-bible.md -> Palette).
WET_SLATE = (0x73, 0x6B, 0x66)
RAIN_STONE = (0x4D, 0x47, 0x40)
PEAT_BLACK = (0x2E, 0x29, 0x26)
OLD_BONE = (0xCC, 0xB4, 0x84)

# name: (block colour, joint colour, block width px, block height px, offset alternate rows, value jitter)
TEXTURES = {
    # Dressed wall courses, 1 m x 0.5 m at 32 px per metre, running bond.
    "crypt_wall": (WET_SLATE, RAIN_STONE, 32, 16, True, 0.08),
    # Floor flagstones, 1 m square, slightly lighter than the field stone so the floor never reads black.
    "crypt_floor": (RAIN_STONE, PEAT_BLACK, 32, 32, True, 0.10),
    # Ceiling slabs, 2 m x 1 m.
    "crypt_ceiling": (RAIN_STONE, PEAT_BLACK, 64, 32, True, 0.06),
    # Dais, steps and the sarcophagus: pale dressed stone so the landmark reads against the walls.
    "crypt_dais": (OLD_BONE, WET_SLATE, 32, 16, True, 0.05),
}
JOINT_PX = 2


def _clamp(v):
    return max(0, min(255, int(round(v))))


def make(name, block, joint, bw, bh, offset, jitter):
    rng = random.Random(name)  # seeded by name: deterministic and independent per texture
    rows = SIZE // bh
    cols = SIZE // bw
    shade = {(r, c): 1.0 + rng.uniform(-jitter, jitter) for r in range(rows) for c in range(cols)}
    pixels = bytearray()
    for y in range(SIZE):
        row = y // bh
        shift = (bw // 2) if (offset and row % 2) else 0
        pixels.append(0)  # PNG filter type: none
        for x in range(SIZE):
            xs = (x + shift) % SIZE
            col = xs // bw
            in_joint = (y % bh) < JOINT_PX or (xs % bw) < JOINT_PX
            if in_joint:
                rgb = joint
            else:
                k = shade[(row, col)]
                rgb = tuple(_clamp(ch * k) for ch in block)
            pixels.extend(rgb)
    return _png(SIZE, SIZE, bytes(pixels))


def _png(w, h, raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)  # 8-bit RGB
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in TEXTURES.items():
        path = os.path.join(OUT_DIR, name + ".png")
        with open(path, "wb") as f:
            f.write(make(name, *spec))
        print("wrote", os.path.relpath(path, ROOT))
    seeded = [n for n in TEXTURES if texture_imports.seed(os.path.join(OUT_DIR, n + ".png"), "vram")]
    if seeded:
        texture_imports.godot_import(os.environ.get("GODOT_BIN", texture_imports.GODOT), ROOT)
        print("imported", ", ".join(seeded), "VRAM compressed, as the editor detects them")


if __name__ == "__main__":
    main()

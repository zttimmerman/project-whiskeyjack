"""The crypt trial's room set (docs/trials/func-godot.md), in Godot metres; see scripts/tools/brush_boxes.py.

Corridor: interior x -2..2, z 1..13, ceiling 4 m (its own func_room entity, so the renderer's
8-lights-per-mesh cap applies per room). Doorway 3 x 3 m. Hall: interior x -6..6, z -12..0, ceiling
6 m, with pillars, beams, side niches and a 1 m dais whose steps sit under a clip ramp.
"""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "brush_boxes", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "brush_boxes.py")
)
_bb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bb)
outside = _bb.outside

OUTPUT = "scenes/world/trials/crypt_trial.map"
WALL, FLOOR, CEIL, DAIS = "crypt_wall", "crypt_floor", "crypt_ceiling", "crypt_dais"

# (comment, Godot position, angle): func_godot turns a node's -Z to the angle; 0 is Godot +Z, 90 is +X
TORCHES = [
    ("corridor west wall, halfway", (-2, 2.75, 7), 90),
    ("corridor east wall, halfway", (2, 2.75, 7), 270),
    ("hall south wall, west of the doorway", (-4, 2.75, 0), 180),
    ("hall south wall, east of the doorway", (4, 2.75, 0), 180),
    ("hall west niche", (-6.5, 2.2, -6), 90),
    ("hall east niche", (6.5, 2.2, -6), 270),
    ("hall north wall above the dais, west", (-3, 3.3, -12), 0),
    ("hall north wall above the dais, east", (3, 3.3, -12), 0),
]


def build(m):
    m.header(
        "Crypt trial (docs/trials/func-godot.md). Units: 32 per metre; Godot (x, y, z) = Quake (y, z, x) / 32.",
        "Written by scripts/tools/brush_boxes.py from scripts/tools/brush_layouts/crypt_trial.py.",
        "Built into scenes/world/trials/CryptTrial_brushes.tscn by scripts/tools/build_brush_maps.gd.",
    )
    w = m.entity("worldspawn", {"_cull_interior_faces": "1"}, "the hall, the dais and the doorway wall")
    w.box("hall floor slab", (-7, -1, -13), (7, 0, 1), FLOOR, outside("-x", "+x", "-y", "-z", "+z"))
    w.box("hall ceiling slab", (-7, 6, -13), (7, 7, 1), CEIL, outside("-x", "+x", "+y", "-z", "+z"))
    w.box("hall north wall", (-7, 0, -13), (7, 6, -12), WALL, outside("-z", "-x", "+x"))
    for sx, name in ((-1, "west"), (1, "east")):
        lo_x, hi_x = (-7, -6) if sx < 0 else (6, 7)
        back = (-7, -6.5) if sx < 0 else (6.5, 7)
        front = (-6.5, -6) if sx < 0 else (6, 6.5)
        out_side = "-x" if sx < 0 else "+x"
        w.box("hall %s wall, north of the niche" % name, (lo_x, 0, -12), (hi_x, 6, -7), WALL, outside(out_side))
        w.box("hall %s wall, south of the niche" % name, (lo_x, 0, -5), (hi_x, 6, 0), WALL, outside(out_side))
        w.box("hall %s niche back (0.5 m deep)" % name, (back[0], 0, -7), (back[1], 6, -5), WALL, outside(out_side))
        w.box("hall %s niche header (niche 2 m wide, 3 m tall)" % name, (front[0], 3, -7), (front[1], 6, -5), WALL)
    w.box("hall south wall, west of the doorway", (-7, 0, 0), (-1.5, 6, 1), WALL, outside("-x"))
    w.box("hall south wall, east of the doorway", (1.5, 0, 0), (7, 6, 1), WALL, outside("+x"))
    w.box("doorway lintel (doorway 3 m wide, 3 m tall)", (-1.5, 3, 0), (1.5, 6, 1), WALL)
    for x0 in (-4, 3):
        for z0 in (-3, -6):
            w.box("hall pillar at x %g, z %g" % (x0 + 0.5, z0 + 0.5), (x0, 0, z0), (x0 + 1, 6, z0 + 1), WALL)
    for z0 in (-3, -6):
        w.box("ceiling beam over the pillars at z %g" % (z0 + 0.5), (-6, 5.25, z0), (6, 6, z0 + 1), WALL)
    # Dais: 1 m high across the north end, stairs up its middle
    w.box("dais (1 m high)", (-4, 0, -12), (4, 1, -8), DAIS)
    w.box("dais step 1", (-2, 0, -8), (2, 0.25, -6.5), DAIS)
    w.box("dais step 2", (-2, 0.25, -8), (2, 0.5, -7), DAIS)
    w.box("dais step 3", (-2, 0.5, -8), (2, 0.75, -7.5), DAIS)
    w.hull(
        "clip ramp over the steps (collision only, 26.6 degrees): the capsule and the navmesh climb it",
        [
            [(-2, 0, -6), (2, 0, -6), (2, 0, -8)],  # bottom y 0
            [(-2, 0, -8), (2, 0, -8), (2, 1, -8)],  # back z -8
            [(-2, 0, -6), (-2, 0, -8), (-2, 1, -8)],  # west x -2
            [(2, 0, -6), (2, 1, -8), (2, 0, -8)],  # east x 2
            [(-2, 0, -6), (2, 0, -6), (2, 1, -8)],  # slope
        ],
        (0, 0.3, -7.5),
        "clip",
    )
    w.box("sarcophagus base", (-1.25, 1, -11), (1.25, 1.875, -9.5), DAIS)
    w.box("sarcophagus lid", (-1.5, 1.875, -11.25), (1.5, 2.125, -9.25), DAIS)

    r = m.entity("func_room", {"_cull_interior_faces": "1"}, "the corridor; its own mesh, so the 8-light cap is per room")
    r.box("corridor floor slab", (-3, -1, 1), (3, 0, 14), FLOOR, outside("-x", "+x", "-y", "-z", "+z"))
    r.box("corridor ceiling slab", (-3, 4, 1), (3, 5, 14), CEIL, outside("-x", "+x", "+y", "-z", "+z"))
    r.box("corridor west wall", (-3, 0, 1), (-2, 4, 13), WALL, outside("-x", "-z"))
    r.box("corridor east wall", (2, 0, 1), (3, 4, 13), WALL, outside("+x", "-z"))
    r.box("corridor south end wall", (-3, 0, 13), (3, 4, 14), WALL, outside("+z", "-x", "+x"))

    for comment, pos, angle in TORCHES:
        m.point("light_torch", pos, angle=angle, comment=comment)

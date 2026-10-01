#!/usr/bin/env python3
"""Write Quake .map brushwork from boxes in Godot metres, so nobody hand-writes plane triples.

    python3 scripts/tools/brush_boxes.py            write every layout's .map
    python3 scripts/tools/brush_boxes.py --check    fail if a committed .map differs from its layout

A layout is a module in scripts/tools/brush_layouts/ with OUTPUT (the .map path from the repo root)
and build(m), which fills a MapWriter:

    m.header("one line about the map")
    world = m.entity("worldspawn", {"_cull_interior_faces": "1"}, "the hall")
    world.box("hall floor", (-7, -1, -13), (7, 0, 1), "crypt_floor", outside("-y", "-x"))
    world.hull("clip ramp", [[p0, p1, p2], ...], centre, "clip")
    m.point("light_torch", (-2, 2.75, 7), angle=90, comment="corridor torch")

Coordinates are Godot metres (y up). The map is Standard (Quake) format at 32 units per metre
(data/maps/crypt_map_settings.tres): Godot (x, y, z) = Quake (y, z, x) / 32. A plane is three points
ordered so the Quake normal, (p2 - p0) x (p1 - p0), points out of the brush. Texture names are files
in assets/textures/brush/ (without extension), plus func_godot's "clip" (collision only) and "skip"
(neither mesh nor collision; use it for faces outside the shell, via outside()). Brush comments
("// brush N: ...") name each brush for review.

Once a map is edited in TrenchBroom, the .map is the source: delete its layout, since TrenchBroom
rewrites comments and --check would fail. scripts/tools/build_brush_maps.gd builds the .map into a scene.
Stdlib only.
"""
import argparse
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYOUT_DIR = os.path.join(ROOT, "scripts", "tools", "brush_layouts")
UNITS_PER_M = 32
# Godot side -> Quake axis of the face's outward normal (qx = Gz, qy = Gx, qz = Gy)
_SIDES = {"-z": "-qx", "-x": "-qy", "-y": "-qz", "+y": "+qz", "+x": "+qy", "+z": "+qx"}


def to_quake(p):
    """Godot metres -> Quake units (rounded to whole units)."""
    x, y, z = p
    return (round(z * UNITS_PER_M), round(x * UNITS_PER_M), round(y * UNITS_PER_M))


def outside(*sides):
    """Faces on the outside of the shell (Godot sides such as "-y", "+x"): textured skip."""
    for s in sides:
        if s not in _SIDES:
            raise ValueError("unknown side %r (use %s)" % (s, ", ".join(_SIDES)))
    return {s: "skip" for s in sides}


def _sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def quake_normal(p0, p1, p2):
    """The outward normal Quake tools derive from a plane's three points."""
    return _cross(_sub(p2, p0), _sub(p1, p0))


def _plane(p0, p1, p2, tex):
    return "( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s 0 0 0 1 1" % (*p0, *p1, *p2, tex)


def box_planes(lo, hi, tex, faces=None):
    """Six plane lines for an axis-aligned box between two Godot corners; faces overrides per side."""
    faces = faces or {}
    a, b = to_quake(lo), to_quake(hi)
    x0, y0, z0 = (min(a[i], b[i]) for i in range(3))
    x1, y1, z1 = (max(a[i], b[i]) for i in range(3))
    if x0 == x1 or y0 == y1 or z0 == z1:
        raise ValueError("box %s..%s is flat at 32 units per metre" % (lo, hi))
    planes = [
        ("-qx", (x0, y0, z0), (x0, y0 + 1, z0), (x0, y0, z0 + 1)),
        ("-qy", (x0, y0, z0), (x0, y0, z0 + 1), (x0 + 1, y0, z0)),
        ("-qz", (x0, y0, z0), (x0 + 1, y0, z0), (x0, y0 + 1, z0)),
        ("+qz", (x1, y1, z1), (x1, y1 + 1, z1), (x1 + 1, y1, z1)),
        ("+qy", (x1, y1, z1), (x1 + 1, y1, z1), (x1, y1, z1 + 1)),
        ("+qx", (x1, y1, z1), (x1, y1, z1 + 1), (x1, y1 + 1, z1)),
    ]
    by_axis = {v: k for k, v in _SIDES.items()}
    return [_plane(p0, p1, p2, faces.get(by_axis[axis], tex)) for axis, p0, p1, p2 in planes]


def hull_planes(planes, centre, tex):
    """Plane lines for a convex brush: each plane as three Godot points, wound to face away from centre."""
    c = to_quake(centre)
    out = []
    for pts in planes:
        p0, p1, p2 = (to_quake(p) for p in pts)
        n = quake_normal(p0, p1, p2)
        if n == (0, 0, 0):
            raise ValueError("degenerate plane %s" % (pts,))
        if _dot(n, _sub(c, p0)) > 0:
            p1, p2 = p2, p1
        out.append(_plane(p0, p1, p2, tex))
    return out


class Entity:
    def __init__(self, classname, properties, comment):
        self.classname, self.properties, self.comment = classname, properties, comment
        self.brushes = []  # (comment, plane lines)

    def box(self, comment, lo, hi, tex, faces=None):
        self.brushes.append((comment, box_planes(lo, hi, tex, faces)))

    def hull(self, comment, planes, centre, tex):
        self.brushes.append((comment, hull_planes(planes, centre, tex)))


class MapWriter:
    def __init__(self):
        self._header = []
        self._entities = []  # Entity, or (classname, origin, angle, comment) for point entities

    def header(self, *lines):
        self._header.extend(lines)

    def entity(self, classname, properties=None, comment=""):
        e = Entity(classname, properties or {}, comment)
        self._entities.append(e)
        return e

    def point(self, classname, position, angle=None, comment="", properties=None):
        props = {"origin": "%d %d %d" % to_quake(position)}
        if angle is not None:
            props["angle"] = "%d" % angle
        props.update(properties or {})
        self._entities.append(Entity(classname, props, comment))

    def text(self):
        out = ["// Game: Whiskeyjack", "// Format: Standard"] + ["// " + h for h in self._header]
        for i, e in enumerate(self._entities):
            out.append("// entity %d: %s%s" % (i, e.classname, (", " + e.comment) if e.comment else ""))
            out.append("{")
            out.append('"classname" "%s"' % e.classname)
            out.extend('"%s" "%s"' % kv for kv in e.properties.items())
            for j, (comment, lines) in enumerate(e.brushes):
                out.append("// brush %d: %s" % (j, comment))
                out.append("{")
                out.extend(lines)
                out.append("}")
            out.append("}")
        return "\n".join(out) + "\n"


def layouts():
    found = []
    for name in sorted(os.listdir(LAYOUT_DIR)):
        if name.endswith(".py") and not name.startswith("_"):
            spec = importlib.util.spec_from_file_location("brush_layout_" + name[:-3], os.path.join(LAYOUT_DIR, name))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            found.append(module)
    return found


def render(layout):
    m = MapWriter()
    layout.build(m)
    return m.text()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if a committed .map differs from its layout")
    args = parser.parse_args(argv)
    stale = []
    for layout in layouts():
        path = os.path.join(ROOT, layout.OUTPUT)
        text = render(layout)
        if args.check:
            current = open(path).read() if os.path.exists(path) else None
            if current != text:
                stale.append(layout.OUTPUT)
        else:
            with open(path, "w") as f:
                f.write(text)
            print("wrote", layout.OUTPUT)
    for path in stale:
        print("stale: %s differs from its layout (run python3 scripts/tools/brush_boxes.py)" % path, file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())

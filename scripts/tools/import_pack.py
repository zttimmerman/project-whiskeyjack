#!/usr/bin/env python3
"""Import pieces of a downloaded CC0 kit through the asset pipeline (the asset-pipeline skill -> Sourced assets).

    python3 scripts/tools/import_pack.py <pack-dir> --pack <pack-id> (--pieces NAME[:FORMAT] ... | --glob PATTERN)
        [--describe NAME=TEXT ...] [--dry-run]
        # first import of a pack (recorded in assets/sources.json; later runs read it back):
        [--title T --homepage URL --url ARCHIVE_URL --author A --license SPDX --version V --archive ZIP --license-file PATH]
        [--palette "Name,Name" --budget "art-bible heading" --source-scale S --prefix P --format gltf|obj|fbx
         --atlas-source PATH]

<pack-dir> is the extracted download under the gitignored .downloads/<pack-id>/, next to the original zip
(--archive). For each piece it finds <name>.<format> in the pack, writes assets/briefs/<prefix><name>.yaml and
the piece's assets/sources.json entry (URL, author, licence, pack version, SHA-256 of the source file), then
runs `scripts/pipeline.py <id> --stage all`, and reports the triangle count and any budget failure per piece.
The validate stage gives each piece's extracted texture the editor's import settings (VRAM compressed;
scripts/tools/texture_imports.py), so the .import files it leaves are the ones to commit.

Numbers come only from docs/art-bible.md: --budget names the art-bible budget line (**<label>:**) or the
section whose **Budget:** line gives the triangle budget and texture size. Idempotent: the same inputs write the same briefs and entries,
and the pipeline skips stages whose inputs haven't changed. Exit 0 all pieces passed, 2 any failed, 1 error.
Downloads are never made here: fetch the pack with curl from its official URL first.
"""

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import pipeline as P  # noqa: E402

FORMATS = {"gltf": (".glb", ".gltf"), "obj": (".obj",), "fbx": (".fbx",)}
PACK_META = ("title", "homepage", "source_url", "author", "license", "version")
IMPORT_SETTINGS = ("palette", "budget", "source_scale", "prefix", "format", "atlas_source", "pivot")
LICENSE_MARKERS = {"CC0-1.0": ("CC0", "creativecommons.org/publicdomain/zero")}


class ImportError_(Exception):
    pass


def piece_name(path):
    """KayKit names pieces wall.gltf.glb (and some wall_doorway.glb): the name is the stem without .gltf."""
    stem = path.name[: -len(path.suffix)]
    return stem[:-5] if stem.endswith(".gltf") else stem


def find_piece(pack_dir, name, fmt):
    hits = sorted(p for p in pack_dir.rglob("*") if p.suffix.lower() in FORMATS[fmt] and piece_name(p) == name)
    if len(hits) != 1:
        raise ImportError_(f"piece '{name}' ({fmt}): expected one file in {P.rel(pack_dir)}, found {[P.rel(h) for h in hits]}")
    return hits[0]


def budget_from_art_bible(heading):
    """(triangle_budget, texture_size) from the art bible: the budget line labelled **<heading>:** (for
    example "Sourced props (kit dressing)" under Budgets), or else the **Budget:** line of the section whose
    heading contains `heading` (for example "Brief: Levy Bow"). The art bible is the only source of these numbers."""
    text = P.ART_BIBLE.read_text()
    line = next((l for l in text.splitlines() if f"**{heading}:**" in l), None)
    if line is None:
        m = re.search(rf"^(#+) [^\n]*{re.escape(heading)}[^\n]*$", text, re.M)
        if not m:
            raise ImportError_(f"docs/art-bible.md has no budget line **{heading}:** and no heading containing {heading!r}")
        rest = text[m.end():]
        end = re.search(rf"^#{{1,{len(m.group(1))}}} ", rest, re.M)
        section = rest[:end.start() if end else len(rest)]
        line = next((l for l in section.splitlines() if "**Budget:**" in l), None)
    tris = re.search(r"≤\s*([\d,]+)\s*triangles", line or "")
    tex = re.search(r"(\d+)\s*[×x]\s*\1", line or "")
    if not (tris and tex):
        raise ImportError_(f"the {heading!r} section has no parsable '**Budget:** ≤ N triangles ... NxN' line")
    return int(tris.group(1).replace(",", "")), int(tex.group(1))


def yaml_scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return v if re.fullmatch(r"[A-Za-z0-9_./-]+", v) else json.dumps(v)


def write_brief(path, fields, header):
    lines = [f"# {h}" for h in header]
    for k, v in fields.items():
        if v is None:
            continue
        if isinstance(v, list):
            lines.append(f"{k}: [{', '.join(v)}]")
        elif isinstance(v, str) and "\n" in v:
            lines.append(f"{k}: |")
            lines += [f"  {l}" if l else "" for l in v.splitlines()]
        else:
            lines.append(f"{k}: {yaml_scalar(v)}")
    text = "\n".join(lines) + "\n"
    changed = not path.exists() or path.read_text() != text
    if changed:
        path.write_text(text)
    return changed


def existing_text(path, key):
    if not path.exists():
        return None
    return P.parse_brief_yaml(path.read_text(), P.rel(path)).get(key)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack_dir")
    ap.add_argument("--pack", required=True, help="pack id, e.g. kaykit_dungeon_remastered")
    ap.add_argument("--pieces", nargs="*", default=[], help="piece names, optionally NAME:FORMAT (gltf, obj, fbx)")
    ap.add_argument("--glob", help="fnmatch pattern over piece names, e.g. 'wall_*'")
    ap.add_argument("--describe", action="append", default=[], metavar="NAME=TEXT", help="the piece's prompt text for the judge")
    ap.add_argument("--dry-run", action="store_true")
    for k in ("title", "homepage", "url", "author", "license", "version", "archive", "license_file"):
        ap.add_argument(f"--{k.replace('_', '-')}")
    ap.add_argument("--palette", help="comma-separated art-bible palette names for the whole pack")
    ap.add_argument("--budget", help="art-bible budget label or heading, e.g. 'Sourced props (kit dressing)'")
    ap.add_argument("--source-scale", type=float, help="the kit's uniform scale into metres (keeps its grid)")
    ap.add_argument("--prefix", help="asset-id prefix, e.g. kaykit_dungeon_")
    ap.add_argument("--format", choices=sorted(FORMATS), help="default source format")
    ap.add_argument("--pivot", choices=("source", "base", "center"), help="default source (the kit's origin)")
    ap.add_argument("--atlas-source", help="the pack's shared atlas image, relative to the pack dir")
    args = ap.parse_args()
    try:
        return run(args)
    except (ImportError_, P.PipelineError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


def run(args):
    pack_dir = Path(args.pack_dir).resolve()
    downloads = ROOT / ".downloads" / args.pack
    if not pack_dir.is_dir() or downloads.resolve() not in (pack_dir, *pack_dir.parents):
        raise ImportError_(f"{args.pack_dir} must be an extracted pack under .downloads/{args.pack}/")
    sources = P.load_sources()
    pack = dict(sources["packs"].get(args.pack) or {})
    given = {"title": args.title, "homepage": args.homepage, "source_url": args.url, "author": args.author,
             "license": args.license, "version": args.version}
    pack.update({k: v for k, v in given.items() if v is not None})
    missing = [k for k in PACK_META if not pack.get(k)]
    if missing:
        raise ImportError_(f"pack {args.pack} isn't in assets/sources.json yet; give --{' --'.join(m.replace('source_url', 'url') for m in missing)}")
    if pack["license"] not in P.ALLOWED_LICENSES:
        raise ImportError_(f"pack licence {pack['license']!r} isn't allowed (only {', '.join(P.ALLOWED_LICENSES)}); "
                           "another licence is the user's decision")
    if args.archive:
        zp = Path(args.archive).resolve()
        pack["archive"] = {"file": P.rel(zp), "sha256": P.sha256(zp)}
    if not pack.get("archive"):
        raise ImportError_("give --archive (the original download, kept beside the pack) on the first import")
    if (ROOT / pack["archive"]["file"]).exists() and P.sha256(ROOT / pack["archive"]["file"]) != pack["archive"]["sha256"]:
        raise ImportError_(f"{pack['archive']['file']} doesn't match its recorded SHA-256; the download changed")
    if args.license_file:
        lf = (pack_dir / args.license_file).resolve()
        text = lf.read_text(errors="replace")
        if not any(mark in text for mark in LICENSE_MARKERS.get(pack["license"], ())):
            raise ImportError_(f"{P.rel(lf)} doesn't state {pack['license']}; check the licence before importing")
        pack["license_file"] = {"file": P.rel(lf), "sha256": P.sha256(lf)}
    settings = dict(pack.get("import") or {})
    for k in IMPORT_SETTINGS:
        v = getattr(args, k)
        if v is not None:
            settings[k] = [c.strip() for c in v.split(",")] if k == "palette" else v
    settings.setdefault("format", "gltf")
    settings.setdefault("pivot", "source")
    settings.setdefault("prefix", f"{args.pack}_")
    for k in ("palette", "budget", "source_scale"):
        if settings.get(k) is None:
            raise ImportError_(f"no import setting '{k}' for {args.pack}; give --{k.replace('_', '-')}")
    pack["import"] = settings
    budget, texture_size = budget_from_art_bible(settings["budget"])

    names = {}
    for spec in args.pieces:
        name, _, fmt = spec.partition(":")
        names[name] = fmt or settings["format"]
    if args.glob:
        for p in pack_dir.rglob("*"):
            if p.suffix.lower() in FORMATS[settings["format"]] and fnmatch.fnmatch(piece_name(p), args.glob):
                names.setdefault(piece_name(p), settings["format"])
    if not names:
        raise ImportError_("no pieces: give --pieces or --glob")
    describe = dict(d.split("=", 1) for d in args.describe)

    atlas = atlas_source = None
    if settings.get("atlas_source"):
        src = pack_dir / settings["atlas_source"]
        if not src.exists():
            raise ImportError_(f"atlas source {settings['atlas_source']} isn't in the pack")
        atlas_source = P.rel(src)
        atlas = f"assets/atlases/{args.pack}/{src.stem}_{texture_size}.png"

    ids = []
    for name, fmt in sorted(names.items()):
        f = find_piece(pack_dir, name, fmt)
        aid = f"{settings['prefix']}{name}"
        brief_path = P.BRIEFS / f"{aid}.yaml"
        words = name.replace("_", " ")
        prompt = describe.get(name) or existing_text(brief_path, "prompt") or \
            f"The {pack['title']} kit piece '{name}': a {words}, used as downloaded."
        fields = {
            "asset_id": aid, "type": "prop", "source": "download", "pack": args.pack,
            "source_url": pack["source_url"], "author": pack["author"], "license": pack["license"], "source_file": P.rel(f),
            "brief": existing_text(brief_path, "brief") or f"Level dressing from {pack['title']} ({pack['license']}), "
                                                           f"piece '{name}'. Keeps the kit's axes, origin and grid.",
            "prompt": prompt, "triangle_budget": budget, "texture_size": texture_size,
            "source_scale": settings["source_scale"], "pivot": settings["pivot"], "orientation": "source",
            "palette": settings["palette"], "atlas": atlas, "atlas_source": atlas_source,
        }
        header = [f"Written by scripts/tools/import_pack.py (pack {args.pack}; provenance in assets/sources.json).",
                  f"Budget from docs/art-bible.md, \"{settings['budget']}\": the art bible is the only source for these numbers."]
        entry = {"pack": args.pack, "source_url": pack["source_url"], "author": pack["author"], "license": pack["license"],
                 "pack_version": pack["version"], "source_file": P.rel(f), "source_sha256": P.sha256(f)}
        if args.dry_run:
            print(f"import: would write {P.rel(brief_path)} and the sources entry for {aid} ({P.rel(f)})")
        else:
            changed = write_brief(brief_path, fields, header)
            sources["assets"][aid] = entry
            print(f"import: {P.rel(brief_path)} {'written' if changed else 'unchanged'}")
        ids.append(aid)
    if not args.dry_run:
        sources["packs"][args.pack] = pack
        P.save_sources(sources)
        if atlas and not (ROOT / atlas).parent.exists():
            (ROOT / atlas).parent.mkdir(parents=True)
        gd = ROOT / "assets" / "atlases" / ".gdignore"
        if atlas and not gd.exists():
            gd.write_text("")  # the clean stage's input, embedded in each GLB; Godot needn't import it

    rows, failed = [], []
    for aid in ids:
        cmd = [sys.executable, str(ROOT / "scripts" / "pipeline.py"), aid, "--stage", "all"] + (["--dry-run"] if args.dry_run else [])
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if args.dry_run:
            print(proc.stdout + proc.stderr)
            continue
        m = P.load_manifest(aid)
        clean = (m["stages"].get("clean") or {}).get("report") or {}
        val = m["stages"].get("validate") or {}
        ok = proc.returncode == 0
        err = (proc.stderr.strip().splitlines() or [""])[-1] if proc.returncode == 1 else \
            "; ".join(clean.get("errors") or []) or ("" if ok else val.get("message", ""))
        rows.append((aid, clean.get("triangle_count"), clean.get("triangle_budget"), "PASS" if ok else f"FAIL (exit {proc.returncode})", err))
        if not ok:
            failed.append(aid)
            print(proc.stdout + proc.stderr)
    if rows:
        w = max(len(r[0]) for r in rows)
        print(f"\n{'asset':{w}}  triangles / budget  result")
        for aid, tris, bud, res, err in rows:
            over = " OVER BUDGET" if isinstance(tris, int) and isinstance(bud, int) and tris > bud else ""
            print(f"{aid:{w}}  {str(tris):>9} / {str(bud):<6}  {res}{over}" + (f": {err}" if err else ""))
        print(f"import: {len(rows) - len(failed)}/{len(rows)} passed. Judge each: python3 scripts/judge.py packet <id> --stage mesh")
    return 2 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

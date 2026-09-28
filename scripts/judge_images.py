"""Image side of scripts/judge.py. Runs inside headless Blender (numpy and every image format):

    blender -b --factory-startup --python-exit-code 1 -P scripts/judge_images.py -- --job job.json --report out.json

The job lists images to copy into a judge packet (downscaled to a longest side of `max_size`, as
PNG) and images whose main colors to measure. Copies are what the judge sees and what the verdict
log keeps, so a later re-render can never change the evidence behind a logged verdict.

Colors use the clean stage's own Lab conversion and k-means (scripts/blender_cleanup.py), so the
judge's numbers and the correction's numbers are the same measurement. The background is removed
by alpha when the image has any, otherwise by the border color, as the clean stage does for concepts.
"""

import json
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_cleanup import CONCEPT_BG_DE, _hex, _kmeans, _lab_to_srgb, _srgb_to_lab  # noqa: E402


def arg(name):
    argv = sys.argv[sys.argv.index("--") + 1:]
    return argv[argv.index(name) + 1]


def load_pixels(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, img.channels)
    bpy.data.images.remove(img)
    if px.shape[2] == 3:
        px = np.concatenate([px, np.ones((h, w, 1))], axis=2)
    return px


def copy_image(src, dst, max_size):
    img = bpy.data.images.load(src)
    w, h = img.size
    scale = min(1.0, max_size / max(w, h))
    if scale < 1.0:
        img.scale(max(1, round(w * scale)), max(1, round(h * scale)))
    img.filepath_raw = dst
    img.file_format = "PNG"
    img.save()
    size = list(img.size)
    bpy.data.images.remove(img)
    return size


def main_colors(path, k):
    """The image's k main colors (Lab centers, hex, share of foreground pixels), largest first."""
    px = load_pixels(path)
    h, w = px.shape[:2]
    step = max(1, int(np.sqrt(h * w / 60000)))
    sample = px[::step, ::step].reshape(-1, 4)
    if sample[:, 3].min() < 0.5:
        fg = sample[sample[:, 3] > 0.5, :3]
        background = "alpha"
    else:
        b = max(4, min(w, h) // 50)
        rgb = px[:, :, :3]
        border = np.concatenate([rgb[:b].reshape(-1, 3), rgb[-b:].reshape(-1, 3), rgb[:, :b].reshape(-1, 3), rgb[:, -b:].reshape(-1, 3)])
        bg = _srgb_to_lab(np.median(border, axis=0)[None])[0]
        lab_all = _srgb_to_lab(sample[:, :3])
        fg = sample[np.linalg.norm(lab_all - bg, axis=1) > CONCEPT_BG_DE, :3]
        background = _hex(_lab_to_srgb(bg[None])[0])
    lab = _srgb_to_lab(fg)
    if len(lab) == 0:
        return {"background": background, "colors": []}
    # Farthest-point seeding from the median: deterministic, like the clean stage's concept_colors
    seeds = [np.median(lab, axis=0)]
    for _ in range(k - 1):
        d = np.min(np.linalg.norm(lab[:, None, :] - np.array(seeds)[None, :, :], axis=2), axis=1)
        seeds.append(lab[d.argmax()])
    centers, near = _kmeans(lab, np.array(seeds))
    shares = np.bincount(near, minlength=len(centers)) / len(near)
    order = np.argsort(-shares)
    return {"background": background, "foreground_share": round(len(fg) / len(sample), 4),
            "colors": [{"hex": _hex(_lab_to_srgb(centers[i][None])[0]), "lab": [round(float(c), 1) for c in centers[i]],
                        "share": round(float(shares[i]), 3)} for i in order if shares[i] > 0]}


def main():
    job = json.load(open(arg("--job")))
    report = {"status": "ok", "errors": [], "copies": [], "colors": {}}
    try:
        for c in job.get("copy", []):
            os.makedirs(os.path.dirname(c["dst"]), exist_ok=True)
            report["copies"].append({"src": c["src"], "dst": c["dst"], "size": copy_image(c["src"], c["dst"], c.get("max_size", 1024))})
        for path in job.get("colors", []):
            report["colors"][path] = main_colors(path, job.get("clusters", 8))
    except Exception as e:  # report every failure to judge.py
        report["status"] = "error"
        report["errors"].append(f"{type(e).__name__}: {e}")
    with open(arg("--report"), "w") as f:
        json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()

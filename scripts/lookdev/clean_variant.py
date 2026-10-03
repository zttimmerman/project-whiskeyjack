"""Look-dev spike (docs/backlog/spike-look-dev.md): the clean stage with the art bible's shading rule
lifted, for variant assets under assets/lookdev/ only. Never used for shipped assets.

    blender -b --factory-startup --python-exit-code 1 -P scripts/lookdev/clean_variant.py -- \
        --input <rigged raw GLB> --output assets/lookdev/player_b1.glb --params <json> --report <json>

Runs scripts/blender_cleanup.py unchanged except for one step: flat_shade_by_angle (custom normals
cleared, every edge over 30 degrees flat) is replaced by keeping the source's own imported normals,
which for Tripo are smooth. Texture size, colour correction and everything else come from --params.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_cleanup  # noqa: E402


def keep_source_normals(meshes, weld, report):
    report["shading"] = {"mode": "source normals kept (look-dev: no flat shading, no weld)",
                         "custom_normals": [o.name for o in meshes if o.data.has_custom_normals]}


blender_cleanup.flat_shade_by_angle = keep_source_normals
blender_cleanup.main()

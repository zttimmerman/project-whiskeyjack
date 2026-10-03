---
id: decide-art-direction
title: "Decide: which art-bible look rules change after the look-dev spike"
status: done
kind: decision
targets: []
after: [spike-look-dev]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Settle the look rules the art bible questions after `spike-look-dev`'s A/B (`docs/trials/look-dev.md`), before `player-model-rework` and the Phase C kit choice.

## Question

Which of the spike's proposed rule changes does the art bible adopt? Evidence: at 256 px the face smears even smooth-shaded; 512 px brings the eyes and brows back and 1024 px is close to the 2048 px source; B2 lighting is the biggest change from the gameplay camera and runs in Compatibility; Forward+ alone changes 0.3% of the image. Every variant runs at 1–4 ms a frame on the M2 Pro at 1280×720.

## Options

1. **Characters' albedo:** 1024 px (0.7 MB VRAM each), 512 px (the floor), or keep 256 px.
2. **Character shading:** keep the source's smooth normals (flat-by-30° stays for props, kit pieces and rigid-part characters), or keep flat shading everywhere.
3. **Level lighting standard like B2** (warmer ambient 0.8, filmic tonemap, depth fog, torches range 7 m with a steeper falloff, a dim cool key; fog and tonemapping allowed, bloom/SSAO/SSR still out), or keep today's.
4. **Renderer:** stay on Compatibility, or move to Forward+ (only pays with SSAO, shadows and PBR, i.e. with C).

## Recommendation

1024 px characters, smooth character shading, the B2 lighting standard, and stay on Compatibility. Smooth shading needs the B2 lighting (under today's lighting the flat facets catch the fill light and A reads brighter), so adopt 2 and 3 together. The proposed art-bible text is in `docs/trials/look-dev.md` → Proposed art-bible changes.

## Outcome

Decided by the user (2026-10-02), adopting all four proposals: (1) character textures 1024 px (512 the floor), still albedo only; (2) smooth shading on continuous-skin characters (props, kit pieces and rigid-part characters keep the 30° flat rule); (3) the B2 lighting standard (warmer ambient, filmic tonemap, depth fog, torch range ~7 m with steeper falloff, dim cool key), staying on Compatibility; (4) move away from KayKit (toy-like) toward brush-built shells and a kit closer to the chosen look. Implementation: `art-rules-b2`; kit replacement: `kit-replacement`. Variant C was approved and is running (`look-dev-c`).

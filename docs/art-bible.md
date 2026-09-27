# Art Bible (v0, minimal)

Derived from shipped assets and `CLAUDE.md` → Visual Style Rules. Faction groupings and design briefs come in a later pass, once `docs/world/` exists.

**Style:** The look is stylized low-poly with generous budgets: bold colors, readable silhouettes, and simple albedo-only textures over realism.

## Palette

Hex values are either set exactly in a scene or script, or sampled from a shipped texture. Sampled values were quantized to 24-step bins, so they're approximate.

| Name | Hex | Derived from | Use |
|---|---|---|---|
| Garrison Teal | `#0C5454` | Player tunic (`player_character_texture_diffuse.png`, sampled) | Imperial cloth, player identity |
| Saddle Leather | `#4A2A10` | Player straps and boots (same texture, sampled) | Leather, harness, belts |
| Barrow Oak | `#8C5933` | Crate/barrel albedo `Color(0.55, 0.35, 0.2)` (`Level1.tscn`) | Timber, shafts, shield faces |
| Old Bone | `#CCB484` | Skeleton base color (`archer_enemy_skeleton_baseColor.png`, sampled) | Bone, parchment, pale cloth |
| Wet Slate | `#736B66` | Wall albedo `Color(0.45, 0.42, 0.40)` (Level scenes) | Dressed stone, roads |
| Rain Stone | `#4D4740` | Wall albedo `Color(0.3, 0.28, 0.25)` | Field stone, oilskin |
| Peat Black | `#2E2926` | Floor albedo `Color(0.18, 0.16, 0.15)` | Peat, soot, deep shadow areas |
| Blackened Iron | `#242424` | Torch iron (`prop_torch_material_diffuse.png`, sampled) | Iron, helms, fittings |
| Torch Amber | `#FFCC80` | Torch light `Color(1.0, 0.8, 0.5)` (Level scenes) | Firelight, warmth, the player's realm |
| Signal Red | `#C71F14` | HP bar fill (`HUD.gd:52`) | Blood, danger, rare accents |
| Tarnished Gold | `#E6BF1A` | XP bar fill (`HUD.gd:55`) | Brass, rank marks, reward accents |
| Overcast Blue | `#8C8CCC` | UI panel border (`HUD.gd:40`) | Cold light, rain, the Sleet |

**Balance:** scenes should be mostly the cool, muted colors (Wet Slate, Rain Stone, Peat Black), with Torch Amber marking wherever people live. Save Signal Red and Tarnished Gold for accents.

## Budgets (from CLAUDE.md; authoritative)

- **Vertices:** characters 2,000–5,000; props and small objects 500–2,000. Count Blender mesh vertices with modifiers applied, summed across the whole `.glb`.
- **Textures:** albedo (base color) only, one texture per asset, 128×128 to 256×256, or vertex colors. No normal, roughness, metallic, occlusion, emissive or specular maps.
- **Rendering:** one directional light plus ambient per area. Local lights are allowed only for visible sources such as torches and candelabras. No bloom, SSAO or SSR.
- **Post-MVP, not now:** palette quantization, vertex-snap or affine-warp shaders, pixel fonts.

## STYLE BLOCK

Paste this in front of any image or 3D generation prompt, then add the entry's visual description after it:

```
Stylized low-poly 3D game art with generous polygon budgets: clean readable
silhouette, slightly exaggerated proportions, smooth limbs, recognizable face
and hands. Simple hand-painted albedo-only texture, matte surfaces, no normal
maps, no metallic or glossy PBR shine, no photorealism. Muted cold palette of
wet slate, rain stone and peat black with warm torch-amber accents. Soft single
directional light, overcast mood, no bloom, no pixel art, no PS1 jitter.
```

# Trial: a target look from the Souls series and The Witcher (2026-10-07)

**Status: steps 1–3 done (free); the user adopted the rule changes on 2026-10-08 (`decide-target-look`), and the four concepts are ready to run (paid, each confirmed through the tripo skill).** The user's references (2026-10-05) are the Souls series, Elden Ring above all, and The Witcher 3: a "dark epic fantasy" that fits the Malazan-flavoured world in `docs/world/`. Look-dev C found that the concept image, not the model tier, limits the look (`docs/trials/look-dev.md`), so this spike starts at the concept. Spend so far: **0 credits**. The four concept prompts below are ready, with the pipeline's dry-run commands; running all four is **60 credits** (banana_pro, observed 15 each).

**Short version:** most of the target look already fits the hard rules. The references' look comes from value structure, restrained colour, worn layered costume, fog and controlled detail, and an albedo-only, 5,500-triangle, Compatibility-rendered game can carry all of them. Two lines conflict and are the user's call (`decide-target-look`): CLAUDE.md's and the art bible's **"bold colors"** Style line, and the FORM block's **"slightly exaggerated proportions"** (CLAUDE.md: "slightly large heads"). Two more bend: Tarnished Gold's plain colour ("bright golden yellow") is too saturated for worn brass, and the "wear goes in the albedo, never in the prompt" rule has to allow colour-level wear words, because the concept is where the albedo's wear comes from.

## 1. What the look is made of

Each trait says what the references do, then what a stylized, budgeted game can keep. Where a claim is sourced it's cited; the rest is observation of the games, marked *(obs.)*.

| Trait | Souls series / Elden Ring | The Witcher 3 | What carries over to us |
|---|---|---|---|
| **Palette and saturation** | Dark Souls III is "dominated by grays, browns, and blacks, punctuated by fiery reds and ethereal whites" [1]. Elden Ring adds a gold key (the Erdtree's light) over a slight grey cast [2]. | Muted on purpose: Vesemir's concept had "brighter" beige and "vibrant brown" pieces, shipped as "more muted colors… a washed-out or used appearance" [3]. The 2013–14 demos were gloomier still; the release was graded warmer [4]. | Low-saturation earth tones over most of every frame; saturation spent only on accents (fire, gold, blood, magic). **Our palette already does this** (the Balance line: mostly Wet Slate, Rain Stone, Peat Black). |
| **Value range** | Mostly dark-to-mid values; bright values are rare and are the focal points (bonfires, the Erdtree, the player's lit weapon) *(obs.)*. | Mid values outdoors, deep interiors; faces kept a step lighter than the costume *(obs.)*. | "The eyes are guided to the point where the contrast of value is high" [5]: a dark costume with a lighter face and one mid-value layer reads at distance. Value, not hue, does the read. |
| **Area colour identity** | Shadow of the Erdtree's artists, limited to the Gravesite Plain's assets, made them read as a new place by moving the grade "from sepia tones to… yellow and black" [6]. | Each region has its own grade: Velen's damp browns, Skellige's cold grey-blue *(obs.)*. | A per-area grade through the levers we have (ambient colour, fog colour, key colour, tonemap exposure), within the B2 standard. Cheap, and it lets one kit serve several areas. |
| **Detail control and atmosphere** | Akiman (Capcom): the level of detail "is carefully controlled at every step, so the player's imagination is constantly stimulated", with atmospheric perspective as a key tool [7]. FromSoftware's environment team builds scenes by composition rules over "landscape, architecture, shadows, and fog" [8]. | Fog and haze over distance in every exterior *(obs.)*. | Strong fit for a low-budget game: detail is concentrated where the eye lands (face, chest, weapon) and fog takes the rest. Our depth fog does atmospheric perspective; nothing here needs volumetrics. |
| **Silhouette and proportion** | Strong, recognisable silhouettes [1]; knights read from helm shape, pauldrons and the cape or tabard line *(obs.)*. Proportions are naturalistic, slightly heroic (broad shoulders, long legs), never chibi *(obs.)*. | Historically grounded: the team visited museums and worked out "how he could put [the armour] on" [9]. Naturalistic proportions *(obs.)*. | Naturalistic adult proportions, with the silhouette carried by **costume masses** (helm, mantle or cape, pauldrons, skirt line) rather than enlarged heads. Stylization as "omission and exaggeration" [5]: drop small parts, enlarge the few big shapes. |
| **Materials and wear** | Weathered metal, layered cloth and leather; "the metal shows signs of weathering" [1]. Nothing is new *(obs.)*. | Gambesons, mail, leather and fur, worn and repaired, functional layering [9][10]. | Thick, layered, functional clothing (a quilted gambeson, a tabard over mail, a wool mantle) that's **one continuous mass** for the rigger. Wear lives in the albedo (rain-darkened hems, scuffs, faded dye), which the 1024 px character texture can now hold. |
| **Lighting** | One strong key per scene (low gold sun, or firelight in the dark), deep shadow, fog everywhere; interiors are near-black between light sources *(obs.)*. | Warm-cool split: warm fire against cool overcast *(obs.)*. | The B2 standard already is this indoors (warm torch pools, warm dark between, fog, a dim cool key). Outdoor areas would add a low warm or cold key per area. No bloom, SSAO or SSR is needed for the read. |
| **Architecture scale** | Monumental: small figures under huge vertical gothic structures; the Erdtree as a landmark in every sky [2] *(obs.)*. | Human-scale villages under big skies and ruined keeps *(obs.)*. | Not a character concern; it goes to `kit-replacement` and the level briefs (tall brush shells, landmarks seen through fog). |
| **Proof it survives low-poly** | *Bloodborne PSX* keeps Yharnam and its enemies recognisable with "less detail" and "fewer polygons", the beasts reading from silhouette alone [11]. | | The look isn't a fidelity tier. It survives at our budgets if the silhouette and value structure are right. |

**Sources**
1. Dark Souls III *Design Works*, as summarised by web search; the pages it came from were unofficial mirrors and couldn't be checked first-hand, so treat this row's quotes as **low confidence** until checked against the book.
2. Elden Ring's grey cast and the Erdtree landmark: https://www.gfinityesports.com/article/elden-ring-mod-colourful-vibrant-reshade, https://spawningpoint.com/article/elden-ring-pc-ps5-xbox-series-xs-review-2026
3. Vesemir's concept against his shipped colours: https://www.player.one/witcher-3-mod-gives-vesemir-his-early-concept-design-153283
4. The Witcher 3's grade against its 2013–14 demos: https://www.dsogaming.com/?p=88572, https://finalboss.io/the-witcher-3-remastered-visuals-why-some-scenes-look-worse
5. Yuichiro Fujita on silhouette, value contrast and stylization: https://80.lv/articles/studying-character-art-silhouette-and-contrast
6. CEDEC 2025, Shadow of the Erdtree (Hidenori Sato, Reiji Katahira), asset reuse through colour: https://igm.gg/media/d/khudozhniki-shadow-of-the-erdtree-maskirovali-reiuz-assetov-s-pomoshchiu-tsveta-dcab91eb
7. Akiman on Elden Ring's controlled detail and atmospheric perspective: https://automaton-media.com/en/news/this-is-what-it-means-to-be-good-at-art-capcom-veteran-akiman-on-why-elden-rings-environments-stand-out-even-among-higher-fidelity-aaas/ (English summary: https://ixbt.games/en/news/2026/04/07/408937-vot-cto-znacit-byt-masterom-iskusstva-veteran-capcom-o-tom-pocemu-mir-elden-ring-vpecatliaet-daze-sredi-sovremennyx-aaa-igr.amp.html)
8. CEDEC 2025 composition lecture: https://automaton-media.com/en/?p=64712
9. Stan Just (CD Projekt Red) on armour design and museum research: https://www.gamereactor.eu/the-witcher-3-the-art-of-the-wild-hunt/
10. Kai Greter, "History and Fantasy: Armor in The Witcher 3": https://omeka.emich.edu/s/thedigitalmedieval/page/kai-greter-history-and-fantasy-armor-in-the-witcher-3-wild-hunt (behind a browser check; cited for the title and subject only)
11. *Bloodborne PSX*: https://en.wikipedia.org/wiki/Bloodborne_PSX, https://www.techradar.com/news/bloodborne-is-now-on-pc-if-you-can-stomach-its-ps1-era-graphics

The web turned up little first-hand FromSoftware art-direction text in English; the CEDEC lectures [6][8] and Akiman [7] are the strongest sources. The palette and lighting rows lean on observation, which the concept round will test.

## 2. Against the art bible

| Rule (where it lives) | Verdict | Why |
|---|---|---|
| Albedo only, one texture, no PBR maps (CLAUDE.md, art bible → Budgets) | **Holds** | The look is value, colour and wear, all albedo. Look-dev C showed PBR adds sheen, not form. |
| Triangle budgets (5,500 per character) | **Holds** | Detail is controlled, not maximised [7]; *Bloodborne PSX* [11]. The costume needs a few big masses, not many small parts. |
| 1024 px character albedo, smooth character shading (B2) | **Holds** | 1024 px is what lets painted wear and a readable face exist at all. |
| Compatibility renderer; no bloom, SSAO, SSR; fog and filmic tonemap allowed | **Holds** | Depth fog does atmospheric perspective. Contact darkening that SSAO would give comes from painted grime in the albedo, if anywhere. |
| B2 level lighting standard | **Holds** | Already warm pools, warm dark, fog, a dim cool key. Per-area grading (section 1) is a use of it, not a change. |
| One directional light plus ambient; local lights only for visible sources | **Holds** | The references light by one key and visible fires. |
| CONCEPT LIGHTING block (flat, shadowless) | **Holds** | Required by multiview-to-3D, whatever the look. The darkness lives in the albedo values and the level lighting, not in the concept's light. |
| Palette and Balance line (mostly cool, muted; accents reserved) | **Holds** | Already the references' structure. Garrison Teal "deep dark teal" is a muted primary. |
| Faction groupings and reserved colours | **Holds** | Faction read from a primary colour suits a game where everyone else is grey and brown. |
| "Silhouettes matter" (CLAUDE.md) | **Holds, stronger** | The target look leans on it harder. |
| FORM block: "restricted muted palette", "clean, readable silhouette", "no photorealism, no glossy PBR shine" | **Holds** | |
| FORM block: "Flat color blocking with minimal fine surface detail" | **Bends** | Right for geometry (fine modelled detail dies at `face_limit`), but the target look wants worn, varied surface colour. Keep "minimal modelled detail"; allow "painted wear". |
| Prompt rule: wear and small marks go in the albedo, never in the prompt (art bible → Design brief format) | **Bends** | The albedo comes from the concept (multiview copies its colours, colour correction restores toward it), so a clean concept gives a clean albedo. Colour-level wear words ("faded", "rain-darkened", "soot-darkened") are allowed in the variants below; shape-level wear (rips, dents, frayed edges) stays out, as the rule intends. |
| Tarnished Gold plain colour "bright golden yellow" (`#E6BF1A`, from the XP bar) | **Bends** | Reads as new brass. Worn gold in the references is darker and duller. Proposed plain colour: "dull dark antique gold" (around `#9C7A2E`) for assets, keeping `#E6BF1A` for the UI. |
| Style line: "bold colors" (CLAUDE.md → Visual Style Rules; art bible → Style) | **Conflicts** | The references are low-saturation and value-led. The palette has already drifted this way; the Style line hasn't. **A direction change for the user.** |
| FORM block "slightly exaggerated proportions"; CLAUDE.md "Exaggerated proportions (slightly large heads, stylized hair) are fine and encouraged" | **Conflicts** | The references use naturalistic adult proportions; large heads read as cute, against "wet boots, dry jokes". Tripo's `t_pose` template already appends "Keep natural body proportions and anatomy" (tripo skill), so today's concepts get both instructions at once. |
| Player identity mark: spiky dark hair (player brief) | **Question** | Spiky hair reads as a JRPG hero; the Line's signature is a half-helm with a neck flap (`02-factions.md`). Variants B and D test the two ends. |

**Rule text, adopted by the user on 2026-10-08** (applied to CLAUDE.md and `docs/art-bible.md`; Tarnished Gold became `#9C7A2E`, and the old `#E6BF1A` stays for the UI as a new palette row, XP Gold):

> **Style (CLAUDE.md and art bible):** The look is stylized low-poly with generous budgets: dark epic fantasy after the Souls series and The Witcher. Restrained, earthy colour with saturated accents saved for fire, gold, blood and magic; the read comes from value contrast and readable silhouettes; simple albedo-only textures, worn and lived-in, over realism.

> **CLAUDE.md, Silhouettes:** characters should read clearly from the gameplay camera distance. Proportions are naturalistic and adult, slightly heroic (broad shoulders, long legs); the silhouette is carried by costume masses (helms, mantles, pauldrons, the skirt line), not by enlarged heads.

> **FORM block:**
> ```
> Stylized low-poly 3D game asset for a dark fantasy game, with a clean, readable
> silhouette and naturalistic adult proportions. Large simple forms with minimal
> modelled detail; matte hand-painted albedo-only texture with worn, faded colour,
> restricted muted earthy palette. No photorealism, no glossy PBR shine, no pixel art.
> ```

> **Palette, Tarnished Gold:** plain colour "dull dark antique gold"; the `#E6BF1A` UI fill keeps its own row.

With the FORM text adopted, the pipeline recomposes all four prompts from it (it reads FORM from the art bible), so the composed prompts no longer say "slightly exaggerated" against "natural adult proportions". The briefs then dropped their own "natural adult proportions" and "faded", which FORM now carries.

## 3. Concept brief: the player in the target look

The player is still a Frontier Line soldier (`02-factions.md`: half-helm with a neck flap, knee-length tunic, rectangular shield; Garrison Teal, Saddle Leather, Blackened Iron; wool, oiled leather, riveted iron). The four variants differ on purpose, so the round chooses a direction and not just a picture:

| | Variant | Reference | Silhouette at 10 m | Risk for the pipeline |
|---|---|---|---|---|
| **A** | Line soldier, grounded | The Witcher 3 | Quilted gambeson to the knee, short leather mantle, bare head | Low: one thick continuous mass, like today's tunic |
| **B** | Souls footsoldier | Dark Souls | Rounded iron half-helm with a neck flap, wide pauldrons, mail over a tabard | Pauldrons are separate-looking masses; a helm hides the face the player sees in dialogue |
| **C** | Wanderer | Elden Ring | Hooded shoulder cape, high-collared coat, greaves | The cape's hem moves with the back: skin stretch like the skirt's, and no cloth bones |
| **D** | Control: today's design, grounded | — | Today's tunic, vest and spiky hair, natural proportions, darker and worn | Lowest: tests the tone change alone |

All four keep a knee-length skirt (so `skirt_reweight` applies), empty hands, a T-pose and colours by palette name. Each is a brief, `assets/briefs/player_look_{a,b,c,d}.yaml` (budgets copied from the art bible, as the P2 parts brief did), so the concept stage runs, records and approves each one exactly as for any asset. The winner's brief carries on to multiview and model as the look-dev variant; the shipped player is untouched.

**Brief prompts** (palette names; the pipeline swaps in plain colours and prepends FORM and CONCEPT LIGHTING):

- **A:** A weathered frontier soldier in his thirties, broad shoulders, lean build. A thick quilted Garrison Teal gambeson to the knee, split front and back, cinched by a wide Saddle Leather belt. A short Saddle Leather shoulder mantle, Blackened Iron bracers, tall Saddle Leather boots. Short cropped dark hair, stubble, a tired face. Rain-darkened colours, dark overall, lighter face. Empty open hands, T-pose.
- **B:** A grim imperial footsoldier, heavy armoured silhouette. A rounded Blackened Iron half-helm with a long leather neck flap, face visible. A Blackened Iron mail shirt to the hips over a knee-length Garrison Teal wool tabard, wide rounded Blackened Iron pauldrons, a broad Saddle Leather belt with one Tarnished Gold buckle, Saddle Leather gloves and boots. Matte, soot-darkened colours. Empty open hands, T-pose.
- **C:** A lone wandering soldier, tall and lean. A thick Peat Black wool shoulder cape, hood lowered, over the shoulders and upper back. Beneath it a knee-length Garrison Teal padded coat with a high collar and a wide Saddle Leather belt, Blackened Iron vambraces and greaves, Saddle Leather boots. Dark hair tied back, a gaunt weathered face, one small Tarnished Gold collar clasp. Muted, dark colours. Empty open hands, T-pose.
- **D:** A young frontier soldier, lean build, in a knee-length Garrison Teal wool tunic that flares at the hem, a fitted Saddle Leather vest with two straps crossing the chest, a wide belt, Blackened Iron bracers and tall Saddle Leather boots. Short spiky dark hair, damp and swept back, a serious, tired face. Rain-darkened colours, dark overall, lighter face. Empty open hands, T-pose.

Each is phrased positively (tripo skill rule 6): "face visible" rather than "no visor", "hood lowered" rather than "no hood up", "empty open hands" as today.

**Length:** Tripo's text-to-image prompt limit is 1,024 characters (`tripo docs --topic commands/generate`). The composed prompts (with the adopted FORM block) are 954 (A), 974 (B), 987 (C) and 926 (D) characters, under the limit but close; FORM and CONCEPT LIGHTING take about 540 of them. The pipeline doesn't check the length (`pipeline-prompt-length`).

**Dry run** (free, writes nothing): `python3 scripts/pipeline.py player_look_<k> --stage concept --dry-run` for each, all exit 3 ("generate through the tripo skill"). Each prints:

```
tripo generate text-to-image '<FORM> <CONCEPT LIGHTING> <prompt with plain colours>' --model banana_pro --param template=t_pose --param aspect_ratio=3:4 -o .tripo-out/player_look_<k>/concept-1 --no-open --json
```

The four commands as printed on 2026-10-08 (A, B, C, D):

```
tripo generate text-to-image 'Stylized low-poly 3D game asset for a dark fantasy game, with a clean, readable silhouette and naturalistic adult proportions. Large simple forms with minimal modelled detail; matte hand-painted albedo-only texture with worn, faded colour, restricted muted earthy palette. No photorealism, no glossy PBR shine, no pixel art. Flat, even, shadowless lighting from all sides on a plain, uniform mid-grey background. Every surface shows its true base color at the same brightness, front and back, with no cast shadows and no highlights. A weathered frontier soldier in his thirties, broad shoulders, lean build. A thick quilted deep dark teal gambeson to the knee, split front and back, cinched by a wide dark reddish-brown belt. A short dark reddish-brown shoulder mantle, near-black charcoal bracers, tall dark reddish-brown boots. Short cropped dark hair, stubble, a tired face. Rain-darkened colours, dark overall, lighter face. Empty open hands, T-pose.' --model banana_pro --param template=t_pose --param aspect_ratio=3:4 -o .tripo-out/player_look_a/concept-1 --no-open --json

tripo generate text-to-image 'Stylized low-poly 3D game asset for a dark fantasy game, with a clean, readable silhouette and naturalistic adult proportions. Large simple forms with minimal modelled detail; matte hand-painted albedo-only texture with worn, faded colour, restricted muted earthy palette. No photorealism, no glossy PBR shine, no pixel art. Flat, even, shadowless lighting from all sides on a plain, uniform mid-grey background. Every surface shows its true base color at the same brightness, front and back, with no cast shadows and no highlights. A grim imperial footsoldier, heavy armoured silhouette. A rounded near-black charcoal half-helm with a long leather neck flap, face visible. A near-black charcoal mail shirt to the hips over a knee-length deep dark teal wool tabard, wide rounded near-black charcoal pauldrons, a broad dark reddish-brown belt with one dull dark antique gold buckle, dark reddish-brown gloves and boots. Matte, soot-darkened colours. Empty open hands, T-pose.' --model banana_pro --param template=t_pose --param aspect_ratio=3:4 -o .tripo-out/player_look_b/concept-1 --no-open --json

tripo generate text-to-image 'Stylized low-poly 3D game asset for a dark fantasy game, with a clean, readable silhouette and naturalistic adult proportions. Large simple forms with minimal modelled detail; matte hand-painted albedo-only texture with worn, faded colour, restricted muted earthy palette. No photorealism, no glossy PBR shine, no pixel art. Flat, even, shadowless lighting from all sides on a plain, uniform mid-grey background. Every surface shows its true base color at the same brightness, front and back, with no cast shadows and no highlights. A lone wandering soldier, tall and lean. A thick very dark brown-black wool shoulder cape, hood lowered, over the shoulders and upper back. Beneath it a knee-length deep dark teal padded coat with a high collar and a wide dark reddish-brown belt, near-black charcoal vambraces and greaves, dark reddish-brown boots. Dark hair tied back, a gaunt weathered face, one small dull dark antique gold collar clasp. Muted, dark colours. Empty open hands, T-pose.' --model banana_pro --param template=t_pose --param aspect_ratio=3:4 -o .tripo-out/player_look_c/concept-1 --no-open --json

tripo generate text-to-image 'Stylized low-poly 3D game asset for a dark fantasy game, with a clean, readable silhouette and naturalistic adult proportions. Large simple forms with minimal modelled detail; matte hand-painted albedo-only texture with worn, faded colour, restricted muted earthy palette. No photorealism, no glossy PBR shine, no pixel art. Flat, even, shadowless lighting from all sides on a plain, uniform mid-grey background. Every surface shows its true base color at the same brightness, front and back, with no cast shadows and no highlights. A young frontier soldier, lean build, in a knee-length deep dark teal wool tunic that flares at the hem, a fitted dark reddish-brown vest with two straps crossing the chest, a wide belt, near-black charcoal bracers and tall dark reddish-brown boots. Short spiky dark hair, damp and swept back, a serious, tired face. Rain-darkened colours, dark overall, lighter face. Empty open hands, T-pose.' --model banana_pro --param template=t_pose --param aspect_ratio=3:4 -o .tripo-out/player_look_d/concept-1 --no-open --json
```

These match tripo skill rule 4 (`banana_pro`, `template=t_pose`, a 3:4 portrait frame, no `--for`, no `--then`). `generate` has no `--dry-run` of its own, so this is the whole free check.

**Cost:** 4 × 15 = **60 credits** (banana_pro text-to-image, observed 15 on 2026-09-27 at the same parameters). Balance at the last handoff: 365. Every call needs the user's yes through the tripo skill, at `used / 500` per session.

## 4. Style anchor plan

**The anchor is one approved image every later concept is conditioned on,** so the player, the Line's soldiers, the Hessane and the dead come out in one hand.

1. **Pick:** the user chooses one of A–D (or a refine of one, `--refine N --edit`, 15 credits). That concept is approved with `--approve-concept N` as usual and doubles as the style anchor.
2. **Store:** its SHA-256 and path go in the art bible as a new "Style anchor" line (the image stays in the gitignored `.tripo-out/`, like every concept; a committed copy is the user's call, since images are kept out of git today).
3. **Condition:** later concepts are made with **image-to-image with the anchor as a reference** instead of text-to-image: `tripo generate image-to-image` takes `inputs` (up to 10 reference images on the gemini family, which includes banana_pro), referenced in the prompt as `[image 1]` (`tripo docs --topic commands/generate`). The prompt names the new subject and says "in the art style, palette and rendering of [image 1]". Same cost as a concept (banana_pro image-to-image was observed at 15). The pipeline doesn't support it yet (its `--refine` edits one image into a new version of itself): `pipeline-style-anchor` adds a `style_anchor` reference to briefs and composes the call.
4. **Judge:** the asset judge gets the anchor in the packet and checks palette and value structure against it, alongside the brief.

The first test of the anchor is cheap: one Barrow-levy or Line-soldier concept through it (15 credits), judged against the anchor.

## 5. Model and rig the winner (paid, not run)

As the item scopes it: multiview (10) → P1 model at `face_limit` 5,000 (50) → rig v1.0 (25), about **85 credits** (the item's 55–75 predates the observed P1 multiview cost of 50), built through the pipeline into gitignored `assets/lookdev/` and rendered beside B2 in `scenes/lookdev/LookDev.tscn` with the same shots. This waits on the user's pick.

## Spend

| Step | Credits |
|---|---|
| Research, reconciliation, briefs, dry runs | 0 |
| Concepts (4 × banana_pro) | not run; 60 estimated |
| Multiview, model, rig of the winner | not run; about 85 estimated |

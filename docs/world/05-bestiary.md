# 05 — Bestiary

**Rigging rule:** humanoids map onto Godot's `SkeletonProfileHumanoid` so the shared animation library retargets onto them (CLAUDE.md → Rigging & Animation). Proportions may vary; the bone set may not. **The quadruped isn't covered by the humanoid library.** It needs its own skeleton and animation set, which makes it the costliest entry here.

---

## 1. Barrow-levy *(humanoid; canon, `archer_enemy.glb`)*

**Why the March makes them inevitable:** the terraces are one enormous graveyard. The builders' levies were buried standing, in file order, with their kit. The Stillreach lies just under the stone, and the Hessane rites kept it shut. Breach a barrow (the road, the Charter, a Sett-boar) and the rain carries the Still into the bones. Every barrow is a squad; every terrace, a company.

**Why melee and archer share a silhouette:** every levy was issued the same harness, a short blade *and* a short recurve bow, and was drilled to loose arrows and then close. The dead repeat their last order. The **Front-file** (head of each row) advance with blades. The **Back-file** hold and shoot. It's the same body and kit; only the posture and what's in hand differ.

**Body plan:** human-scale humanoid. The existing 28-bone rig must be mapped to the humanoid profile. **The MVP ships this one model with two variants.**
**Variants:** Front-file melee (`BaseEnemy.tscn`: hunched, blade forward) · Back-file archer (`ArcherEnemy.tscn`: upright, bow drawn).
**Weapons are separate prop assets**, not part of the body mesh. Each is held in a hand socket: the **Levy Blade** in `hand_r`, the **Levy Bow** in `hand_l`. The rig's bone names live only in `data/rigs/barrow_levy_sockets.tres`. Briefs are in `docs/art-bible.md`.
**Secondary readability cue:** in case posture and weapon don't read at distance, Back-file levies carry faded **Signal Red** rag wrappings on the forearms and brow, as a material variant of the skeleton's albedo. Front-file levies stay unwrapped Old Bone.
**Gameplay hook:** a levy killed in a Still-pool re-forms unless Kindled or warded, and Kindle hits always stagger.

An Old Bone skeleton stained peat-brown at the joints, in a rotted Saddle Leather harness. Scraps of wool cling to the ribs, and roots thread the pelvis. Front-file hunch forward with a short Blackened Iron blade; Back-file stand straight with a small recurve bow, faded Signal Red rags wound around forearms and brow.

## 2. Line Deserter *(humanoid; human; post-MVP)*

Frontier Line soldiers who walked away and now rob the road for whoever pays.
**Body plan:** standard humanoid with the player's proportions, so animation retargets directly.
**Gameplay hook:** they use the **player's own moveset** (dodge roll, 3-hit combo, heavy attack) with readable wind-ups. It's a mirror fight that teaches the player's timing, and it needs no new animations.

A Garrison Teal tunic gone grey-brown with mud, with a pale square where the Notch was cut away. Mismatched Saddle Leather straps and a dented Blackened Iron half-helm over an unshaven, hollow face. The shield has been scraped back to bare Barrow Oak.

## 3. Peat-drowned *(humanoid; heavy; post-MVP)*

Fen bog-bodies raised by the same Stillreach seep, preserved in peat rather than reduced to bone.
**Body plan:** thick-torsoed, hunched humanoid; standard bone set.
**Gameplay hook:** a **peat crust** gives heavy damage reduction until it's Kindled off. Their grab roots the player briefly. They're slow, so keep moving and save Kindle for them.

A hunched, heavy body of Saddle Leather-dark skin shrunk tight over bone, crusted in cracked slabs of Peat Black peat. Dripping bog water and trailing reeds, with a flattened face pressed into the skin. It moves like something wading.

## 4. Choir-warden *(humanoid; elongated elite; post-MVP)*

Tall figures in the Hollow Choir's upper alcoves, not the same people as the levies. Whether they guard the dead or conduct them is left unexplained.
**Body plan:** humanoid with limbs about 1.3× normal length; standard bone set. **Retarget risk:** limb-length offsets are needed in the bone map, so test early.
**Gameplay hook:** its **song** re-forms fallen levies in range instantly. Stagger or heavy hits interrupt it, making it the kill-priority target. It's the Choir's boss candidate (post-MVP).

An impossibly tall, narrow figure of polished Old Bone, draped in long strips of Rain Stone cloth, with a faceless elongated skull. Fingers twice human length hold a thin Tarnished Gold rod. It stands dead still in an alcove, dust on its shoulders.

## 5. Sett-boar *(quadruped; post-MVP)*

A badger-built boar native to the peat, rooting into barrows for marrow. Every one is a breacher.
**Body plan:** **quadruped**, low and wide with digging forelimbs. **Rigging risk:** it needs its own quadruped skeleton and animation set (idle, run, charge, dig, stagger, death), none of it covered by the shared humanoid library.
**Gameplay hook:** a **charge** to dodge through, and a **burrow** it erupts from under the player. Scripted Sett-boars break barrow walls, opening shortcuts and releasing levies.

A pony-sized beast with a striped Peat Black and Old Bone badger face, a bristled Saddle Leather-brown hide, and huge mud-caked digging claws. Short tusks, a bone wedged in its jaw, moss on its back. It's built like a battering ram, close to the ground.

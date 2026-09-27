# 03 — Magic: the Reaches

Magic is **reaching**: opening yourself to a **Reach**, one of several realms lying under the world like water under ice. Each has its own cost and look. Most people can't reach at all, and a squad mage holds one.

**Gameplay split:** the **player** has exactly one ability, *Kindle* (Lowfire), limited by a **cooldown**, with no resource. **Mages, enemies and the environment** carry every other Reach.

> **Implementation note:** the MVP cost is a **cooldown only**. It uses the countdown-float pattern the combat code already has (`Player._tick_attack`, `scenes/player/Player.gd:330-340`; `BaseEnemy._attack_cooldown_timer`, `scenes/enemies/BaseEnemy.gd:85`): a `_kindle_timer` for the active window and a `_kindle_cooldown` for the lockout, both ticked in `_tick_attack`. There's no new resource and no HUD change; the weapon's ember glow is the only feedback. Starting values are 5 s active and 15 s cooldown. **Stamina is the intended post-slice upgrade.** No stamina exists in code today (`scripts/stats/CharacterStats.gd:9-16`; dodge and attacks are free, `Player.gd:94-107`), and once a pool shared with dodge is built, Kindle's cost moves onto it.

---

## Lowfire *(player-usable)*

The Reach of banked heat. Reaching into it spends your own warmth.
**Kindle:** set the weapon smoldering for a few seconds, then wait out the cooldown. While it lasts, hits always stagger **Barrow-levies**, and levies killed can't re-form. It strips the **Peat-drowned**'s crust, and it can light a **ward-stone** in melee range.
**Design intent:** one burn per fight, spent on the right moment. After the slice, a stamina cost will make every use trade the roll for the burn.
**Look:** ember motes and heat shimmer, done with Torch Amber particles, never emissive textures.

A blade edge glowing Torch Amber, trailing slow sparks upward through grey rain. Heat haze bends the air around the wielder's hands, and their breath steams. Blackened Iron shows through the glow like coal.

## Stillreach *(enemy and environment)*

The Reach of stopped time. It lies close under the terraces, and the Hessane rites kept it shut. With the rites gone and barrows breached, rain carries it into the bones.
**Still-pools:** pale ground patches around breached barrows. A levy killed inside one re-forms after a delay unless it's Kindled or warded. The Choir-warden can skip the delay.

A patch of ground where rain hangs motionless in mid-air like glass beads. The mud is bleached Old Bone, with loose bones arranged in rank order. Nothing inside it casts a shadow.

## The Sleet *(squad mages, Charter, environment)*

The Reach of cold water and forgetting, and the March's most common one.
**Hooks:** Charter-lamp **fog** shortens detection and the player's lock-on range. An ally mage's **Sleetwall** (scripted) stops arrows, countering Back-file archers. An enemy mage casts the same wall to protect its archers.

A straight wall of sideways sleet, edges glowing faint Overcast Blue. Frost feathers creep over nearby Blackened Iron and Wet Slate. Arrows caught in it hang frozen, then drop.

## The Understair *(environment only; unexplained)*

A Reach nobody holds, tied to the Longsteps. Its cost is unknown.
**Hook (post-MVP):** triggered terraces that shift, rise or seal, as puzzle spaces. Never player-cast.

Blocks of mirror-flat Peat Black stone sliding apart along hairline Tarnished Gold seams. No dust falls and no rain beads on them. The scale is wrong for human hands.

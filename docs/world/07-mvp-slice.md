# 07 — MVP Vertical Slice

Exactly one location, one quest, one enemy model (with two variants) and one NPC, all of which already exist in the build. This matches `docs/audit.md` §5 Phase B. Anything not listed is out of scope.

| Element | Setting | Existing asset |
|---|---|---|
| Location | **Oskett and the Eastern Road cut** | `scenes/world/Level1.tscn` |
| Quest | **Clear the Eastern Road** | `data/quests/clear_eastern_road.json` |
| Enemy | **Barrow-levy**, one model: Front-file (melee, ×5) and Back-file (archer, ×2) | `archer_enemy.glb` via `BaseEnemy.tscn` / `ArcherEnemy.tscn` |
| NPC | **Keeper Idrenna** | `VillageElder` node (`NPC.tscn`), `data/dialogues/village_elder*.json` |

Level 1 contains no other enemy types: all 7 enemies are the skeleton model.

**Premise:** the player's squad has just been posted to Fort Dremmel, and the player is sent alone to Oskett on road patrol. Idrenna, who won't say "Keeper" in front of a soldier, asks for the dead on the road to be put down; she can't do it herself without breaking the Rite Ban.

## Quest stages (implemented)

1. `find_monsters`: "Walk the Eastern Road cut." Advanced by the existing `QuestAdvanceArea`.
2. `defeat_monsters`: "Put down the dead on the road." All 7 levies; advanced by `Level1.gd`.
3. `return_to_keeper`: "Report to Keeper Idrenna in Oskett." Talking to her completes the quest (`NPC.return_stage_id`).

**Reward:** the Elder's Shield (`shield_wooden`) and 50 XP. It was her son's imperial-issue shield; he took the Line's pay and went south with the Draw. The exit door opens only once the quest is complete.

**Dialogue:** implemented in `data/dialogues/village_elder.json` and `village_elder_complete.json`. Idrenna greets a posted soldier, not a traveler.

## Slice art (pilot assets)

- **Levy Blade** and **Levy Bow**: separate props held in hand sockets.
- **Back-file wrap**: a Signal Red albedo variant for the archer.

Briefs for all three are in `docs/art-bible.md`.

## Out of scope

- Kindle and its cooldown, ward-stones, Still-pools, and all Reaches.
- The Charter, Deserters and Peat-drowned.
- Level 2, Fort Dremmel, the Longsteps.

**Slice visual target:** Oskett at wet dusk, Rain Stone longhouses under dripping turf with Torch Amber doorways and a lone soldier in Garrison Teal on the path. Beyond, the Eastern Road runs straight between split barrows, its Wet Slate shining with rain. Hunched Old Bone figures with short Blackened Iron blades rise out of the mounds, and red-ragged archers stand behind them.

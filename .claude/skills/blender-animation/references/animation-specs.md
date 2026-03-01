# Animation Pose Specifications

Detailed keyframe-by-keyframe descriptions for each standard animation. All rotations are in degrees. Axis conventions may vary per rig — adapt based on bone rest orientation.

**Notation:** `bone_name: (X, Y, Z)` means Euler rotation in degrees. `+` means the axis the user sees. Positive X = pitch forward, positive Z = spread outward (for arms).

## Base: Arms-Lowered Rest Pose

Apply at frame 1 of every animation as the starting point.

```
upper_arm.L: (0, 0, -55)    # left arm down at side
upper_arm.R: (0, 0, 55)     # right arm down at side
forearm.L:   (0, 0, 0)      # straight
forearm.R:   (0, 0, 0)      # straight
```

Note: The Z rotation direction depends on the rig. Some rigs use +55 for left and -55 for right. **Check the bone's local axes** — the goal is arms hanging naturally at the sides.

---

## Idle (60 frames, looping)

Subtle breathing and gentle weight shift. Should feel alive but calm.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| 1 | (arms-lowered base) | | Starting pose |
| 1 | spine | (0, 0, 0) | Neutral |
| 1 | chest | (0, 0, 0) | Neutral |
| 1 | head | (0, 0, 0) | Looking forward |
| 15 | spine | (3, 0, 0) | Slight forward lean (inhale) |
| 15 | chest | (2, 0, 0) | Chest rises |
| 15 | head | (-2, 0, 0) | Slight look up |
| 15 | upper_arm.L | (3, 0, -55) | Arms drift slightly |
| 15 | upper_arm.R | (3, 0, 55) | |
| 30 | spine | (0, 0, 1) | Slight weight shift right |
| 30 | chest | (0, 0, 0) | Returns |
| 30 | head | (0, 2, 0) | Slight head turn |
| 45 | spine | (-2, 0, 0) | Slight backward lean (exhale) |
| 45 | chest | (-1, 0, 0) | Chest lowers |
| 45 | head | (1, 0, 0) | Slight look down |
| 60 | (same as frame 1) | | Loop back to start |

**Key principle:** Copy frame 1 poses exactly at frame 60 for seamless looping.

---

## Run (24 frames, looping)

Full stride cycle — two steps in 24 frames (12 frames per step).

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| **Frame 1 — Left foot forward, right foot back (contact)** |
| 1 | spine | (8, 0, 0) | Forward lean for running |
| 1 | chest | (-3, 0, 0) | Counter-rotate to keep head stable |
| 1 | thigh.L | (-35, 0, 0) | Left leg forward |
| 1 | shin.L | (20, 0, 0) | Slight knee bend |
| 1 | thigh.R | (25, 0, 0) | Right leg back |
| 1 | shin.R | (40, 0, 0) | Trailing leg knee bend |
| 1 | upper_arm.L | (25, 0, -55) | Left arm back (opposite to left leg) |
| 1 | upper_arm.R | (-25, 0, 55) | Right arm forward |
| 1 | forearm.L | (0, 0, -20) | Slight bend |
| 1 | forearm.R | (0, 0, 20) | |
| **Frame 6 — Left leg passing (midstance)** |
| 6 | hips | loc (0, 0, 0.03) | Slight upward bounce |
| 6 | thigh.L | (-10, 0, 0) | Passing under body |
| 6 | shin.L | (50, 0, 0) | High knee bend (foot clearing ground) |
| 6 | thigh.R | (5, 0, 0) | Nearly vertical |
| 6 | shin.R | (10, 0, 0) | Extending |
| **Frame 12 — Right foot forward, left foot back (contact)** |
| 12 | spine | (8, 0, 0) | Same lean |
| 12 | thigh.L | (25, 0, 0) | Left leg now back |
| 12 | shin.L | (40, 0, 0) | Trailing bend |
| 12 | thigh.R | (-35, 0, 0) | Right leg now forward |
| 12 | shin.R | (20, 0, 0) | |
| 12 | upper_arm.L | (-25, 0, -55) | Arms swapped |
| 12 | upper_arm.R | (25, 0, 55) | |
| 12 | forearm.L | (0, 0, -20) | |
| 12 | forearm.R | (0, 0, 20) | |
| **Frame 18 — Right leg passing** |
| 18 | hips | loc (0, 0, 0.03) | Bounce again |
| 18 | thigh.R | (-10, 0, 0) | Passing under body |
| 18 | shin.R | (50, 0, 0) | High knee bend |
| 18 | thigh.L | (5, 0, 0) | Nearly vertical |
| 18 | shin.L | (10, 0, 0) | Extending |
| **Frame 24 — Same as frame 1 for loop** |

**Key principle:** Arms always oppose legs. Copy frame 1 at frame 24 for looping.

---

## Attack (15 frames, one-shot)

Quick melee strike — windup, swing, follow-through.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| **Frame 1 — Ready stance** |
| 1 | (arms-lowered base) | | Neutral start |
| 1 | spine | (0, 0, 0) | |
| **Frame 3 — Windup** |
| 3 | spine | (-5, -20, 0) | Twist torso right, lean back |
| 3 | chest | (0, -15, 0) | Additional twist |
| 3 | upper_arm.R | (-40, -20, 55) | Right arm raised back |
| 3 | forearm.R | (0, 0, 45) | Elbow bent |
| 3 | upper_arm.L | (10, 0, -55) | Left arm braces |
| **Frame 6 — Strike (fastest part)** |
| 6 | spine | (10, 25, 0) | Twist torso left, lean forward |
| 6 | chest | (5, 20, 0) | Follow through |
| 6 | upper_arm.R | (30, 30, 55) | Right arm swings forward/down |
| 6 | forearm.R | (0, 0, 10) | Arm extends |
| 6 | upper_arm.L | (-10, 10, -55) | Left arm counterbalances |
| 6 | thigh.L | (-10, 0, 0) | Weight shifts forward |
| **Frame 10 — Follow-through** |
| 10 | spine | (5, 15, 0) | Settling |
| 10 | chest | (3, 10, 0) | |
| 10 | upper_arm.R | (15, 15, 55) | Arm decelerating |
| 10 | forearm.R | (0, 0, 15) | |
| **Frame 15 — Recovery** |
| 15 | (arms-lowered base) | | Return to neutral |
| 15 | spine | (0, 0, 0) | |

---

## Stagger (12 frames, one-shot)

Hit reaction — body snaps back, then recovers.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| **Frame 1 — Impact** |
| 1 | (arms-lowered base) | | Start neutral |
| **Frame 3 — Recoil peak** |
| 3 | spine | (-15, 0, 0) | Snap backward |
| 3 | chest | (-10, 0, 0) | Upper body bends back |
| 3 | head | (-15, 0, 0) | Head snaps back |
| 3 | upper_arm.L | (20, 0, -45) | Arms flail up/out |
| 3 | upper_arm.R | (20, 0, 45) | |
| 3 | forearm.L | (0, 0, -30) | Elbows bend outward |
| 3 | forearm.R | (0, 0, 30) | |
| 3 | thigh.L | (-5, 0, 0) | Slight stumble |
| 3 | thigh.R | (5, 0, 0) | |
| **Frame 7 — Recovery** |
| 7 | spine | (-5, 0, 0) | Starting to straighten |
| 7 | chest | (-3, 0, 0) | |
| 7 | head | (-5, 0, 0) | |
| 7 | upper_arm.L | (5, 0, -55) | Arms coming down |
| 7 | upper_arm.R | (5, 0, 55) | |
| **Frame 12 — Recovered** |
| 12 | (arms-lowered base) | | Back to neutral |
| 12 | spine | (0, 0, 0) | |
| 12 | head | (0, 0, 0) | |

---

## Death (30 frames, one-shot)

Collapse to the ground. No need to loop — character gets queue_free'd after animation.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| **Frame 1 — Standing (hit)** |
| 1 | (arms-lowered base) | | Start neutral |
| **Frame 5 — Stagger** |
| 5 | spine | (-10, 5, 0) | Lean back and to side |
| 5 | chest | (-8, 0, 0) | |
| 5 | head | (-10, 10, 0) | Head lolls |
| 5 | upper_arm.L | (15, 0, -40) | Arms go limp-ish |
| 5 | upper_arm.R | (15, 0, 40) | |
| **Frame 10 — Knees buckle** |
| 10 | hips | loc (0, 0, -0.2) | Drop height |
| 10 | spine | (-20, 8, 0) | Bending backward |
| 10 | thigh.L | (-30, 0, 0) | Knees bending |
| 10 | thigh.R | (-25, 0, 5) | |
| 10 | shin.L | (60, 0, 0) | Deep knee bend |
| 10 | shin.R | (55, 0, 0) | |
| 10 | upper_arm.L | (30, 0, -30) | Arms flailing |
| 10 | upper_arm.R | (25, 0, 30) | |
| **Frame 18 — Falling** |
| 18 | hips | loc (0, 0, -0.5) | Significant drop |
| 18 | spine | (-40, 10, 5) | Nearly horizontal |
| 18 | chest | (-20, 0, 0) | |
| 18 | head | (-20, 15, 0) | Head rolling |
| 18 | thigh.L | (-50, 0, 0) | Legs folding |
| 18 | thigh.R | (-45, 0, 10) | |
| 18 | shin.L | (80, 0, 0) | |
| 18 | shin.R | (75, 0, 0) | |
| **Frame 25 — On the ground** |
| 25 | hips | loc (0, 0, -0.8) | Near ground level |
| 25 | spine | (-60, 10, 5) | Torso flat |
| 25 | chest | (-25, 0, 0) | |
| 25 | head | (0, 20, 10) | Head resting sideways |
| 25 | thigh.L | (-10, 0, -20) | Legs splayed on ground |
| 25 | thigh.R | (-10, 0, 20) | |
| 25 | shin.L | (15, 0, 0) | Mostly straight on ground |
| 25 | shin.R | (20, 0, 0) | |
| 25 | upper_arm.L | (10, 20, -70) | Arms splayed |
| 25 | upper_arm.R | (-10, -10, 70) | |
| 25 | forearm.L | (0, 0, -20) | |
| 25 | forearm.R | (0, 0, 15) | |
| **Frame 30 — Final rest (hold)** |
| 30 | (same as frame 25) | | Hold the final pose |

---

## Dodge Roll (20 frames, one-shot) — Player Only

Quick forward roll with i-frames.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| 1 | (arms-lowered base) | | Start |
| 3 | spine | (20, 0, 0) | Crouch forward |
| 3 | thigh.L | (-40, 0, 0) | Deep squat |
| 3 | thigh.R | (-40, 0, 0) | |
| 3 | shin.L | (70, 0, 0) | |
| 3 | shin.R | (70, 0, 0) | |
| 7 | spine | (70, 0, 0) | Tucked roll |
| 7 | chest | (30, 0, 0) | |
| 7 | head | (30, 0, 0) | Chin tucked |
| 7 | upper_arm.L | (40, 0, -55) | Arms wrapped in |
| 7 | upper_arm.R | (40, 0, 55) | |
| 7 | hips | loc (0, 0, -0.3) | Lowered |
| 13 | spine | (40, 0, 0) | Coming out of roll |
| 13 | chest | (15, 0, 0) | |
| 13 | hips | loc (0, 0, -0.2) | Rising |
| 17 | spine | (10, 0, 0) | Nearly upright |
| 20 | (arms-lowered base) | | Recovery to neutral |

---

## Attack Heavy (20 frames, one-shot) — Player Only

Slower, more powerful overhead strike.

| Frame | Bone | Rotation | Notes |
|-------|------|----------|-------|
| 1 | (arms-lowered base) | | Start |
| 4 | spine | (-10, 0, 0) | Lean back for windup |
| 4 | chest | (-5, 0, 0) | |
| 4 | upper_arm.R | (-70, -10, 55) | Arm raised high |
| 4 | forearm.R | (0, 0, 60) | Elbow bent overhead |
| 4 | upper_arm.L | (-20, 10, -55) | Left arm counterbalances |
| 8 | spine | (20, 0, 0) | Slam forward |
| 8 | chest | (15, 0, 0) | |
| 8 | upper_arm.R | (50, 0, 55) | Arm swings down hard |
| 8 | forearm.R | (0, 0, 5) | Arm extends |
| 8 | thigh.L | (-15, 0, 0) | Lunge forward |
| 13 | spine | (10, 0, 0) | Follow-through |
| 13 | upper_arm.R | (30, 0, 55) | |
| 20 | (arms-lowered base) | | Recovery |

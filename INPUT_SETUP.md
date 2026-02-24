# Input Map Setup

Add the following actions in **Project > Project Settings > Input Map**.

Each action should have at least one keyboard binding and, where noted, a
recommended controller (joypad) binding as well.

---

## Movement

| Action          | Keyboard        | Controller (suggested)  |
|-----------------|-----------------|-------------------------|
| `move_forward`  | W               | Left Stick Up           |
| `move_backward` | S               | Left Stick Down         |
| `move_left`     | A               | Left Stick Left         |
| `move_right`    | D               | Left Stick Right        |

## Camera

| Action          | Keyboard        | Controller (suggested)  |
|-----------------|-----------------|-------------------------|
| `camera_left`   | Arrow Left / Q  | Right Stick Left        |
| `camera_right`  | Arrow Right / E | Right Stick Right       |
| `camera_up`     | Arrow Up        | Right Stick Up          |
| `camera_down`   | Arrow Down      | Right Stick Down        |

## Combat

| Action          | Keyboard        | Controller (suggested)  |
|-----------------|-----------------|-------------------------|
| `attack_light`  | J / Left Click  | Joypad Button 0 (X/A)  |
| `attack_heavy`  | K               | Joypad Button 2 (X/Square)  |
| `dodge`         | Space / Shift   | Joypad Button 1 (B/Circle) |

## Interaction & UI

| Action           | Keyboard        | Controller (suggested)  |
|------------------|-----------------|-------------------------|
| `interact`       | F / E           | Joypad Button 3 (Y/Triangle) |
| `lock_on`        | Tab / Middle Click | Joypad Button 8 (R3) |
| `open_inventory`  | I               | Joypad Button 4 (Back/Select) |
| `open_quest_log`  | L               | Joypad Button 9 (L1/LB) |
| `pause`           | Escape          | Joypad Button 6 (Start/Options) |

---

## Notes

- Use **Godot's built-in axis actions** for analogue stick input if you want
  analogue movement. The actions above use digital (pressed/released) bindings,
  which is fine for keyboard play. For full analogue controller support you may
  want to read `Input.get_vector("move_left", "move_right", "move_forward",
  "move_backward")` directly in Player.gd.
- `lock_on` cycles through nearby enemies — a single press/release is enough;
  no need to map it as an axis.
- All action names above must match **exactly** (case-sensitive) to the
  `Input.is_action_*` calls in the scripts.

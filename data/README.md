# data

Gameplay values as data files: mech stats, point costs, weapons, perks, rulesets and balance. Balance changes are edits to these files, not to code.

## Animation

Mechs are animated in code from their data file, with no animation assets.

- `animation` (per mech): tuning numbers. Ground mechs need `stride_length` and `bob_m`; flying mechs need `flap_hz`, `flap_hz_climb`, `hover_bob_m`, `bank_deg` and `pitch_deg`. Optional: `idle_bob_m`, `stalk_drop_m` (body sinks low while walking), `sway_yaw_deg`, `sway_roll_deg`, `sway_pitch_deg` (prowling spine and shoulder motion), `limp_roll_deg`, `collapse_m`, `death_pitch_deg`, `death_roll_deg`.
- `anim` (per part): `pivot` is the point the part rotates around. `walk` (ground) or `flap` (flying) gives `axis`, `deg`, and optionally `phase`, `offset_deg` and `droop_deg`.
- Parts with a `parent` move with it, so joints follow their limbs, and hitboxes move with the visible parts.
- `aim` (per part, `"yaw"` or `"pitch"`): the part turns or tilts with where the pilot aims. The lion's gun mast (yaw) and gimbal bar (pitch) use it. A part that hangs from a destroyed part is knocked out too, so losing the mast takes both guns offline.

## Cockpit

`cockpit_frame` (per mech) shapes the frame the pilot sees in cockpit view: `window` (half width and half height of the opening), `distance` (at least 0.4), `pillar_tilt_deg` and `console_height`. The frame is built from flat-coloured boxes in the mech's palette and is hidden in third-person view.

## Segmented limbs

A limb can be a chain of parts, each hanging from the one before (`parent`), with its own `pivot` and `walk` motion. The lion's legs are chains: shoulder blade, upper arm, elbow, forearm, paw (front) and thigh, knee, shin, foot (rear).

- `damage_to` (per part): the part is only a visible piece of another part. It has no health or HUD row, and hits on it count against the named part.
- `rectify` (inside a `walk` or `flap` motion): only the positive half of the wave is used, so a joint folds and straightens but never bends backwards. Used to lift the foot during the swing.

## Jumping

Ground mechs set `base.jump_speed` (upward speed in m/s, 0 disables jumping) and optionally `base.jump_cooldown` (seconds). The jump height follows from gravity, and a damaged mech jumps lower because leg damage scales the jump like it scales speed. A ruleset can switch jumping off with `"jumping": false`. The optional animation key `land_dip_m` sets how far the body dips on landing.

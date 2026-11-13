# data

Gameplay values as data files: mech stats, point costs, weapons, perks, rulesets and balance. Balance changes are edits to these files, not to code.

## Animation

Mechs are animated in code from their data file, with no animation assets.

- `animation` (per mech): tuning numbers. Ground mechs need `stride_length` and `bob_m`; flying mechs need `flap_hz`, `flap_hz_climb`, `hover_bob_m`, `bank_deg` and `pitch_deg`. Optional: `idle_bob_m`, `stalk_drop_m` (body sinks low while walking), `sway_yaw_deg`, `sway_roll_deg`, `sway_pitch_deg` (prowling spine and shoulder motion), `limp_roll_deg`, `collapse_m`, `death_pitch_deg`, `death_roll_deg`.
- `anim` (per part): `pivot` is the point the part rotates around. `walk` (ground) or `flap` (flying) gives `axis`, `deg`, and optionally `phase`, `offset_deg` and `droop_deg`.
- Parts with a `parent` move with it, so joints follow their limbs, and hitboxes move with the visible parts.

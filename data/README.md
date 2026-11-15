# data

Gameplay values as data files: mech stats, point costs, weapons, perks, rulesets and balance. Balance changes are edits to these files, not to code.

## Animation

Mechs are animated in code from their data file, with no animation assets.

- `animation` (per mech): tuning numbers. Ground mechs need `stride_length` and `bob_m`; flying mechs need `flap_hz`, `flap_hz_climb`, `hover_bob_m`, `bank_deg` and `pitch_deg`. Optional: `idle_bob_m`, `stalk_drop_m` (body sinks low while walking), `sway_yaw_deg`, `sway_roll_deg`, `sway_pitch_deg` (prowling spine and shoulder motion), `limp_roll_deg`, `collapse_m`, `death_pitch_deg`, `death_roll_deg`.
- `anim` (per part): `pivot` is the point the part rotates around. `walk` (ground) or `flap` (flying) gives `axis`, `deg`, and optionally `phase`, `offset_deg` and `droop_deg`.
- Parts with a `parent` move with it, so joints follow their limbs, and hitboxes move with the visible parts.
- `aim` (per part, `"yaw"` or `"pitch"`): the part turns or tilts with where the pilot aims. The lion's gun mast (yaw) and gimbal bar (pitch) use it. A part that hangs from a destroyed part is knocked out too, so losing the mast takes both guns offline.

## Aim twist

`base.twist_limit_deg` is how far the pilot can aim left or right of the way the legs face. At 180 or more the aim spins freely through a full circle. The lion uses 360, so its gimbal-mounted guns can turn all the way round.

## Cockpit

`visual` (per part, optional) draws the part as a set of shaped pieces instead of its plain box, so a mech can look like a build of metal strips and plates. Each piece has `size` (plates use `points` and `thickness` instead), `pos` (offset from the part's centre), optional `rot_deg`, `tone` (`primary`, `accent`, `dark`, or `metal` for silver bolts, nuts and joints) and `shape` (`box`, `sphere` of diameter `size[0]`, `cylinder` or `hex` of diameter `size[0]` and length `size[1]`, both along the up axis, or `plate`: an outline `points` ([x, y] pairs in the piece's own XY plane) with a `thickness` along Z and an optional corner `round` radius, like a stamped metal plate). The part's hitbox still uses its own `size`, so changing the look never changes gameplay.

`cockpit_frame` (per mech) shapes the frame the pilot sees in cockpit view: `window` (half width and half height of the opening), `distance` (at least 0.4), `pillar_tilt_deg` and `console_height`. The frame is built from flat-coloured boxes in the mech's palette and is hidden in third-person view.

## Segmented limbs

A limb can be a chain of parts, each hanging from the one before (`parent`), with its own `pivot` and `walk` motion. The lion's, raptor's and hawk's limbs are chains: shoulder blade, upper arm, elbow, forearm, paw (front) and thigh, knee, shin, foot (rear).

- `damage_to` (per part): the part is only a visible piece of another part. It has no health or HUD row, and hits on it count against the named part.
- `rectify` (inside a `walk` or `flap` motion): only the positive half of the wave is used, so a joint folds and straightens but never bends backwards. Used to lift the foot during the swing.

## Jumping

Ground mechs set `base.jump_speed` (upward speed in m/s, 0 disables jumping) and optionally `base.jump_cooldown` (seconds). The jump height follows from gravity, and a damaged mech jumps lower because leg damage scales the jump like it scales speed. A ruleset can switch jumping off with `"jumping": false`. The optional animation key `land_dip_m` sets how far the body dips on landing.
- `stabilize` (per part, a number): the part turns against the body's pitch by that fraction, so what sits on it stays level. The hawk's neck uses it to keep the head steady while the body pitches.

The velociraptor follows a theropod skeleton: thigh, knee, shin, ankle bone and foot with a raised sickle claw, short folded arms with clawed hands, and a stiff three-segment tail. The hawk follows a bird skeleton: a three-joint wing (upper wing, forearm, primaries) whose flap travels outwards as a wave, a two-joint neck that keeps the head level, a hooked beak, a keel and a fanned tail.

## Head look

`look` (per part, `turn_deg`, optional `share` and `speed`) makes a part turn and tilt towards where the pilot is aiming, up to `turn_deg` left or right. Past that limit the aim carries on and the part stays put. `share` splits a turn between linked parts: the hawk's neck and head each take part of it, which adds up to one full turn. The lion's head turns up to 110 degrees, the raptor's up to 100 and the hawk's neck and head together up to 120. The cockpit view and the lion's gimbal keep following the aim beyond a head's limit.

The hawk carries both of its guns on a gimbal under its belly (a mast with a crossbar, like the lion's, but hanging down). It turns and tilts with the aim, so the guns can fire downwards. Losing the gimbal takes both guns offline, and the wings no longer carry weapons.

## Points (hidden, fixed)

Every mech has a fixed point budget the player cannot change. `points` (per mech) splits `budget` (in `points.json`, 30) across `speed`, `armor` and `carry`, each at least 1. `points.json` gives each stat as `base + per_point * points`:

- `speed` covers mobility too: top speed, turn rate, jump speed and cooldown (walkers) or climb speed (flyers).
- `armor` divides incoming damage.
- `carry` sets carry capacity. Weapons have a `weight`, and ranged ones an `ammo_weight` per round. A mech whose capacity cannot hold every full ammo load carries less ammo, cut back evenly. The weapons themselves must always fit.

Do not put `speed`, `turn_rate`, `armor`, `jump_speed`, `jump_cooldown` or `climb_speed` in `base`; they come from points. Bump `balance.json` when points or conversions change.

## Loadout (four slots)

A pilot picks four things in the main menu: `primary` and `secondary` weapons (any weapon whose `slot` matches), one `equipment` item (`data/equipment/`) and one `perk` (`data/perks/`). Each has a `weight`; weapons add `weight` plus `ammo_weight` per round. Weapons and gear must fit the mech's carry capacity, otherwise the server uses the default loadout (autocannon, rocket pod, no equipment, no perk). Melee weapons stay fixed per mech.

Equipment and perks can have `mods`: `armor_mult`, `speed_mult` (top speed, jump, climb), `turn_mult`, `damage_mult` and `ammo_mult`. Every folder needs a `none` entry. The server checks every loadout a client sends. Command-line options: `--primary=ID --secondary=ID --equipment=ID --perk=ID`.

## Sprint

Hold Shift (gamepad: left stick click) while moving forward to move faster. `points.json` `sprint.speed_mult` (1.5) sets the boost, which applies to ground speed only, not flight climb. A ruleset can switch it off with `"sprinting": false`. The server applies it, so it cannot be faked. Hardcore and Arcade keep it on.

## Weapon models

A ranged weapon can have a `visual` (the same pieces as a part, drawn with `-Z` as forward) and a `muzzle` distance. The gun is drawn on the part its mount sits on, so choosing a different weapon in the loadout changes what the mech carries. Colours come from the mech's palette (`metal` stays silver). A mount can set `gun_scale` and `gun_offset` (the velociraptor's small hands use 0.55). Shots start at the muzzle. The lion's and hawk's gun pods are now plain mounting brackets.

## Projectiles

A ranged weapon with a `projectile` block fires a real shot that flies, instead of hitting instantly: `model` (`bullet`, `pellet`, `rocket` or `grenade`), `speed` (m/s), optional `gravity` (a grenade arcs under it), optional `min_arc_deg` (the flattest lob; a close target is lobbed slower so the arc stays visible), `splash_radius` and `splash_damage` (a blast that hurts other mechs near where it lands, weaker with distance). Shots start at the gun's muzzle and head for the point under the crosshair, which for a grenade means a lobbed arc that lands there. The server flies and judges every shot; clients draw a copy and show the burst when told. Weapons without `projectile` are still instant hits. Direct hits do the weapon's `damage` to the part hit.

# data

Gameplay values as data files: mech stats, point costs, weapons, perks, rulesets and balance. Balance changes are edits to these files, not to code.

## Animation

Mechs are animated in code from their data file, with no animation assets.

- `animation` (per mech): tuning numbers. Ground mechs need `stride_length` and `bob_m`; flying mechs need `flap_hz`, `flap_hz_climb`, `hover_bob_m`, `bank_deg` and `pitch_deg`. Optional: `idle_bob_m`, `stalk_drop_m` (body sinks low while walking), `sway_yaw_deg`, `sway_roll_deg`, `sway_pitch_deg` (prowling spine and shoulder motion), `limp_roll_deg`, `collapse_m`, `death_pitch_deg`, `death_roll_deg`. Ground mechs can also stand up straight when they stop: `stand_pivot` (the hips, [x, y, z]) and `stand_pitch_deg` tip every part except the legs nose-up about that point over about a second, and back down when the mech moves. A part's `stabilize` also cancels some of that tilt, so a head or tail can stay level.
- `anim` (per part): `pivot` is the point the part rotates around. `walk` (ground) or `flap` (flying) gives `axis`, `deg`, and optionally `phase`, `offset_deg` and `droop_deg`.
- Parts with a `parent` move with it, so joints follow their limbs, and hitboxes move with the visible parts.
- `aim` (per part, `"yaw"` or `"pitch"`): the part turns or tilts with where the pilot aims. The lion's gun mast (yaw) and gimbal bar (pitch) use it. A part that hangs from a destroyed part is knocked out too, so losing the mast takes both guns offline.

## Aim twist

`base.twist_limit_deg` is how far the pilot can aim left or right of the way the legs face. At 180 or more the aim spins freely through a full circle. The lion uses 360, so its gimbal-mounted guns can turn all the way round.

## Cockpit

`visual` (per part, optional) draws the part as a set of shaped pieces instead of its plain box, so a mech can look like a build of metal strips and plates. Each piece has `size` (plates use `points` and `thickness` instead), `pos` (offset from the part's centre), optional `rot_deg`, `tone` (`primary`, `accent`, `dark`, or `metal` for silver bolts, nuts and joints, `black` for dark steel and `eye` for a glowing orange) and `shape` (`box`, `sphere` of diameter `size[0]`, `cylinder` or `hex` of diameter `size[0]` and length `size[1]`, both along the up axis, or `plate`: an outline `points` ([x, y] pairs in the piece's own XY plane) with a `thickness` along Z and an optional corner `round` radius, like a stamped metal plate). A plate can also have `holes`: a list of `[x, y, radius]` circles or lists of `[x, y]` points cut through it, like the perforations in a construction-set strip. The part's hitbox still uses its own `size`, so changing the look never changes gameplay.

`cockpit_frame` (per mech) shapes the cockpit the pilot sees in cockpit view, laid out like a box of glass held by grey structure: a header beam, two slanted pillars and roof struts to the screen corners, with a sloping console at the bottom where the HUD readouts sit. All positions are fractions of the screen from its centre (1 is the edge): `top` is [half width, height] of the windscreen's top corners, `bottom` is [half width, height below centre (negative)] of its bottom corners (so the console's far edge), `distance` is how far ahead the windscreen sits (at least 0.4), and `beam` is the structure thickness. It is built from flat-coloured shapes in the mech's palette and is hidden in third-person view.

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

A pilot picks four things in the main menu: `primary` and `secondary` weapons (either slot takes any ranged weapon, so two machine guns or two sniper cannons are fine; a weapon's own `slot` is only where it sits by default, and melee weapons are never offered), one `equipment` item (`data/equipment/`) and one `perk` (`data/perks/`). Each has a `weight`; weapons add `weight` plus `ammo_weight` per round. Weapons and gear must fit the mech's carry capacity, otherwise the server uses the default loadout (autocannon, rocket pod, no equipment, no perk). Melee weapons stay fixed per mech.

Equipment and perks can have `mods`: `armor_mult`, `speed_mult` (top speed, jump, climb), `turn_mult`, `damage_mult`, `ammo_mult` and `noise_mult` (how loud footsteps are and how far they carry; below 1 is quieter, as in the Silent Stride perk). Every folder needs a `none` entry. The server checks every loadout a client sends. Command-line options: `--primary=ID --secondary=ID --equipment=ID --perk=ID`.

## Sprint

Hold Shift (gamepad: left stick click) while moving forward to move faster. `points.json` `sprint.speed_mult` (1.5) sets the boost, which applies to ground speed only, not flight climb. A ruleset can switch it off with `"sprinting": false`. The server applies it, so it cannot be faked. Hardcore and Arcade keep it on.

## Flight: flying like a plane

Flying mechs (the hawk) fly like a plane, using the `flight` block in `points.json`. They never hover: a flyer is always moving along its nose. Shift and Ctrl set the throttle (Ctrl pulled back it settles at `idle_fraction` of top speed, pushed at the top, hands off at `cruise_fraction`); A and D bank and turn (the bank is what turns the nose, up to `max_roll_deg`); W pushes the nose down and S pulls it up; Q and E nudge the rudder. The top speed is the mech's speed stat times `max_speed_mult`. Gravity trades speed for height: climbing bleeds speed and diving builds it (`gravity_coupling`). Below `stall_fraction` of top speed the wings stall: the controls go soft, the nose drops (`stall_nose_drop`) and the mech falls until it has built speed again. Wing damage gives less lift, so a damaged flyer stalls at a higher speed. Hitting a cliff slows it, and the ground skids it to a stop (a mech left on the ground can take off again). The whole body pitches and banks, so the cockpit view tilts with it.

Space is boost for a flyer instead of Shift being a sprint: `boost_speed_mult` (1.6) faster for `boost_time` seconds (10) per tank. When the tank is empty the boost is locked until it has refilled, which takes `boost_cooldown` seconds (8); letting go early refills it at the same rate. The HUD shows airspeed, altitude, a STALL warning and the boost tank on the weapons readout. The server works it all out. A ruleset's `"sprinting": false` switches boost off.

## Air bomb

The hawk's belly rack carries an air bomb (`weapons/air_bomb.json`, weapon `slot` `bomb`, fired with B or the d-pad down). A weapon on the `bomb` slot has its own button and is not offered in the loadout screen. Its `projectile` has `"drop": true`: it is not aimed, it leaves with the mech's own velocity (plus `speed` straight down) and falls on an arc under `gravity`, bursting where it lands (`splash_radius`, `splash_damage`). An orange marker on the HUD shows where a bomb dropped now would land.

## Ion cannon

`weapons/ion_cannon.json` is a two-slot weapon: choosing it in either weapon slot fills both (the loadout menu does this for you), it sits on the primary mount, and the secondary mount is left empty. Its weight (45) is counted once. It is an instant beam (`"beam": {"width", "fade"}` instead of a `projectile`): the beam is a ray from the aim point out to `range`, hits the first thing on its path the moment it fires, then stays where it is and fades out over `fade` seconds (3). Hold either fire button for `charge.max_time` (3 s) and let go to fire; `"full_only": true` means letting go early cancels the shot and costs no ammo. A glowing ball grows at the muzzle while it charges and the HUD counts the seconds. `"kill": true` makes a hit destroy the whole mech whatever part it strikes (friendly fire rules still apply). Six shots (`ammo`), 4 s between them.

## Sniper rifle (raptor only equipment)

The sniper is raptor-only **equipment**, not a primary or secondary weapon, so the raptor keeps both its hand weapons. `equipment/sniper_rifle.json` has `"weapon": "sniper_cannon"` (the equipment adds that weapon to the mech on its own mount, and the weapon's weight counts instead of the equipment's) and `"mechs"` (the only mechs that may take it; the loadout menu and the server enforce it, and any item or weapon can use `mechs`). `weapons/sniper_cannon.json` has slot `equipment`, a `mount` that moves it onto another part with its own `gun_offset`, `gun_rot_deg` and `gun_scale` (the raptor's sits on its tail tip pointing backwards) and a `scope` (`min_zoom`, `max_zoom`, `start_zoom`). F ("use equipment") switches the scope on and off. While scoped the mech stops and turns tail first to the aim (the aim stays put in the world while the body swings), the view goes through a round scope, the mouse wheel zooms between `min_zoom` and `max_zoom` (mouse aim slows with the zoom) and the hand weapons are put away. Press a fire button to take aim and let go to fire once the tail points at the aim. Moving or turning the legs, or F again, leaves the scope, and the mech turns back round until the aim is inside its normal twist limit. The tail is a target: lose it and the sniper goes offline. (Melee moved to G to free F.)

## Sounds
Clips are `assets/audio/<name>.ogg` and play on the Effects bus. A weapon names them with `"sound"` (the shot, also sent to network clients), `"sound_charge"` (loops while a charged weapon is held) and `"sound_aim"` (when the sniper scope comes up); `"sound_burst"` (where a projectile explodes) and `"sound_db"` trims the volume. A mech has a top-level `"sounds"` block: `"step"` with `"steps_per_stride"` (footfalls per gait cycle; 2 for a biped) and `"step_db"`, or `"flap"` for wing beats; `"destroyed"` overrides the default `mech_destroyed` clip. `GameData.validate_all()` checks that each named clip exists. The MIDI scores for the clips made for the remaining weapons are in `assets/audio/source`. `elephant_step` is ready for a future elephant mech.

## Sound minimap
Every clip played also records a sound event (`Sfx.events`) with a position, the team that made it and how far it carries (`Sfx.NOISE`, in metres). The minimap in the top-right corner (`scripts/ui/minimap.gd`, switch in Options > Visuals) pulses a blip for each event the player can hear: blue for their team, red for others, pinned to the rim when beyond 150 m. The player's own nearby sounds are not drawn. A mech's `noise_mult` scales its footsteps' volume and range, so a quiet mech is hard to hear on the map.

## Practice matches (computer pilots)
Main menu > Test range card > 1v1 / 2v2 / 3v3 starts an offline match with the `practice_match` ruleset (best of 5 rounds on the open field, unlimited ammo): you and `size - 1` computer pilots against `size` of them, each bot flying a random mech with the default loadout. `NetSession.start_offline` fills the slots and `AiPilot` (`scripts/mech/ai_pilot.gd`) fills in each bot's `MechControls` every frame, the same inputs a player sends, so the usual match rules, scoring and sounds apply. How sharp the bots are comes from `data/ai.json` (levels easy, normal, hard: aim speed, aim wobble, how well they lead a target, firing range, reaction time and how often they dodge). Command line: `--practice=1|2|3 --bot-level=easy|normal|hard`.

## Weapon models

A ranged weapon can have a `visual` (the same pieces as a part, drawn with `-Z` as forward) and a `muzzle` distance. The gun is drawn on the part its mount sits on, so choosing a different weapon in the loadout changes what the mech carries. Colours come from the mech's palette (`metal` stays silver). A mount can set `gun_scale` and `gun_offset` (the velociraptor's small hands use 0.55). Shots start at the muzzle. The lion's and hawk's gun pods are now plain mounting brackets.

## Rulesets and maps

A ruleset (`data/rulesets/`) switches systems on and off. Four keys make a round match: `map` (`field` for the open field, or the id of a file in `data/maps/`), `best_of` (0 for an ordinary timed match; an odd number such as 7 for rounds, where the first team to win more than half takes the match), `swap_ends` (the teams change ends every round) and `one_life` (a destroyed mech stays out until the next round). In a round match `match_time` is the length of one round. `standard_match.json` is the best-of-7 canyon mode.

A map (`data/maps/canyon.json`) is drawn from flat outlines, in metres from the middle of the map with z running from the north end to the south end: `outer` is the canyon's outline, `islands` are the mesas inside it (everything inside `outer` and outside the islands is canyon floor), `depth` is how far the rock stands above the floor, `cell` is the size of the grid squares the map is built from, `rim` is how much high ground is added beyond the canyon, and `spawns` gives the spawn spots (at least 4) for the `north` and `south` ends and the direction each end faces. The floor and the tops are green and the rock faces tan in layers. To change the shape, edit the points; `tools/check.sh` checks the spawns are on open floor.

## Projectiles

A ranged weapon with a `projectile` block fires a real shot that flies, instead of hitting instantly: `model` (`bullet`, `pellet`, `rocket` or `grenade`), `speed` (m/s), optional `gravity` (a grenade arcs under it), optional `min_arc_deg` (the flattest lob; a close target is lobbed slower so the arc stays visible), `splash_radius` and `splash_damage` (a blast that hurts other mechs near where it lands, weaker with distance). Shots start at the gun's muzzle and head for the point under the crosshair, which for a grenade means a lobbed arc that lands there. The server flies and judges every shot; clients draw a copy and show the burst when told. Weapons without `projectile` are still instant hits. Direct hits do the weapon's `damage` to the part hit.

`knockout` (weapon, true or false) makes a hit put out the part it lands on in one shot, like the sniper cannon: any limb, joint or mount is taken out, a head hit knocks the mech out, and torso or hindquarters (too big for one shot) just take the weapon's normal `damage`. `charge` (weapon, with `max_time` and `max_height`) makes a weapon fire when the button is let go: the longer it is held, up to `max_time` seconds, the higher above the aim point the shell bursts, up to `max_height` metres. Quick tap bursts at the aim point. A charged weapon needs a projectile with a `splash_radius`.

## Between rounds

In round-based rulesets the break between rounds lasts 15 s (`NetProtocol.ROUND_OVER_TIME`). A panel lets each player pick a mech and one of their four saved loadouts, then press Ready; the break ends early once every human player is ready. The server validates the choice (`NetSession.choose`) and applies it when the next round spawns.

## Mech colours

In round (team) matches every mech is painted by team: team 1 blue, team 2 red (`LoadoutStore.TEAM_PAINT`). In other matches a mech wears its pilot's own colour, picked on the loadout screen and saved in `user://paint.txt`; the server sends the final colour to every client in the spawn info. Painting replaces the mech palette's `primary` tone and darkens `dark` to match; `accent` stays.

## Practice maps

The main menu lets you pick a map for a match against computer pilots: the open field or any map in `data/maps/` (`LaunchConfig.map`, or `--map=canyon` on the command line). On a map file the computer pilots work out routes round the raised rock with A* over the map's grid (`AiPilot.plan`), and flying pilots stay above the rim. A canyon practice round lasts at least 300 s.

## Landing

A flying mech with a `landing` block (`touch_height`, `walk_speed`, `turn_rate`) settles onto its feet when it is slower than 80% of cruise speed, within `touch_height` metres of the ground and not pulling the nose up. It then walks at `walk_speed` like a ground mech, with its wings folded; Space takes off again at cruise speed. The `animation` block's `stride_length`, `bob_m`, `sway_roll_deg` and `perch_lift_m` shape the walk. Computer pilots take off again at once.

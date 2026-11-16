# Animal Mech Combat Game

An open-source, multiplayer tournament game where players pilot animal-shaped mechs from a cockpit in the animal's head. Low-poly, flat-colour visuals. Built with Godot 4.

**Status:** very early. There is an offline test range where you can drive the three mechs and shoot dummy targets. Multiplayer is not built yet.

## Planned features

- Three starting mechs: Lion (four-legged), Velociraptor (two-legged) and Hawk (flying). Names are working names.
- Cockpit view and third-person view, plus a hardcore mode with no HUD and forced cockpit view.
- A point system for tuning each mech (speed, carry, armaments, flight time) and a loadout system with weapons, equipment and perks.
- Location-based damage: joints can be crippled and weapons or equipment can be knocked offline.
- Timed matches: 1v1, 2v2 and 3v3, with a test range and large open maps.
- Community-hosted dedicated servers, a simple server browser, listen-server and LAN play. The game stays playable without any official server.
- VR and non-VR play, with broad support for controllers, joysticks, HOTAS and flight gear.
- A map editor, either in-game (grid and blocks) or through an external 3D tool.

## Rules for this project

- No AI-generated art, audio, icons or fonts.
- Mechs use plain flat colours. Levels are low-poly blocky shapes in flat colours.
- Third-party assets must be open-licensed, with the licence understood and credit recorded in [CREDITS.md](CREDITS.md).

## Try the test range

Open the project in Godot 4.7 and press Play. Click the window to capture the mouse, and press Esc to open the pause menu (resume or return to the main menu).

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move forward / back | W / S | Left stick up / down |
| Turn the legs | A / D | Left stick left / right |
| Strafe | Q / E | Shoulder buttons |
| Sprint (hold, moving forward); ground mechs only | Shift | Left stick click |
| Flying mech: speed up / slow down / boost | Shift / Ctrl / Space | Left stick click / B / A |
| Flying mech: nose down / up, bank, rudder | W / S, A / D, Q / E | Left stick |
| Drop the hawk's bomb | B | D-pad down |
| Raptor sniper: click to scope (mech turns tail first), click and release to fire, wheel to zoom, move to leave | Fire button, mouse wheel, W A S D | Trigger |
| Aim head and weapons | Mouse | Right stick |
| Centre the aim | Z | Right stick click |
| Fire primary / secondary | Left / right mouse button | Right / left trigger |
| Melee | F | X |
| Switch cockpit / third-person | C | Y |
| Jump (Lion, Velociraptor) | Space | A |

Test range keys: `1` Lion, `2` Velociraptor, `3` Hawk. `F1` Practice, `F2` Standard, `F4` Hardcore, `F5` Arcade rules. `F3` developer overlay. `R` restart. `[` and `]` lower and raise the cockpit head bob (saved between sessions).

The rulesets show how modes switch systems on and off: Hardcore removes the HUD and crosshair, forces cockpit view, lowers durability and allows friendly fire. Arcade turns off per-part damage, joint criticals, equipment knockout and ammo limits.

All gameplay numbers (mech parts and stats, weapons, rulesets) are JSON files in `data/`. Change them, restart, and the game picks them up. `tools/check.sh` validates them.

## Multiplayer

The game opens on a menu: **Test range** (offline), **Host a match**, **Join by address** and **Scan local network**. The default ruleset when hosting is **Standard Match**: two teams (up to 4 a side) on the **Canyon** map, best of 7 rounds (first to 4). Team 1 starts at the north end and team 2 at the south, and the teams swap ends after every round. Everyone has one life per round: when your mech is destroyed you are out until the next round, and a round ends when one team has no mech left standing. When the 5 minute round clock runs out, the team with more mechs standing wins the round, then the team with more health left; a dead level round scores nothing. Pilots who join mid-round wait for the next round. The other rulesets (Standard, Practice, Hardcore, Arcade) are timed free-for-all matches on the open field (most kills when the time runs out wins). Esc opens a pause menu with a Main menu button (`F10` also leaves a match). **Loadouts** on the menu opens four named loadout boxes per mech: Use picks the one taken into matches, Edit renames it and sets primary, secondary, equipment and perk. They are saved in the game's user folder.

Run a dedicated server (no player, no window needed) on any machine with Godot:

```
godot --headless --path . -- --server --port=7777 --ruleset=standard --max-players=2 --server-name="My server"
```

Other options: `--host` (listen server, you play too), `--join=ADDRESS[:PORT]`, `--name=`, `--mech=`. Open UDP ports 7777 (game) and 7778 (LAN discovery) on the server. A client with a different balance version or network protocol is turned away with a message, so everyone in a match has the same numbers.

The server decides movement, shooting and damage. There is no client-side prediction or lag compensation yet, so expect the local mech to feel a little delayed on high latency; those come in a later milestone. The game never needs an official server: LAN and direct connect always work.

## Building the Windows game

`tools/build_windows.sh` exports `build/AnimalMechCombat.exe` (a single file, no install needed) and, if NSIS is installed, `build/AnimalMechCombat-Setup.exe` (a per-user installer with Start menu and desktop shortcuts and an uninstaller). It needs Godot's export templates for your Godot version (Editor > Manage Export Templates). The exe is not code-signed, so Windows SmartScreen may warn the first time it runs.

## Project layout

- `assets/`: art and audio (CC BY-SA 4.0)
- `data/`: gameplay values such as mech stats, weapons, rulesets and balance
- `maps/`: map files
- `scenes/`: Godot scenes
- `scripts/`: game code
- `tests/`: automated tests
- `tools/`: development scripts

Open the folder with Godot 4.7. To run the headless check: `GODOT=/path/to/godot tools/check.sh`.

## Licences

Copyright (C) 2026 jacksonhcnz and contributors.

- Code: [GNU AGPL-3.0](LICENSE).
- Art and audio in `assets/`: [CC BY-SA 4.0](assets/LICENSE).

See [CONTRIBUTING.md](CONTRIBUTING.md) before sending changes.

This project is an original work. It is not affiliated with or based on any existing game, show or toy franchise.

# Animal Mech Combat Game

An open-source, multiplayer tournament game where players pilot animal-shaped mechs from a cockpit in the animal's head. Low-poly, flat-colour visuals. Built with Godot 4.

**Status:** very early. Design is in progress and nothing is playable yet.

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

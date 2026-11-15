#!/usr/bin/env bash
# Builds the Windows game (build/AnimalMechCombat.exe) and, if NSIS is installed,
# the installer (build/AnimalMechCombat-Setup.exe).
# Needs the Godot export templates for your Godot version (Editor > Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build
"$GODOT" --headless --path . --export-release "Windows Desktop" build/AnimalMechCombat.exe
if command -v makensis >/dev/null 2>&1; then
  (cd tools && makensis -V2 installer.nsi)
else
  echo "NSIS (makensis) not found: built the game exe only."
fi

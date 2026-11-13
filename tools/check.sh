#!/usr/bin/env bash
# Loads the project headlessly and parses every script.
# Fails if Godot reports any error.
# Usage: GODOT=/path/to/godot tools/check.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
log="$(mktemp)"

"$GODOT" --headless --path . --import 2>&1 | tee "$log"

while IFS= read -r script; do
	"$GODOT" --headless --path . --check-only --script "$script" 2>&1 | tee -a "$log"
done < <(find . -name '*.gd' -not -path './.godot/*' | sort)

if grep -E "ERROR|Parse Error" "$log" >/dev/null; then
	echo "Godot reported errors." >&2
	exit 1
fi
echo "Project loaded with no errors."

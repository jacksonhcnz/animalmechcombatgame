#!/usr/bin/env bash
# Loads the project headlessly, parses every script, then runs the tests.
# Fails if Godot reports any error or any test fails.
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

for test_script in tests/run_tests.gd tests/smoke_test.gd; do
	echo "Running $test_script"
	"$GODOT" --headless --path . --script "$test_script" 2>&1 | tee -a "$log"
	if [ "${PIPESTATUS[0]}" -ne 0 ]; then
		echo "$test_script failed." >&2
		exit 1
	fi
done
echo "All checks passed."

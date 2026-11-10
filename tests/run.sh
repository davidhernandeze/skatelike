#!/bin/sh
# Runs every test in tests/ headless and sums up the PASS / FAIL lines (see README.md).
# Usage: tests/run.sh [test name ...]   GODOT=/path/to/godot to use another binary.
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
TESTS=${*:-mirror backward_course trick_names replay game_scene spots practice}
export SKATELIKE_API_URL=http://127.0.0.1:9  # No scoreboard calls.
# The player's saves (playing in the editor) are put aside and back afterwards: runs write
# their own. Spot progress has a test file of its own (SKATELIKE_SPOTS_SAVE).
export SKATELIKE_SPOTS_SAVE=user://test_spots.cfg
SAVES="$HOME/Library/Application Support/Godot/app_userdata/skatelike"
KEEP=$(mktemp -d)
for f in progress profile scoreboard spots; do
	[ -f "$SAVES/$f.cfg" ] && cp "$SAVES/$f.cfg" "$KEEP/"
done
pass=0; fail=0
for t in $TESTS; do
	echo "== $t"
	out=$("$GODOT" --headless --path . --fixed-fps 60 -s "tests/$t.gd" --quit-after 20000 2>&1)
	echo "$out" | grep -E "^(PASS|FAIL) |SCRIPT ERROR|Parse Error"
	p=$(echo "$out" | grep -c "^PASS ")
	f=$(echo "$out" | grep -c "^FAIL \|SCRIPT ERROR\|Parse Error")
	[ "$p" -eq 0 ] && f=$((f + 1))  # A test that printed nothing failed to run.
	pass=$((pass + p)); fail=$((fail + f))
done
# The runs' saves go, the player's come back.
for f in progress profile scoreboard spots test_spots; do
	rm -f "$SAVES/$f.cfg"
	[ -f "$KEEP/$f.cfg" ] && cp "$KEEP/$f.cfg" "$SAVES/"
done
rm -rf "$KEEP"
echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Every suite, in parallel, in brief mode: one line per suite, and the lines
# that explain a failure. Run from the project folder:
#
#   bash dev/run_tests.sh            everything (about 5 minutes; the level is the long one)
#   bash dev/run_tests.sh --quick    everything but the level and the long chaos run
#
# Exit status is 0 only if every suite passed. Full output of each suite is kept
# in the folder printed at the end, for when a failure needs reading in detail.

cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-../_tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
OUT="${TMPDIR:-/tmp}/mobile_tavern_tests_$$"
mkdir -p "$OUT"
QUICK=0
[ "$1" = "--quick" ] && QUICK=1

"$GODOT" --headless --path . --import > "$OUT/import.txt" 2>&1
if grep -q "SCRIPT ERROR\|Parse Error" "$OUT/import.txt"; then
	echo "IMPORT FAIL:"; grep -m 5 "SCRIPT ERROR\|Parse Error" "$OUT/import.txt"; exit 1
fi

run() {  # name, scene, extra args...
	local name="$1" scene="$2"; shift 2
	( start=$(date +%s)
	  timeout 1500 "$GODOT" --headless --path . "res://dev/$scene.tscn" -- --brief "$@" > "$OUT/$name.txt" 2>&1
	  echo "EXIT $? $(( $(date +%s) - start ))" >> "$OUT/$name.txt" ) &
}

run regressions regressions
run day day_regressions
run visit visit_regressions
run polish polish_regressions
run layout hud_layout_smoke
run atmosphere atmosphere_smoke
run adventurers adventurer_mesh_smoke
run characters character_smoke
run faces face_smoke
run wardrobe wardrobe_smoke
run uniforms staff_uniform_smoke
run tutorial tutorial_smoke
run tutahead tutorial_ahead_check
run uifixes ui_fixes_check
run soak tutorial_smoke --days 6
run house house_smoke
run stores stores_smoke
run farm farm_polish_smoke
run saves save_resume_smoke
run saveedge save_edge_check
run saveui save_ui_smoke
run smoke smoke_test
run chaos81 chaos_test seed=81 seconds=1800
run chaos90 chaos_test seed=90 seconds=1800 level=wayfarers_rest
if [ $QUICK -eq 0 ]; then
	run chaos33 chaos_test seed=33 seconds=3600 level=wayfarers_rest
	run level level_smoke
fi
wait

failed=0
for f in "$OUT"/*.txt; do
	name=$(basename "$f" .txt)
	[ "$name" = "import" ] && continue
	read -r _ code secs <<< "$(grep '^EXIT' "$f" | tail -1)"
	total=$(grep -E "REGRESSIONS|SMOKE|TUTORIAL [0-9]|CHAOS TEST|LEVEL SMOKE|^SOAK|HOUSE SMOKE|EDGE CHECK|AHEAD CHECK|FIXES CHECK" "$f" | tail -1)
	extra=$(grep -E "FINGERPRINT|Purse at the close" "$f" | sed 's/^ *//' | tr '\n' ' ')
	# A script error fails the suite even when every check passed: a function
	# that errors returns a default, and the checks after it can still hold.
	if [ "$code" = "0" ] && grep -q "SCRIPT ERROR" "$f"; then
		code="script-error"
		total="$total ($(grep -c "SCRIPT ERROR" "$f") script errors)"
	fi
	if [ "$code" = "0" ]; then
		printf "ok    %-12s %4ss  %s %s\n" "$name" "$secs" "$total" "$extra"
	else
		failed=1
		printf "FAIL  %-12s %4ss  %s\n" "$name" "$secs" "$total"
		grep -E "^FAIL|^SOAK|HOLE|SCRIPT ERROR|^TUT .*FAIL|^ {5}[a-z ]+: " "$f" | head -12 | sed 's/^/        /'
	fi
done
echo "logs: $OUT"
exit $failed

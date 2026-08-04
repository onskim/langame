#!/usr/bin/env bash
# Run every acceptance suite. One command, so a regression in an earlier week
# cannot hide behind a later week's green run.
set -u
cd "$(dirname "$0")/../game" || exit 1
SAVE="$HOME/Library/Application Support/Godot/app_userdata/Langame/save.json"
fail=0

# keep_save=1 for a suite that must read what the previous run wrote.
run() {
  local name="$1"; shift
  local keep="${KEEP_SAVE:-0}"
  [ "$keep" = "1" ] || rm -f "$SAVE"
  local out
  out=$(godot --headless --quit-after 8000 "$@" 2>&1)
  local passes failures
  passes=$(grep -c "  PASS" <<<"$out")
  failures=$(grep -c "  FAIL" <<<"$out")
  if [ "$failures" -gt 0 ]; then
    printf '  %-10s %2d passed, %d FAILED\n' "$name" "$passes" "$failures"
    grep "  FAIL" <<<"$out"
    fail=1
  else
    printf '  %-10s %2d passed\n' "$name" "$passes"
  fi
}

echo "=== acceptance suites ==="
run "week1" res://dev/acceptance_week1.tscn -- pass1
# pass2 verifies persistence across a real process boundary, so it must
# NOT start from a wiped save.
KEEP_SAVE=1 run "week1-p2" res://dev/acceptance_week1.tscn -- pass2
run "week2" res://dev/acceptance_week2.tscn
run "week3" res://dev/acceptance_week3.tscn
run "week4" res://dev/acceptance_week4.tscn
run "week5" res://dev/acceptance_week5.tscn
run "world" res://dev/acceptance_world.tscn
run "scenes" res://dev/acceptance_scenes.tscn

echo "=== content lint ==="
(cd .. && .venv/bin/python tools/lint_content.py | tail -1) || fail=1

exit $fail

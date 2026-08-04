#!/usr/bin/env python3
"""30-day bot player — GDD Part 10 §6 Week 4 acceptance.

  "simulate.py 30-day bot run: review load stays 5–15/day, no starved words"

The simulation itself runs INSIDE Godot (game/dev/simulate.gd) so it exercises
the same Scheduler / Mastery / WordStats code the game runs. A Python
reimplementation of the algorithms would drift from the engine and prove
nothing. This script drives it, parses the JSON it emits, and enforces the
acceptance band.

Usage:
  .venv/bin/python tools/simulate.py                 # 30 days, default bot
  .venv/bin/python tools/simulate.py --days 60
  .venv/bin/python tools/simulate.py --sweep         # several bot accuracies
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")

BEGIN = "SIMULATION_JSON_BEGIN"
END = "SIMULATION_JSON_END"


def find_godot():
    godot = shutil.which("godot") or shutil.which("Godot")
    if not godot:
        print("ERROR: godot not on PATH. Install Godot 4.3+ and retry.",
              file=sys.stderr)
        sys.exit(2)
    return godot


def run_sim(days, accuracy, seed):
    cmd = [
        find_godot(), "--headless", "--path", GAME, "res://dev/simulate.tscn",
        "--", "--days=%d" % days, "--accuracy=%s" % accuracy, "--seed=%d" % seed,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    out = proc.stdout
    if BEGIN not in out or END not in out:
        print("ERROR: simulation produced no result.", file=sys.stderr)
        print(out[-2000:], file=sys.stderr)
        print(proc.stderr[-2000:], file=sys.stderr)
        sys.exit(2)
    payload = out.split(BEGIN, 1)[1].split(END, 1)[0].strip()
    return json.loads(payload)


def evaluate(result, quiet=False):
    """Returns (ok, failures). Acceptance per Part 10 §6 Week 4."""
    failures = []

    lo = 5
    hi = 15
    # Day 1-2 cannot have a review load: nothing has been introduced yet.
    warm = [row for row in result["daily"] if row["day"] > 2]

    under = [r for r in warm if r["review_load"] < lo]
    over = [r for r in warm if r["review_load"] > hi]
    if under:
        failures.append("review load below %d on %d day(s): %s"
                        % (lo, len(under), [(r["day"], r["review_load"]) for r in under[:6]]))
    if over:
        failures.append("review load above %d on %d day(s): %s"
                        % (hi, len(over), [(r["day"], r["review_load"]) for r in over[:6]]))

    starved = result["starved_total"]
    if starved:
        failures.append("%d starved word(s) by day %d: %s"
                        % (starved, result["days"], result["starved_ids"][:8]))

    if not quiet:
        print("  days %d · bot accuracy %.2f · seed %d"
              % (result["days"], result["accuracy"], result["seed"]))
        print("  words introduced   %d" % result["introduced_total"])
        print("  review load        min %d / mean %.1f / max %d   (target %d–%d)"
              % (result["review_load_min"], result["review_load_mean"],
                 result["review_load_max"], lo, hi))
        print("  starved words      %d" % starved)
        print("  mean mastery       %.3f" % result["mean_mastery_final"])

    return (not failures), failures


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--accuracy", type=float, default=0.8)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--sweep", action="store_true",
                    help="run several bot accuracies; a scheduler that only "
                         "works for one kind of learner is not tuned")
    args = ap.parse_args()

    runs = []
    if args.sweep:
        for accuracy in (0.5, 0.65, 0.8, 0.95):
            runs.append((args.days, accuracy, args.seed))
    else:
        runs.append((args.days, args.accuracy, args.seed))

    all_ok = True
    for days, accuracy, seed in runs:
        print("--- simulate: %d days @ accuracy %.2f ---" % (days, accuracy))
        result = run_sim(days, accuracy, seed)
        ok, failures = evaluate(result)
        for f in failures:
            print("  FAIL  %s" % f)
        print("  %s" % ("PASS" if ok else "FAIL"))
        all_ok = all_ok and ok

    print("\nWeek 4 acceptance: %s" % ("PASS" if all_ok else "FAIL"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())

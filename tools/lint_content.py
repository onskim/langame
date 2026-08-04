#!/usr/bin/env python3
"""Content lint v0 — GDD Part 5 §4 step 3, Part 9 §2 authoring checklist.

This is the AUTOMATED gate. It does not replace the native-speaker gate
(Part 5 §4 step 4); it just catches what a machine can catch first so the
reviewer's hours go on grammar and naturalness, not on bookkeeping.

Checks:
  REF   every referenced id resolves (line->word, quest->line, quest->prereq,
        line->npc, gesture->word, distractor->word)
  INTRO no word is used in a quest before the quest that introduces it
        ("forbidden-word check" — Part 5 §4)
  ART   every noun has an article, and it is der/die/das
  A1    banned-for-A1 constructions: subordinate clauses, Konjunktiv, passive,
        genitive; plus a sentence-length cap
  COVER every quest's vocab_tags are actually carried by its lines
  DRAFT reports how much German is still unreviewed (informational, not a failure)

Usage:  .venv/bin/python tools/lint_content.py [--strict]
        --strict also fails on warnings.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compile_db  # noqa: E402

MAX_A1_WORDS = 8  # sentence-length cap for A1 lines

# Banned A1 constructions (Part 5 §4 constraint kit). Deliberately conservative:
# these are heuristics meant to flag for human review, not to be authoritative.
SUBORDINATE_CONJUNCTIONS = {
    "weil", "dass", "obwohl", "damit", "wenn", "als", "während", "bevor",
    "nachdem", "seitdem", "falls", "sobald", "solange", "ob",
}
KONJUNKTIV_MARKERS = {"wäre", "hätte", "würde", "könnte", "möchte", "sollte", "müsste"}
PASSIVE_MARKERS = {"wird", "wurde", "werden", "wurden"}
GENITIVE_ARTICLES = {"des", "der eines", "eines", "einer"}
VALID_ARTICLES = {"der", "die", "das"}


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.notes = []

    def error(self, code, msg):
        self.errors.append("%s  %s" % (code, msg))

    def warn(self, code, msg):
        self.warnings.append("%s  %s" % (code, msg))

    def note(self, msg):
        self.notes.append(msg)


def words_of(text):
    return re.findall(r"[A-Za-zÄÖÜäöüß]+", text)


def check_refs(b, r):
    words, lines, quests, npcs = b["words"], b["lines"], b["quests"], b["npcs"]

    for lid, ln in sorted(lines.items()):
        if ln.get("npc_id") and ln["npc_id"] not in npcs:
            r.error("REF", "line '%s' -> unknown npc '%s'" % (lid, ln["npc_id"]))
        for w in ln.get("focus_words") or []:
            if w not in words:
                r.error("REF", "line '%s' -> unknown focus word '%s'" % (lid, w))
        for g in ln.get("gestures") or []:
            if g.get("word") and g["word"] not in words:
                r.error("REF", "line '%s' gesture -> unknown word '%s'" % (lid, g["word"]))

    for wid, w in sorted(words.items()):
        for d in w.get("distractors") or []:
            if d not in words:
                r.error("REF", "word '%s' -> unknown distractor '%s'" % (wid, d))
        if w.get("intro_quest") and w["intro_quest"] not in quests:
            r.error("REF", "word '%s' -> unknown intro_quest '%s'" % (wid, w["intro_quest"]))

    for qid, q in sorted(quests.items()):
        for p in q.get("prereq") or []:
            if p not in quests:
                r.error("REF", "quest '%s' -> unknown prereq '%s'" % (qid, p))
        if q.get("giver") and q["giver"] not in npcs and q["giver"] != "auto":
            r.error("REF", "quest '%s' -> unknown giver '%s'" % (qid, q["giver"]))
        for step in q.get("steps") or []:
            for key in ("line", "hint_line"):
                if step.get(key) and step[key] not in lines:
                    r.error("REF", "quest '%s' -> unknown %s '%s'" % (qid, key, step[key]))
        for t in q.get("vocab_tags") or []:
            if t not in words:
                r.error("REF", "quest '%s' -> unknown vocab tag '%s'" % (qid, t))


def quest_order(quests):
    """Topological-ish order by prereq depth, so 'introduced before use' is meaningful."""
    depth = {}

    def resolve(qid, seen):
        if qid in depth:
            return depth[qid]
        if qid in seen:            # prereq cycle; REF/cycle reported separately
            return 0
        seen.add(qid)
        prereqs = quests.get(qid, {}).get("prereq") or []
        d = 0 if not prereqs else 1 + max(resolve(p, seen) for p in prereqs if p in quests)
        depth[qid] = d
        return d

    for qid in quests:
        resolve(qid, set())
    return depth


def check_intro_order(b, r):
    """No word may be used by a quest that runs before the quest introducing it."""
    words, lines, quests = b["words"], b["lines"], b["quests"]
    depth = quest_order(quests)

    for qid, q in sorted(quests.items()):
        qdepth = depth.get(qid, 0)
        used = set()
        for step in q.get("steps") or []:
            for key in ("line", "hint_line"):
                lid = step.get(key)
                if lid and lid in lines:
                    used.update(lines[lid].get("focus_words") or [])
        for wid in sorted(used):
            w = words.get(wid)
            if not w or not w.get("intro_quest"):
                continue
            intro = w["intro_quest"]
            if intro not in quests:
                continue
            if depth.get(intro, 0) > qdepth:
                r.error("INTRO", "quest '%s' uses '%s' but it is introduced later in '%s'"
                        % (qid, wid, intro))


def check_articles(b, r):
    for wid, w in sorted(b["words"].items()):
        if w.get("pos") != "noun":
            continue
        art = w.get("article")
        if not art:
            r.error("ART", "noun '%s' has no article" % wid)
        elif art not in VALID_ARTICLES:
            r.error("ART", "noun '%s' has article '%s' (expected der/die/das)" % (wid, art))


def check_a1(b, r):
    for lid, ln in sorted(b["lines"].items()):
        de = ln.get("de") or ""
        tokens = [t.lower() for t in words_of(de)]

        if len(tokens) > MAX_A1_WORDS:
            r.warn("A1", "line '%s' is %d words (cap %d for A1): %r"
                   % (lid, len(tokens), MAX_A1_WORDS, de))

        for t in tokens:
            if t in SUBORDINATE_CONJUNCTIONS:
                r.warn("A1", "line '%s' may use a subordinate clause ('%s'): %r" % (lid, t, de))
            if t in KONJUNKTIV_MARKERS:
                r.warn("A1", "line '%s' may use Konjunktiv ('%s'): %r" % (lid, t, de))
            if t in GENITIVE_ARTICLES:
                r.warn("A1", "line '%s' may use genitive ('%s'): %r" % (lid, t, de))

        # Passive needs an auxiliary AND a participle; 'wird' alone is fine.
        if any(t in PASSIVE_MARKERS for t in tokens) and re.search(r"\bge\w+t\b", de.lower()):
            r.warn("A1", "line '%s' may be passive: %r" % (lid, de))


def check_coverage(b, r):
    """A quest's declared vocab must actually appear in the lines it plays."""
    lines, quests = b["lines"], b["quests"]
    for qid, q in sorted(quests.items()):
        tags = set(q.get("vocab_tags") or [])
        if not tags:
            continue
        carried = set()
        for step in q.get("steps") or []:
            for key in ("line", "hint_line"):
                lid = step.get(key)
                if lid and lid in lines:
                    carried.update(lines[lid].get("focus_words") or [])
        missing = tags - carried
        if missing:
            r.warn("COVER", "quest '%s' declares vocab %s but no line carries %s"
                   % (qid, sorted(tags), sorted(missing)))


def check_draft(b, r):
    lines = b["lines"]
    draft = [lid for lid, ln in lines.items() if ln.get("draft", True)]
    if draft:
        r.note("%d/%d lines still draft:true — unreviewed German, dev builds only "
               "(Part 5 §4 gate): %s" % (len(draft), len(lines), ", ".join(sorted(draft))))
    words = b["words"]
    wdraft = [w for w, v in words.items() if v.get("draft", True)]
    if wdraft:
        r.note("%d/%d words still draft:true" % (len(wdraft), len(words)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--strict", action="store_true", help="fail on warnings too")
    args = ap.parse_args()

    try:
        bundle = compile_db.compile_all(quiet=True)
    except compile_db.CompileError as exc:
        print("COMPILE ERROR: %s" % exc, file=sys.stderr)
        return 1

    r = Report()
    check_refs(bundle, r)
    check_intro_order(bundle, r)
    check_articles(bundle, r)
    check_a1(bundle, r)
    check_coverage(bundle, r)
    check_draft(bundle, r)

    print("content lint v0 — %d words, %d lines, %d quests"
          % (len(bundle["words"]), len(bundle["lines"]), len(bundle["quests"])))
    for n in r.notes:
        print("  NOTE   %s" % n)
    for w in r.warnings:
        print("  WARN   %s" % w)
    for e in r.errors:
        print("  ERROR  %s" % e)

    print("%d error(s), %d warning(s)" % (len(r.errors), len(r.warnings)))
    if r.errors:
        return 1
    if args.strict and r.warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

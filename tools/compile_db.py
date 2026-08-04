#!/usr/bin/env python3
"""YAML -> content.db  (GDD Part 10 §3 DDL, Part 5 §4 step 6).

content/*.yaml is the source of truth. This is the ONLY thing that writes
data/content.db — never hand-edit the database (repo CLAUDE.md hard rule).

Two artifacts come out of one source:

  data/content.db                     SQLite, the DDL in Part 10 §3. Consumed by
                                      lint_content.py, simulate.py, review_export.py.
  game/assets/content/content.json    Runtime bundle the engine loads.

Why two: Godot 4 has no built-in SQLite, and reading content through a native
GDExtension would mean vendoring per-platform binaries for Steam + Android + iOS
before we need writes. Content is read-only and small (~500 words, ~1200 lines),
so the engine loads a JSON bundle at boot. The per-save player.db in Week 4 is
where SQLite at runtime actually earns its cost — revisit the GDExtension then.
Both artifacts are generated; neither is hand-edited; YAML stays the truth.

Usage:  .venv/bin/python tools/compile_db.py [--quiet]
"""

import argparse
import json
import os
import sqlite3
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(ROOT, "content")
DB_PATH = os.path.join(ROOT, "data", "content.db")
BUNDLE_PATH = os.path.join(ROOT, "game", "assets", "content", "content.json")

DDL = """
DROP TABLE IF EXISTS words;
DROP TABLE IF EXISTS npcs;
DROP TABLE IF EXISTS lines;
DROP TABLE IF EXISTS quests;

CREATE TABLE words(
  word_id TEXT PRIMARY KEY, concept TEXT, lemma TEXT, article TEXT,
  plural TEXT, pos TEXT, forms JSON, english TEXT, family TEXT,
  cefr TEXT, freq_rank INT, audio_id TEXT, icon_id TEXT, distractors JSON,
  intro_quest TEXT, draft INT DEFAULT 1);
CREATE TABLE npcs(
  npc_id TEXT PRIMARY KEY, name TEXT, role TEXT, voice_preset TEXT,
  schedule JSON, home TEXT, shop JSON, rep_gate INT, wants TEXT);
CREATE TABLE lines(
  line_id TEXT PRIMARY KEY, npc_id TEXT, de TEXT, en TEXT,
  focus_words JSON, gestures JSON, audio_id TEXT, slow_audio_id TEXT,
  response JSON, recasts JSON, draft INT DEFAULT 1);
CREATE TABLE quests(
  quest_id TEXT PRIMARY KEY, kind TEXT CHECK(kind IN('story','template','drill')),
  giver TEXT, rep_gate INT, prereq JSON, steps JSON,
  vocab_tags JSON, slots JSON, rewards JSON);
"""


class CompileError(Exception):
    pass


def load_yaml_dir(subdir, expect_list=None):
    """Load every .yaml under content/<subdir>, recursively.

    A file may hold either a single mapping or a list of them — one NPC per
    file is tidy for Anna, unbearable for a 16-NPC cast.
    """
    base = os.path.join(CONTENT, subdir)
    items = []
    if not os.path.isdir(base):
        return items
    for dirpath, _dirnames, filenames in os.walk(base):
        for fn in sorted(filenames):
            if not fn.endswith((".yaml", ".yml")):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            if data is None:
                continue
            rel = os.path.relpath(path, ROOT)
            if isinstance(data, list):
                for entry in data:
                    if not isinstance(entry, dict):
                        raise CompileError("%s: list entries must be mappings" % rel)
                    entry["_source"] = rel
                items.extend(data)
            elif isinstance(data, dict):
                data["_source"] = rel
                items.append(data)
            else:
                raise CompileError("%s: expected a mapping or a list of mappings" % rel)
    return items


def j(value):
    """JSON-encode a nested structure for a SQLite JSON column."""
    return None if value is None else json.dumps(value, ensure_ascii=False)


def require(entry, field, kind):
    if field not in entry or entry[field] in (None, ""):
        raise CompileError("%s %s: missing required field '%s'"
                           % (kind, entry.get("_source", "?"), field))
    return entry[field]


def compile_all(quiet=False):
    words = load_yaml_dir("words")
    npcs = load_yaml_dir("npcs")
    lines = load_yaml_dir("lines")
    quests = load_yaml_dir("quests")
    configs = load_yaml_dir("config")

    _check_unique(words, "word_id", "word")
    _check_unique(npcs, "npc_id", "npc")
    _check_unique(lines, "line_id", "line")
    _check_unique(quests, "quest_id", "quest")
    _check_unique(configs, "config_id", "config")

    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    con.executescript(DDL)

    for w in words:
        require(w, "word_id", "word")
        require(w, "lemma", "word")
        con.execute(
            "INSERT INTO words(word_id,concept,lemma,article,plural,pos,forms,"
            "english,family,cefr,freq_rank,audio_id,icon_id,distractors,"
            "intro_quest,draft) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (w["word_id"], w.get("concept"), w["lemma"], w.get("article"),
             w.get("plural"), w.get("pos"), j(w.get("forms")), w.get("english"),
             w.get("family"), w.get("cefr"), w.get("freq_rank"), w.get("audio_id"),
             w.get("icon_id"), j(w.get("distractors")), w.get("intro_quest"),
             1 if w.get("draft", True) else 0))

    for n in npcs:
        require(n, "npc_id", "npc")
        con.execute(
            "INSERT INTO npcs(npc_id,name,role,voice_preset,schedule,home,shop,"
            "rep_gate,wants) VALUES(?,?,?,?,?,?,?,?,?)",
            (n["npc_id"], n.get("name"), n.get("role"), n.get("voice_preset"),
             j(n.get("schedule")), n.get("home"), j(n.get("shop")),
             n.get("rep_gate", 0), n.get("wants")))

    for ln in lines:
        require(ln, "line_id", "line")
        require(ln, "de", "line")
        con.execute(
            "INSERT INTO lines(line_id,npc_id,de,en,focus_words,gestures,audio_id,"
            "slow_audio_id,response,recasts,draft) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (ln["line_id"], ln.get("npc_id"), ln["de"], ln.get("en"),
             j(ln.get("focus_words")), j(ln.get("gestures")), ln.get("audio_id"),
             ln.get("slow_audio_id"), j(ln.get("response")), j(ln.get("recasts")),
             1 if ln.get("draft", True) else 0))

    for q in quests:
        require(q, "quest_id", "quest")
        kind = q.get("kind", "story")
        if kind not in ("story", "template", "drill"):
            raise CompileError("quest %s: kind must be story|template|drill, got %r"
                               % (q["quest_id"], kind))
        con.execute(
            "INSERT INTO quests(quest_id,kind,giver,rep_gate,prereq,steps,"
            "vocab_tags,slots,rewards) VALUES(?,?,?,?,?,?,?,?,?)",
            (q["quest_id"], kind, q.get("giver"), q.get("rep_gate", 0),
             j(q.get("prereq")), j(q.get("steps")), j(q.get("vocab_tags")),
             j(q.get("slots")), j(q.get("rewards"))))

    con.commit()

    bundle = _write_bundle(words, npcs, lines, quests, configs)
    con.close()

    if not quiet:
        draft_lines = sum(1 for ln in lines if ln.get("draft", True))
        print("compiled -> %s" % os.path.relpath(DB_PATH, ROOT))
        print("compiled -> %s" % os.path.relpath(BUNDLE_PATH, ROOT))
        print("  %d words, %d npcs, %d lines, %d quests"
              % (len(words), len(npcs), len(lines), len(quests)))
        if draft_lines:
            print("  %d/%d lines are draft:true — NOT cleared for shipping "
                  "(Part 5 §4 native review gate)" % (draft_lines, len(lines)))
    return bundle


def _check_unique(items, key, kind):
    seen = {}
    for item in items:
        if key not in item:
            raise CompileError("%s %s: missing '%s'"
                               % (kind, item.get("_source", "?"), key))
        ident = item[key]
        if ident in seen:
            raise CompileError("duplicate %s '%s' in %s and %s"
                               % (kind, ident, seen[ident], item.get("_source", "?")))
        seen[ident] = item.get("_source", "?")


def _strip(entry):
    return {k: v for k, v in entry.items() if k != "_source"}


def _write_bundle(words, npcs, lines, quests, configs=()):
    """Runtime bundle: dicts keyed by id so the engine does no scanning."""
    bundle = {
        "schema": 1,
        "words": {w["word_id"]: _strip(w) for w in words},
        "npcs": {n["npc_id"]: _strip(n) for n in npcs},
        "lines": {l["line_id"]: _strip(l) for l in lines},
        "quests": {q["quest_id"]: _strip(q) for q in quests},
        "config": {c["config_id"]: _strip(c) for c in configs if "config_id" in c},
    }
    os.makedirs(os.path.dirname(BUNDLE_PATH), exist_ok=True)
    with open(BUNDLE_PATH, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    return bundle


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    try:
        compile_all(quiet=args.quiet)
    except CompileError as exc:
        print("COMPILE ERROR: %s" % exc, file=sys.stderr)
        return 1
    except yaml.YAMLError as exc:
        print("YAML ERROR: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

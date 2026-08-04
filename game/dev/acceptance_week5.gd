extends Node
## Week 5 acceptance (GDD Part 10 §6):
## "Speak 'Guten Morgen' → scored → NPC reacts; 2 fails spawn Q06; cap works."
##
## Runs on the offline scorer, so the whole gate is provable without Azure
## credentials. The Azure path is exercised by the same code once keys exist.
##
##   godot --headless res://dev/acceptance_week5.tscn

var _failures: int = 0


func _ready() -> void:
	await _run()
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL  %s %s" % [label, detail])


func _reset() -> void:
	WordStats.reset()
	DrillSpawner.reset()
	GameState.day = 1


func _run() -> void:
	print("--- Week 5 acceptance: speech, quiet mode, drill gate ---")
	_reset()

	var phrase := "chunk_guten_morgen"
	var expected: String = ContentDB.get_word(phrase).get("lemma", "")
	_check("the phrase comes from content", expected == "Guten Morgen", expected)

	# ---------- speak -> scored ----------
	SpeechService.offline_next_score = 88.0
	var result: Dictionary = await SpeechService.score(expected, [phrase])
	_check("a spoken attempt is scored", result.get("spoken", false))
	_check("a good attempt passes", result.get("passed", false),
		"accuracy=%.0f threshold=%.0f" % [result.get("accuracy", 0), SpeechService.pass_threshold()])
	_check("pron_avg recorded on the word",
		float(WordStats.get_stat(phrase).get("pron_avg", 0.0)) > 0.0,
		"pron_avg=%.1f" % WordStats.get_stat(phrase).get("pron_avg", 0.0))
	_check("spoken success counts double (Addendum §1)",
		int(WordStats.get_stat(phrase).get("times_correct", 0)) == 2,
		"times_correct=%d" % WordStats.get_stat(phrase).get("times_correct", 0))

	# ---------- the silent path is never blocked ----------
	_reset()
	var silent: Dictionary = await SpeechService.score(expected, [phrase], false)
	_check("silent mode still resolves the prompt", silent.get("passed", false))
	_check("silent mode is not scored as speech", not silent.get("spoken", true))
	_check("silent mode earns credit",
		int(WordStats.get_stat(phrase).get("times_correct", 0)) == 1,
		"times_correct=%d" % WordStats.get_stat(phrase).get("times_correct", 0))
	_check("silent mode does not touch the drill counter",
		int(WordStats.get_stat(phrase).get("pron_fails_row", 0)) == 0)

	# A network failure must read as silence, never as bad pronunciation.
	var fallback := SpeechService._network_fallback([phrase], "timeout")
	_check("a network failure is treated as silence, not failure",
		fallback.get("passed", false) and not fallback.get("spoken", true),
		fallback.get("reason", ""))

	# ---------- 2 fails spawn the drill ----------
	_reset()
	SpeechService.offline_next_score = 30.0
	await SpeechService.score(expected, [phrase])
	_check("one failure does not flag", not DrillSpawner.is_flagged(phrase),
		"fails_row=%d" % WordStats.get_stat(phrase).get("pron_fails_row", 0))

	var spawned: Array = []
	DrillSpawner.drill_spawned.connect(func(w: String, q: String) -> void:
		spawned.append({"word": w, "quest": q}))

	await SpeechService.score(expected, [phrase])
	_check("two consecutive failures flag the word", DrillSpawner.is_flagged(phrase),
		"fails_row=%d" % WordStats.get_stat(phrase).get("pron_fails_row", 0))
	_check("a drill quest is spawned", spawned.size() == 1, str(spawned))
	if spawned.size() == 1:
		_check("the spawned quest is drill-kind",
			ContentDB.get_quest(spawned[0]["quest"]).get("kind", "") == "drill",
			str(spawned[0]))

	# ---------- 2 consecutive passes clear it ----------
	SpeechService.offline_next_score = 90.0
	await SpeechService.score(expected, [phrase])
	_check("one pass is not enough to clear", DrillSpawner.is_flagged(phrase))
	await SpeechService.score(expected, [phrase])
	_check("two consecutive passes clear the flag", not DrillSpawner.is_flagged(phrase))
	_check("a cleared word stays hot (due tomorrow)",
		int(WordStats.get_stat(phrase).get("due_day", 0)) == GameState.day + 1,
		"due=%d day=%d" % [WordStats.get_stat(phrase).get("due_day", 0), GameState.day])

	# ---------- the mercy caps ----------
	# 3 cycles, then the word stops gating anything, whatever the accuracy.
	_reset()
	SpeechService.offline_next_score = 20.0
	for cycle in range(DrillSpawner.max_cycles()):
		await SpeechService.score(expected, [phrase])
		await SpeechService.score(expected, [phrase])
		DrillSpawner._clear(phrase, "test_cycle")
	_check("drill cycles are counted",
		int(WordStats.get_stat(phrase).get("drill_cycles", 0)) == DrillSpawner.max_cycles(),
		"cycles=%d" % WordStats.get_stat(phrase).get("drill_cycles", 0))

	await SpeechService.score(expected, [phrase])
	await SpeechService.score(expected, [phrase])
	_check("past the cycle cap the word never flags again",
		not DrillSpawner.is_flagged(phrase),
		"cycles=%d" % WordStats.get_stat(phrase).get("drill_cycles", 0))

	# One-day block ceiling: a flag raised yesterday cannot gate today.
	_reset()
	SpeechService.offline_next_score = 20.0
	await SpeechService.score(expected, [phrase])
	await SpeechService.score(expected, [phrase])
	_check("a fresh flag blocks progression today", DrillSpawner.blocks_progression(phrase))
	GameState.day += 1
	_check("it stops blocking the next day", not DrillSpawner.blocks_progression(phrase),
		"day=%d" % GameState.day)
	_check("and the flag is released", not DrillSpawner.is_flagged(phrase))

	# ---------- quiet mode ----------
	MicCapture.set_quiet_mode(true)
	_check("quiet mode disables capture", not MicCapture.is_available())
	_check("quiet mode persists", bool(SaveService.load_game().get("quiet_mode", false)))
	MicCapture.set_quiet_mode(false)

	# ---------- config, not constants ----------
	_check("pass threshold comes from content",
		is_equal_approx(SpeechService.pass_threshold(), 60.0),
		"%.0f" % SpeechService.pass_threshold())
	_check("Azure backend is off without credentials", not SpeechService.is_available())

	print("--- Week 5 acceptance complete, %d failure(s). ---" % _failures)

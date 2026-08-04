extends Node
## Speech scoring. GDD Part 10 §4 (Azure PA call), Part 3 §1 Tier IV.
##
## THE RULE THIS FILE EXISTS TO ENFORCE: speech is an amplifier, never a gate.
## Every speech prompt has a silent path, and the game is 100% completable mute
## (Addendum §1 revises this to speech-FIRST, but the silent fallback stays —
## it is a reduced-credit path, not a blocked one).
##
## The scorer is pluggable. Azure Pronunciation Assessment is the production
## backend; a deterministic offline scorer stands in until credentials exist,
## so the whole drill/recast/gate loop is testable today rather than blocked on
## a key. Network failure is NOT failure: a timeout is treated as a silent-mode
## answer, because punishing a player for their wifi is indefensible.

signal scored(result: Dictionary)

enum Backend { OFFLINE, AZURE }

## Set by the offline scorer for deterministic tests.
var offline_next_score: float = 85.0
var backend: int = Backend.OFFLINE

## Azure config, injected from the environment — never committed.
var azure_key: String = ""
var azure_region: String = ""

const TIMEOUT_SECONDS := 4.0


func _ready() -> void:
	azure_key = OS.get_environment("AZURE_SPEECH_KEY")
	azure_region = OS.get_environment("AZURE_SPEECH_REGION")
	if azure_key != "" and azure_region != "":
		backend = Backend.AZURE
		print("[speech] Azure backend ready (region %s)" % azure_region)
	else:
		backend = Backend.OFFLINE
		print("[speech] no AZURE_SPEECH_KEY/REGION — offline scorer in use")


func is_available() -> bool:
	return backend == Backend.AZURE


## Score an utterance against the expected German.
## Always returns a result; never throws, never blocks progression.
func score(expected_de: String, word_ids: Array, spoken: bool = true) -> Dictionary:
	var result: Dictionary
	if not spoken:
		result = _silent_result(word_ids)
	elif backend == Backend.AZURE:
		result = await _score_azure(expected_de, word_ids)
	else:
		result = _score_offline(expected_de, word_ids)

	_apply_to_learner_model(result)
	scored.emit(result)
	return result


func pass_threshold() -> float:
	return float(Config.threshold_group("pronunciation").get("a1_pass_accuracy", 60))


## Addendum §1: silence is a REDUCED-CREDIT fallback, not a free pass.
## It resolves the prompt and earns comprehension credit, but it must not
## advance the schedule as far as a demonstrated spoken answer — otherwise a
## whole quiet-mode run manufactures evidence of mastery the player never gave.
const SILENT_CREDIT := 0.5

func _silent_result(word_ids: Array) -> Dictionary:
	return {
		"spoken": false,
		"accuracy": 0.0,
		"passed": true,
		"silent": true,
		"credit": SILENT_CREDIT,
		"words": word_ids,
		"reason": "silent_mode",
	}


## Deterministic stand-in. Not a simulation of a speaker — a fixture, so the
## drill gate can be exercised without a microphone or a key.
func _score_offline(_expected_de: String, word_ids: Array) -> Dictionary:
	var accuracy := offline_next_score
	return {
		"spoken": true,
		"accuracy": accuracy,
		"passed": accuracy >= pass_threshold(),
		"silent": false,
		"words": word_ids,
		"reason": "offline_scorer",
	}


## POST audio to Azure Pronunciation Assessment (Part 10 §4):
## <=6s, 16kHz mono WAV, gradingSystem HundredMark, granularity Word,
## dimension Comprehensive. 4s timeout -> treat as a silent-mode answer.
func _score_azure(expected_de: String, word_ids: Array) -> Dictionary:
	var audio := MicCapture.take_wav()
	if audio.is_empty():
		return _silent_result(word_ids)

	var config := {
		"referenceText": expected_de,
		"gradingSystem": "HundredMark",
		"granularity": "Word",
		"dimension": "Comprehensive",
	}
	var url := "https://%s.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=de-DE" % azure_region
	var headers := PackedStringArray([
		"Ocp-Apim-Subscription-Key: " + azure_key,
		"Content-Type: audio/wav; codecs=audio/pcm; samplerate=16000",
		"Pronunciation-Assessment: " + Marshalls.utf8_to_base64(JSON.stringify(config)),
	])

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = TIMEOUT_SECONDS
	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, audio)
	if err != OK:
		http.queue_free()
		return _network_fallback(word_ids, "request_failed")

	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	if code != 200:
		return _network_fallback(word_ids, "http_%d" % code)

	var body: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if typeof(body) != TYPE_DICTIONARY:
		return _network_fallback(word_ids, "bad_body")

	var accuracy := _extract_accuracy(body)
	return {
		"spoken": true,
		"accuracy": accuracy,
		"passed": accuracy >= pass_threshold(),
		"silent": false,
		"words": word_ids,
		"reason": "azure",
	}


## A network problem must never read as a pronunciation problem.
func _network_fallback(word_ids: Array, reason: String) -> Dictionary:
	push_warning("[speech] falling back to silent mode: %s" % reason)
	var result := _silent_result(word_ids)
	result["reason"] = "network_fallback:" + reason
	return result


func _extract_accuracy(body: Dictionary) -> float:
	var nbest: Variant = body.get("NBest")
	if nbest is Array and (nbest as Array).size() > 0:
		var top: Dictionary = (nbest as Array)[0]
		var pa: Variant = top.get("PronunciationAssessment")
		if pa is Dictionary:
			return float((pa as Dictionary).get("AccuracyScore", 0.0))
	return 0.0


## Feed the result into the learner model. Spoken successes count double
## (Addendum §1); a spoken failure increments the drill counter.
func _apply_to_learner_model(result: Dictionary) -> void:
	var spoken: bool = result.get("spoken", false)
	var passed: bool = result.get("passed", false)
	for word_id in result.get("words", []):
		var s := WordStats.get_stat(word_id)
		if spoken:
			s["pron_avg"] = _rolling_average(s, float(result.get("accuracy", 0.0)))
			if passed:
				s["pron_fails_row"] = 0
			else:
				s["pron_fails_row"] += 1
		WordStats.record(word_id, passed, GameState.day, spoken,
			float(result.get("credit", 1.0)))
		if spoken:
			if passed:
				DrillSpawner.on_pronunciation_pass(word_id)
			else:
				DrillSpawner.on_pronunciation_fail(word_id)


func _rolling_average(s: Dictionary, accuracy: float) -> float:
	var spoken_count := float(s.get("times_spoken", 0))
	var previous := float(s.get("pron_avg", 0.0))
	if spoken_count <= 0.0:
		return accuracy
	return (previous * spoken_count + accuracy) / (spoken_count + 1.0)

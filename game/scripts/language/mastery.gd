extends Node
## Mastery scoring. GDD Part 10 §4:
##
##   mastery = clamp(0.35*recog + 0.25*prod + 0.25*pron + 0.15*recency, 0, 1)
##
## recog  = correct/(correct+wrong), recency-decayed
## prod   = Tier II/III success rate
## pron   = pron_avg / 100
## Spoken successes already count double where they are recorded (Addendum §1).
##
## Weights come from content/config/mastery_weights.yaml, never from code.


## Recompute and store `mastery` on a word_stats row.
func update(s: Dictionary, day: int) -> float:
	var value := compute(s, day)
	s["mastery"] = value
	return value


## Addendum §10.2: while pronunciation is unavailable its weight is
## redistributed, otherwise mastery is arithmetically capped at 0.50 and no word
## can ever reach support tier L2/L3.
func weights() -> Dictionary:
	if bool(Config.mastery("speech_enabled", false)):
		return {
			"recognition": float(Config.mastery("recognition", 0.35)),
			"production": float(Config.mastery("production", 0.25)),
			"pronunciation": float(Config.mastery("pronunciation", 0.25)),
			"recency": float(Config.mastery("recency", 0.15)),
		}
	var fallback: Variant = Config.mastery("no_speech", {})
	var no_speech: Dictionary = fallback if fallback is Dictionary else {}
	return {
		"recognition": float(no_speech.get("recognition", 0.45)),
		"production": float(no_speech.get("production", 0.35)),
		"pronunciation": 0.0,
		"recency": float(no_speech.get("recency", 0.20)),
	}


func compute(s: Dictionary, day: int) -> float:
	var w := weights()
	var w_recog: float = w["recognition"]
	var w_prod: float = w["production"]
	var w_pron: float = w["pronunciation"]
	var w_recency: float = w["recency"]

	var recog := recognition(s, day)
	var prod := production(s)
	var pron := float(s.get("pron_avg", 0.0)) / 100.0
	var rec := recency(s, day)

	var raw := w_recog * recog + w_prod * prod + w_pron * pron + w_recency * rec
	return clampf(raw, 0.0, 1.0)


## Part 10 §4: correct/(correct+wrong), recency-decayed.
##
## Repair use is deliberately NOT subtracted here. Part 3 §2 says using the
## repair tools is never penalised; it is logged as a weak signal elsewhere.
## Docking mastery for it made a free affordance quietly expensive.
func recognition(s: Dictionary, day: int = -1) -> float:
	var correct := float(s.get("times_correct", 0))
	var wrong := float(s.get("times_wrong", 0))
	var total := correct + wrong
	if total <= 0.0:
		return 0.0
	var ratio := clampf(correct / total, 0.0, 1.0)
	if day < 0:
		return ratio
	# Recency-decayed: an old success is weaker evidence than a fresh one, but
	# never worthless — the floor keeps a well-learned word from reading as unknown.
	return ratio * lerpf(0.6, 1.0, recency(s, day))


## Tier II/III production = SUCCESS RATE, not attempt count.
##
## This previously returned times_spoken / (correct + wrong), which is an
## attempt ratio: a learner who spoke and failed every time scored 1.0, and a
## flawless speaker was pinned at 0.5 by the spoken double-count. Production is
## now tracked on its own counters so neither distortion can recur.
func production(s: Dictionary) -> float:
	var attempts := float(s.get("prod_attempts", 0))
	if attempts <= 0.0:
		return 0.0
	return clampf(float(s.get("prod_successes", 0)) / attempts, 0.0, 1.0)


## 1.0 when just seen, decaying to 0 across the horizon.
func recency(s: Dictionary, day: int) -> float:
	var horizon := float(Config.mastery("recency_horizon_days", 14))
	if horizon <= 0.0:
		return 0.0
	var elapsed := float(day - int(s.get("last_seen_day", day)))
	return clampf(1.0 - elapsed / horizon, 0.0, 1.0)


## Support tier for a line: min mastery across its focus words (Part 10 §4).
## L0 <0.25, L1 <0.5, L2 <0.75, L3 >=0.75
func support_tier(focus_words: Array) -> int:
	if focus_words.is_empty():
		return 3
	var lowest := 1.0
	for word_id in focus_words:
		var s := WordStats.get_stat(word_id)
		lowest = min(lowest, float(s.get("mastery", 0.0)))
	if lowest < 0.25:
		return 0
	if lowest < 0.5:
		return 1
	if lowest < 0.75:
		return 2
	return 3

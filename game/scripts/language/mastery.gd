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


func compute(s: Dictionary, day: int) -> float:
	var w_recog := float(Config.mastery("recognition", 0.35))
	var w_prod := float(Config.mastery("production", 0.25))
	var w_pron := float(Config.mastery("pronunciation", 0.25))
	var w_recency := float(Config.mastery("recency", 0.15))

	var recog := recognition(s)
	var prod := production(s)
	var pron := float(s.get("pron_avg", 0.0)) / 100.0
	var rec := recency(s, day)

	var raw := w_recog * recog + w_prod * prod + w_pron * pron + w_recency * rec
	return clampf(raw, 0.0, 1.0)


func recognition(s: Dictionary) -> float:
	var correct := float(s.get("times_correct", 0))
	var wrong := float(s.get("times_wrong", 0))
	var total := correct + wrong
	if total <= 0.0:
		return 0.0
	# Repair use is a weak-signal miss: it never punishes the player, but it
	# does mean the word is not yet solid (Part 3 §2).
	var repair_drag := float(s.get("repair_uses", 0)) * 0.5
	return clampf((correct - repair_drag) / total, 0.0, 1.0)


## Tier II/III production. Until those tiers exist (Week 6), spoken attempts
## are the only production signal we have.
func production(s: Dictionary) -> float:
	var spoken := float(s.get("times_spoken", 0))
	if spoken <= 0.0:
		return 0.0
	var correct := float(s.get("times_correct", 0))
	var wrong := float(s.get("times_wrong", 0))
	var total := correct + wrong
	if total <= 0.0:
		return 0.0
	return clampf(spoken / total, 0.0, 1.0)


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

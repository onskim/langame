extends Node
class_name QuestEngine
## Quest engine — story kind. GDD Part 10 §6 Week 3.
##
## Owns the quest lifecycle: which quests are available (prereqs + reputation
## gates), which is active, how steps advance, and what completion pays out.
## Supersedes Week 2's StoryQuestRunner, which only knew how to walk one quest.
##
## Template binding and drill spawning are Week 4/5; this deliberately handles
## `kind: story` only and says so loudly if handed anything else.

signal quest_offered(quest_id: String)
signal quest_started(quest_id: String)
signal step_advanced(quest_id: String, index: int)
signal objective_progress(quest_id: String, done: int, needed: int)
signal quest_completed(quest_id: String, rewards: Dictionary)

var active_quest: String = ""
var step_index: int = -1
## Progress toward a counted objective (Q03 waters 4 plots).
var objective_count: int = 0

var _runner: CanvasLayer  # DialogueRunner
var _quest: Dictionary = {}


func setup(dialogue_runner: CanvasLayer) -> void:
	_runner = dialogue_runner
	_runner.objective_resolved.connect(_on_objective_resolved)
	_runner.line_finished.connect(_on_line_finished)


## Quests whose prereqs and reputation gate are satisfied and which are not
## already done. Order is content order, so authors control the offer sequence.
func available_quests() -> Array[String]:
	var out: Array[String] = []
	var ids := ContentDB.quests.keys()
	ids.sort()
	for quest_id in ids:
		if is_available(quest_id):
			out.append(quest_id)
	return out


func is_available(quest_id: String) -> bool:
	if GameState.completed_quests.has(quest_id):
		return false
	var q := ContentDB.get_quest(quest_id)
	if q.is_empty() or q.get("kind", "story") != "story":
		return false
	if GameState.reputation < int(q.get("rep_gate", 0)):
		return false
	var prereq: Variant = q.get("prereq")
	if prereq is Array:
		for p in prereq:
			if not GameState.completed_quests.has(p):
				return false
	return true


## Start the first available quest. Returns "" if none are unlocked.
func start_next_available() -> String:
	var candidates := available_quests()
	if candidates.is_empty():
		return ""
	return candidates[0] if start(candidates[0]) else ""


func start(quest_id: String) -> bool:
	if active_quest != "":
		return false
	var q := ContentDB.get_quest(quest_id)
	if q.is_empty():
		push_error("QuestEngine: unknown quest '%s'" % quest_id)
		return false
	if q.get("kind", "story") != "story":
		push_error("QuestEngine: '%s' is kind '%s'; only story is handled until Week 4"
			% [quest_id, q.get("kind", "")])
		return false
	if not is_available(quest_id):
		return false

	_quest = q
	active_quest = quest_id
	step_index = -1
	objective_count = 0
	quest_started.emit(quest_id)
	print("[quest] start %s" % quest_id)
	_next_step()
	return true


func _steps() -> Array:
	var s: Variant = _quest.get("steps", [])
	return s if s is Array else []


func current_step() -> Dictionary:
	var steps := _steps()
	if step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]


## How many actions the open objective needs (1 unless the step says otherwise).
func objective_needed() -> int:
	var objective: Variant = current_step().get("objective")
	if objective is Dictionary:
		return int(objective.get("count", 1))
	return 1


## Player-facing task text for the phone. Uses the German lemma of the step's
## focus word — the task list is itself exposure, not an English translation.
func active_task_label() -> String:
	if active_quest == "":
		return ""
	var step := current_step()
	var line := ContentDB.get_line(step.get("line", ""))
	var focus: Array = line.get("focus_words", []) if line.get("focus_words") != null else []
	var lemmas: Array[String] = []
	for word_id in focus:
		var lemma: String = ContentDB.get_word(word_id).get("lemma", "")
		if lemma != "":
			lemmas.append(lemma)
	var needed := objective_needed()
	var progress := "" if needed <= 1 else "  %d/%d" % [objective_count, needed]
	return "%s%s" % [" · ".join(lemmas), progress]


func _next_step() -> void:
	step_index += 1
	objective_count = 0
	var steps := _steps()
	if step_index >= steps.size():
		_complete()
		return
	step_advanced.emit(active_quest, step_index)
	_runner.play_line(steps[step_index].get("line", ""))


func _on_objective_resolved(correct: bool, _target: String) -> void:
	if active_quest == "" or not correct:
		return
	objective_count += 1
	var needed := objective_needed()
	objective_progress.emit(active_quest, objective_count, needed)
	if objective_count < needed:
		# Counted objective still running — reopen it rather than advancing.
		var objective: Variant = current_step().get("objective")
		if objective is Dictionary:
			_runner.current_objective = (objective as Dictionary).duplicate()
		return
	_runner.close()


func _on_line_finished(_line_id: String) -> void:
	if active_quest == "":
		return
	var step := current_step()
	var objective: Variant = step.get("objective")
	if objective != null and objective_count < objective_needed():
		return
	_next_step()


func _complete() -> void:
	var finished := active_quest
	var rewards: Dictionary = _quest.get("rewards", {}) if _quest.get("rewards") != null else {}
	active_quest = ""
	step_index = -1
	print("[quest] complete %s rewards=%s" % [finished, rewards])
	quest_completed.emit(finished, rewards)

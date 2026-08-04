extends Node
class_name StoryQuestRunner
## Minimal story-quest driver so Q02 is playable end-to-end in Week 2.
##
## Deliberately narrow: it walks a quest's `steps`, plays each line, waits for
## the Tier I objective, and applies rewards. The real quest engine — gating,
## prereqs, template binding, drill spawning — is Week 3 (Part 10 §6).

signal quest_started(quest_id: String)
signal step_advanced(index: int)
signal quest_completed(quest_id: String, rewards: Dictionary)

var quest_id: String = ""
var step_index: int = -1
var active: bool = false

var _runner: CanvasLayer  # DialogueRunner
var _quest: Dictionary = {}


func setup(dialogue_runner: CanvasLayer) -> void:
	_runner = dialogue_runner
	_runner.objective_resolved.connect(_on_objective_resolved)
	_runner.line_finished.connect(_on_line_finished)


func start(id: String) -> bool:
	_quest = ContentDB.get_quest(id)
	if _quest.is_empty():
		push_error("StoryQuestRunner: unknown quest '%s'" % id)
		return false
	quest_id = id
	step_index = -1
	active = true
	quest_started.emit(id)
	print("[quest] start %s" % id)
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


func _next_step() -> void:
	step_index += 1
	var steps := _steps()
	if step_index >= steps.size():
		_complete()
		return
	step_advanced.emit(step_index)
	_runner.play_line(steps[step_index].get("line", ""))


func _on_objective_resolved(correct: bool, _target: String) -> void:
	if not active or not correct:
		return
	# Objective met: close the current line, which advances via line_finished.
	_runner.close()


func _on_line_finished(_line_id: String) -> void:
	if not active:
		return
	# A step with an unmet objective must not advance on close.
	var step := current_step()
	var objective: Variant = step.get("objective")
	if objective != null and not _runner.current_objective.is_empty():
		return
	_next_step()


func _complete() -> void:
	active = false
	var rewards: Dictionary = _quest.get("rewards", {}) if _quest.get("rewards") != null else {}
	print("[quest] complete %s rewards=%s" % [quest_id, rewards])
	quest_completed.emit(quest_id, rewards)

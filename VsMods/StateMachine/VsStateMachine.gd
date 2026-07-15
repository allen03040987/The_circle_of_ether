class_name VsStateMachine
extends Node

var current_state: VsState
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is VsState:
			states[StringName(child.name.to_lower())] = child

## 由 VsPlayer._ready() 呼叫，注入 player 參照並進入初始狀態
func init(player: CharacterBody2D, initial: StringName) -> void:
	for state: VsState in states.values():
		state.player        = player
		state.state_machine = self
	_enter(initial, &"")

func physics_update(delta: float, input: InputState) -> void:
	if not current_state:
		return
	var next := current_state.physics_update(delta, input)
	if next != &"":
		_enter(next, StringName(current_state.name.to_lower()))

func transition_to(target: StringName) -> void:
	if not current_state:
		return
	_enter(target, StringName(current_state.name.to_lower()))

# ── 內部 ─────────────────────────────────────────────────────────────────────
func _enter(target: StringName, prev: StringName) -> void:
	var key := target.to_lower()
	if not states.has(key):
		push_error("VsStateMachine: 找不到狀態 '%s'" % key)
		return
	if current_state and StringName(current_state.name.to_lower()) == key:
		return  # 防止重入
	if current_state:
		current_state.exit()
	current_state = states[key]
	current_state.enter(prev)

class_name VsStateMachine
extends Node

var current_state:      VsState
var current_state_name: StringName = &""
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

## 執行期動態註冊一個新狀態（跟 _ready() 的自動探索寫進同一份 states 字典，
## 只是時機延後）。用於 VsMods 的武藝系統：具體要掛哪個武藝腳本要等
## art_slots（玩家選擇）注入後才知道，沒辦法在場景裡固定成靜態子節點，
## 只能執行期動態 instantiate 再補登記。呼叫端負責把 state 加成子節點
## （`add_child`），這裡只處理 states 字典登記跟欄位注入。
func register_state(state: VsState, player: CharacterBody2D) -> void:
	state.player        = player
	state.state_machine = self
	states[StringName(state.name.to_lower())] = state

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
	current_state      = states[key]
	current_state_name = key
	current_state.enter(prev)

## Rollback 專用：切換狀態但不呼叫 enter/exit，由 restore_state 負責補齊內部數值。
func set_state_quiet(target: StringName) -> void:
	var key := target.to_lower()
	if not states.has(key): return
	current_state      = states[key]
	current_state_name = key

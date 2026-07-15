extends Node2D

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var spawn_point_p1: Node2D = $SpawnPoint_P1
@onready var spawn_point_p2: Node2D = $SpawnPoint_P2
@onready var camera: VsCamera = $Camera2D

var p1:            VsPlayer
var p2:            VsPlayer
var hud:           BattleHud
var round_manager: VsRoundManager

# ── Rollback ──────────────────────────────────────────────────────────────────
const MAX_ROLLBACK_FRAMES := 10
const PHYS_DELTA          := 1.0 / 60.0

## 幀快照：frame → {p1, p2, rm, inp1, inp2}
var _frame_states: Dictionary = {}
## 重模擬中 = true，讓信號處理器跳過 HUD / VFX 副作用
var is_resimulating: bool = false

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if not VsGameManager.selection_confirmed:
		get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")
		return
	if VsNetworkManager.mode == VsNetworkManager.Mode.OFFLINE:
		VsNetworkManager.start_offline()
	_spawn_players()
	_spawn_hud()
	_spawn_round_manager()

func _spawn_players() -> void:
	var scene := preload("res://VsMods/player/VsPlayer.tscn")

	p1 = scene.instantiate()
	p1.player_id = 1
	p1.position  = spawn_point_p1.position
	add_child(p1)
	p1.art_slots.assign(VsGameManager.p1_arts)
	p1.apply_arts_bonus()

	p2 = scene.instantiate()
	p2.player_id = 2
	p2.position  = spawn_point_p2.position
	add_child(p2)
	p2.art_slots.assign(VsGameManager.p2_arts)
	p2.apply_arts_bonus()

	camera.target_p1 = p1
	camera.target_p2 = p2

func _spawn_hud() -> void:
	hud = BattleHud.new()
	add_child(hud)
	hud.init(p1, p2)

func _spawn_round_manager() -> void:
	round_manager = VsRoundManager.new()
	add_child(round_manager)
	round_manager.init(p1, p2, spawn_point_p1.position, spawn_point_p2.position)
	round_manager.round_ended.connect(_on_round_ended)
	round_manager.round_started.connect(_on_round_started)
	round_manager.match_ended.connect(_on_match_ended)

# ── 主循環 ────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	var local_input := InputState.from_input(1)
	var result      := VsNetworkManager.tick(local_input)
	# result 永不為空（rollback 模式永不 stall），但保險起見
	if result.is_empty():
		return

	var cur_frame := VsNetworkManager.get_game_frame() - 1  # tick() 已 +1

	# Rollback：確認輸入與預測不符時，回溯並重模擬
	if VsNetworkManager.needs_rollback():
		var from_frame := VsNetworkManager.consume_rollback_frame()
		_do_rollback(from_frame, cur_frame, result)
		return  # _do_rollback 已把當幀模擬完了

	# 正常幀：先存快照（含當幀輸入），再模擬
	_save_snapshot(cur_frame, result[0], result[1])
	_simulate_frame(delta, result[0], result[1])

# ── Rollback 執行 ─────────────────────────────────────────────────────────────
func _do_rollback(from_frame: int, cur_frame: int, cur_inputs: Array) -> void:
	# 找最近的有效快照（from_frame 或更早）
	var restore_frame := from_frame
	while restore_frame > 0 and not _frame_states.has(restore_frame):
		restore_frame -= 1

	if _frame_states.has(restore_frame):
		_restore_snapshot(restore_frame)

	# 重模擬 restore_frame … cur_frame-1，以確認輸入覆蓋遠端預測
	is_resimulating = true
	var f := restore_frame
	while f < cur_frame:
		if _frame_states.has(f):
			var s: Dictionary = _frame_states[f]
			var i1 := s["inp1"] as InputState
			var i2 := s["inp2"] as InputState
			# 若已收到確認輸入，覆蓋遠端那側（本地那側永遠正確）
			var conf := VsNetworkManager.get_confirmed_remote_input(f)
			if conf:
				if VsNetworkManager.local_player_id == 1:
					i2 = conf   # P2 是遠端
				else:
					i1 = conf   # P1 是遠端
			_simulate_frame(PHYS_DELTA, i1, i2)
			_save_snapshot(f, i1, i2)
		f += 1
	is_resimulating = false

	# 播放當幀
	_save_snapshot(cur_frame, cur_inputs[0], cur_inputs[1])
	_simulate_frame(PHYS_DELTA, cur_inputs[0], cur_inputs[1])

	# 讓動畫跟上重模擬後的狀態
	p1.sync_anim_to_state()
	p2.sync_anim_to_state()

# ── 快照存取 ──────────────────────────────────────────────────────────────────
func _save_snapshot(frame: int, inp1: InputState, inp2: InputState) -> void:
	_frame_states[frame] = {
		"p1":   p1.save_state(),
		"p2":   p2.save_state(),
		"rm":   round_manager.save_state(),
		"inp1": inp1,
		"inp2": inp2,
	}
	# 只保留最近 MAX_ROLLBACK_FRAMES 幀
	_frame_states.erase(frame - MAX_ROLLBACK_FRAMES)

func _restore_snapshot(frame: int) -> void:
	var s: Dictionary = _frame_states[frame]
	p1.restore_state(s["p1"])
	p2.restore_state(s["p2"])
	round_manager.restore_state(s["rm"])

# ── 單幀模擬 ──────────────────────────────────────────────────────────────────
func _simulate_frame(delta: float, inp1: InputState, inp2: InputState) -> void:
	round_manager.tick(delta)
	if not round_manager.is_fighting():
		return
	p1.apply_input(delta, inp1)
	p2.apply_input(delta, inp2)

# ── 回合事件 ──────────────────────────────────────────────────────────────────
func _on_round_ended(winner_id: int) -> void:
	if is_resimulating: return
	hud.show_round_result(winner_id)
	hud.update_wins(round_manager.p1_wins, round_manager.p2_wins)

func _on_round_started(round_num: int) -> void:
	if is_resimulating: return
	hud.show_round_num(round_num)

func _on_match_ended(winner_id: int) -> void:
	if is_resimulating: return
	hud.show_game_over(winner_id)

func _unhandled_input(event: InputEvent) -> void:
	if round_manager and not round_manager.is_fighting() and \
			round_manager.is_game_over() and event.is_pressed():
		VsGameManager.selection_confirmed = false
		get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

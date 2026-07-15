extends Node2D

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var spawn_point_p1: Node2D = $SpawnPoint_P1
@onready var spawn_point_p2: Node2D = $SpawnPoint_P2
@onready var camera: VsCamera = $Camera2D

var p1:            VsPlayer
var p2:            VsPlayer
var hud:           BattleHud
var round_manager: VsRoundManager

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# 若還未在選角畫面確認，回到選角（也兼容直接 F5 執行 vs_world 的開發模式）
	if not VsGameManager.selection_confirmed:
		get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")
		return
	# 離線模式才在這裡初始化；線上模式已在 LobbyScreen 建立連線，不重置
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
	# 本機永遠讀 P1 鍵位（線上模式各自在自己電腦上，離線模式 local_player_id 也是 1）
	var local_input := InputState.from_input(1)
	var result      := VsNetworkManager.tick(local_input)
	if result.is_empty():
		return

	round_manager.tick(delta)

	if not round_manager.is_fighting():
		return  # 回合結算中，凍結玩家

	p1.apply_input(delta, result[0])
	p2.apply_input(delta, result[1])

# ── 回合事件 ──────────────────────────────────────────────────────────────────
func _on_round_ended(winner_id: int) -> void:
	hud.show_round_result(winner_id)
	hud.update_wins(round_manager.p1_wins, round_manager.p2_wins)

func _on_round_started(round_num: int) -> void:
	hud.show_round_num(round_num)

func _on_match_ended(winner_id: int) -> void:
	hud.show_game_over(winner_id)

func _unhandled_input(event: InputEvent) -> void:
	if round_manager and not round_manager.is_fighting() and \
			round_manager.is_game_over() and event.is_pressed():
		VsGameManager.selection_confirmed = false
		get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

extends Node2D

# ── 節點 ─────────────────────────────────────────────────────────────────────
@onready var spawn_point_p1: Node2D = $SpawnPoint_P1
@onready var spawn_point_p2: Node2D = $SpawnPoint_P2
@onready var camera: VsCamera = $Camera2D

var p1:            VsPlayer
var p2:            VsPlayer
var hud:           BattleHud
var round_manager: VsRoundManager

# ── VsMods 暫停 ───────────────────────────────────────────────────────────────
var _vs_paused:     bool         = false
var _pause_overlay: CanvasLayer
var _leaving:       bool         = false   # 避免多個離場信號重複觸發
# 比賽結束後必須等一小段時間才接受「任意鍵返回」，
# 避免致命一擊的那個按鍵還沒放開就立刻跳轉場景
var _accept_return_input: bool   = false

# Signal callable 必須存下來才能在 _exit_tree() 斷開；
# 用 lambda 直接 connect 會無法 disconnect，導致每場對局多一個 dead callable
var _on_forfeit_cb:    Callable
var _on_disconnect_cb: Callable

# ── Rollback ──────────────────────────────────────────────────────────────────
const MAX_ROLLBACK_FRAMES := 20
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
	else:
		# 保留 WebRTC 連線，只清上一場的幀計數 / 輸入殘留
		VsNetworkManager.reset_for_match()
	# 停用主遊戲 PauseMenu，改用 VsMods 自己的暫停
	PauseMenu.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_players()
	_spawn_hud()
	_spawn_round_manager()
	_build_pause_overlay()
	_on_forfeit_cb    = func(): _leave_to_lobby("對方放棄，你獲勝！")
	_on_disconnect_cb = func(): _leave_to_lobby("對方斷線，你獲勝！")
	VsNetworkManager.desync_detected.connect(_on_desync_detected)
	VsNetworkManager.opponent_forfeited.connect(_on_forfeit_cb)
	VsNetworkManager.disconnected.connect(_on_disconnect_cb)

func _exit_tree() -> void:
	# 每場對局結束時主動斷開，防止 dead callable 在 VsNetworkManager 上堆積
	if VsNetworkManager.desync_detected.is_connected(_on_desync_detected):
		VsNetworkManager.desync_detected.disconnect(_on_desync_detected)
	if _on_forfeit_cb.is_valid() and VsNetworkManager.opponent_forfeited.is_connected(_on_forfeit_cb):
		VsNetworkManager.opponent_forfeited.disconnect(_on_forfeit_cb)
	if _on_disconnect_cb.is_valid() and VsNetworkManager.disconnected.is_connected(_on_disconnect_cb):
		VsNetworkManager.disconnected.disconnect(_on_disconnect_cb)
	PauseMenu.process_mode = Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	if _vs_paused:
		return
	var local_input := InputState.from_input(1)
	var result      := VsNetworkManager.tick(local_input, _compute_checksums())
	# result 永不為空（rollback 模式永不 stall），但保險起見
	if result.is_empty():
		return

	var cur_frame := VsNetworkManager.get_game_frame() - 1  # tick() 已 +1

	# Rollback：確認輸入與預測不符時，回溯並重模擬
	if VsNetworkManager.needs_rollback():
		var from_frame := VsNetworkManager.consume_rollback_frame()
		_do_rollback(from_frame, cur_frame, result)
		return  # _do_rollback 已把當幀模擬完了

	# 正常幀：先存快照（含當幀輸入），再模擬（固定 delta 保證兩端算出相同結果）
	_save_snapshot(cur_frame, result[0], result[1])
	_simulate_frame(PHYS_DELTA, result[0], result[1])

# ── Rollback 執行 ─────────────────────────────────────────────────────────────
func _do_rollback(from_frame: int, cur_frame: int, cur_inputs: Array) -> void:
	# 找最近的有效快照（from_frame 或更早）
	var restore_frame := from_frame
	while restore_frame > 0 and not _frame_states.has(restore_frame):
		restore_frame -= 1

	if not _frame_states.has(restore_frame):
		# 快照全部失效（封包遺失超過視窗）→ 無法修復，踢回大廳
		_on_hard_desync()
		return

	_restore_snapshot(restore_frame)

	# 重模擬 restore_frame … cur_frame-1，以確認輸入覆蓋遠端預測
	# 順序必須：先 save_snapshot（存幀 f 開始時的狀態）再 simulate（推進到幀 f 結束）
	# 與正常幀的儲存語意一致，避免每次 rollback 多跑一幀導致位置累積飄移
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
			_save_snapshot(f, i1, i2)           # ← 先存：幀 f 開始時的狀態
			_simulate_frame(PHYS_DELTA, i1, i2) # ← 再推進（內含打擊偵測）
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
	# 打擊偵測統一在此執行（正常幀與 rollback 幀走同一路徑，保證兩端時機一致）
	_check_manual_hits()

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
	_accept_return_input = false
	get_tree().create_timer(0.8).timeout.connect(func(): _accept_return_input = true)

# ── 手動打擊偵測（補足 rollback 中間幀 Area2D 訊號不觸發的缺口）────────────────
func _check_manual_hits() -> void:
	_manual_check(p1.hitbox, p2.hurtbox)
	_manual_check(p2.hitbox, p1.hurtbox)

func _manual_check(hb: VsHitbox, hrb: VsHurtbox) -> void:
	if not hb.monitoring:
		return
	if hb.hit_targets.has(hrb):
		return
	# Rollback 安全防重複：has_hit 存於快照，還原後仍能阻擋同一攻擊窗再次偵測
	if hb.has_hit:
		return
	if _area_rect(hb).intersects(_area_rect(hrb)):
		hb.hit_targets[hrb] = true
		hb.has_hit = true
		hrb.receive_hit(hb)

## 取得 Area2D 第一個 CollisionShape2D 的世界空間 AABB
func _area_rect(area: Area2D) -> Rect2:
	var cs := area.get_child(0) as CollisionShape2D
	if not cs or not (cs.shape is RectangleShape2D):
		return Rect2()
	var size: Vector2 = (cs.shape as RectangleShape2D).size
	return Rect2(cs.global_transform.origin - size * 0.5, size)

## 回傳 [cs_位置, cs_速度, cs_血量能量回合, cs_狀態] 四個獨立雜湊
func _compute_checksums() -> Array:
	if not p1 or not p2:
		return [0, 0, 0, 0]
	var rm_state := round_manager.save_state() if round_manager else {}
	return [
		_fnv([roundi(p1.position.x*100), roundi(p1.position.y*100),
			  roundi(p2.position.x*100), roundi(p2.position.y*100)]),
		_fnv([roundi(p1.velocity.x*100), roundi(p1.velocity.y*100),
			  roundi(p2.velocity.x*100), roundi(p2.velocity.y*100)]),
		# 把回合管理器狀態也一起雜湊，讓回合轉換時的分叉能立即被偵測到
		_fnv([roundi(p1.hp), roundi(p1.energy*10),
			  roundi(p2.hp), roundi(p2.energy*10),
			  rm_state.get("phase", 0) as int,
			  roundi(rm_state.get("timer", 0.0) as float * 100),
			  rm_state.get("p1w", 0) as int,
			  rm_state.get("p2w", 0) as int]),
		(str(p1.state_machine.current_state_name) + "," +
		 str(p2.state_machine.current_state_name)).hash() & 0xFFFFFFFF,
	]

func _fnv(vals: Array) -> int:
	var h: int = 2166136261
	for v: int in vals:
		h = ((h ^ v) * 16777619) & 0xFFFFFFFF
	return h

func _on_desync_detected(frame: int, fields: Array) -> void:
	var lines: Array[String] = [
		"⚠ DESYNC f%d  分叉欄位：[%s]" % [frame, ", ".join(fields)],
		"本機 P1  pos=%s  vel=%s  hp=%.0f  en=%.1f  [%s]" % [
			str(p1.position.snapped(Vector2(0.01,0.01))),
			str(p1.velocity.snapped(Vector2(0.01,0.01))),
			p1.hp, p1.energy, p1.state_machine.current_state_name],
		"本機 P2  pos=%s  vel=%s  hp=%.0f  en=%.1f  [%s]" % [
			str(p2.position.snapped(Vector2(0.01,0.01))),
			str(p2.velocity.snapped(Vector2(0.01,0.01))),
			p2.hp, p2.energy, p2.state_machine.current_state_name],
	]
	push_warning("\n".join(lines))
	if not is_resimulating:
		hud.show_message("DESYNC f%d: %s" % [frame, ", ".join(fields)])

func _on_hard_desync() -> void:
	if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
		VsNetworkManager.send_forfeit()
	_leave_to_lobby("連線中斷，正在返回大廳...")

## 統一離場入口：顯示訊息 → 2 秒後返回大廳
func _leave_to_lobby(msg: String) -> void:
	if _leaving:
		return
	_leaving = true
	_vs_paused = false   # 確保不卡在暫停狀態
	if hud:
		hud.show_message(msg)
	await get_tree().create_timer(2.0).timeout
	VsGameManager.selection_confirmed = false
	get_tree().change_scene_to_file("res://VsMods/ui/LobbyScreen.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_vs_pause()
		return
	# 比賽結束後任意鍵（非 ESC）返回選角；0.8 秒緩衝避免致命鍵未放開就跳轉
	if not _vs_paused and round_manager and not round_manager.is_fighting() and \
			round_manager.is_game_over() and _accept_return_input and event.is_pressed():
		VsGameManager.selection_confirmed = false
		get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

# ── VsMods 暫停選單 ───────────────────────────────────────────────────────────
func _toggle_vs_pause() -> void:
	var showing := !_pause_overlay.visible
	_pause_overlay.visible = showing
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if showing else Input.MOUSE_MODE_CAPTURED
	# 離線才真正凍結模擬；聯機只顯示 overlay，模擬繼續跑（避免兩端不同步）
	if VsNetworkManager.mode == VsNetworkManager.Mode.OFFLINE:
		_vs_paused = showing

func _build_pause_overlay() -> void:
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.layer   = 20   # 在 HUD（layer 10）之上
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	const VIEW_W := 384
	const VIEW_H := 216
	const PW     := 110
	const PH     := 72

	# 半透明全螢幕遮罩
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color        = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.add_child(dim)

	# 面板
	var panel := PanelContainer.new()
	panel.position = Vector2((VIEW_W - PW) / 2, (VIEW_H - PH) / 2)
	panel.size     = Vector2(PW, PH)
	_pause_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                    = "暫停"
	title.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "繼續"
	resume_btn.add_theme_font_size_override("font_size", 10)
	resume_btn.pressed.connect(_toggle_vs_pause)
	vbox.add_child(resume_btn)

	var is_online := VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	var lobby_btn := Button.new()
	lobby_btn.text = "放棄並返回大廳" if is_online else "返回大廳"
	lobby_btn.add_theme_font_size_override("font_size", 10)
	lobby_btn.pressed.connect(func():
		if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
			VsNetworkManager.send_forfeit()
		_leave_to_lobby("正在返回大廳...")
	)
	vbox.add_child(lobby_btn)

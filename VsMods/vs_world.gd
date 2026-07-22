extends Node2D

# ── 節點 ─────────────────────────────────────────────────────────────────────
## SpawnPoint_P1/P2 不再是 vs_world.tscn 的固定節點——場地本身是資料驅動的
## （VsArenaRegistry），這兩個現在指向 _spawn_arena() 掛進 arena_root 的那份
## 場地實例底下的 Marker2D，_ready() 一開始就會設好，晚於這裡才用得到。
var spawn_point_p1: Node2D
var spawn_point_p2: Node2D
@onready var arena_root: Node2D = $ArenaRoot
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

# ── 回合間重選武藝（規則：每回合開打前雙方都能替換最多 2 種已裝備的武藝）──────
## UI 全部搬進 VsMods/ui/ArtsReselectOverlay.tscn/.gd（自成一個場景，可在編輯器
## 排版），這裡只負責在 Phase 轉換時 instantiate/init/free
const ARTS_RESELECT_SCENE := preload("res://VsMods/ui/ArtsReselectOverlay.tscn")
var _ar_overlay: ArtsReselectOverlay

# ── DESYNC 記錄（事件發生時即時寫檔）──────────────────────────────────────────
var _desync_log:       Array[String] = []
var _desync_log_count: int           = 0   # 本場已記錄的事件數（防灌爆檔案）
const DESYNC_LOG_MAX  := 30

# Signal callable 必須存下來才能在 _exit_tree() 斷開；
# 用 lambda 直接 connect 會無法 disconnect，導致每場對局多一個 dead callable
var _on_forfeit_cb:    Callable
var _on_disconnect_cb: Callable

# ── Rollback ──────────────────────────────────────────────────────────────────
const MAX_ROLLBACK_FRAMES := 20
const PHYS_DELTA          := 1.0 / 60.0

## 幀快照：frame → {p1, p2, rm, inp1, inp2}
var _frame_states: Dictionary = {}
## 幀開始時的 checksum 歷史：frame → [cs×4]。
## rollback 重模擬時 _save_snapshot 會覆寫修正，因此 settled 幀的值保證正確。
var _cs_history: Dictionary = {}
## 重模擬中 = true，讓信號處理器跳過 HUD / VFX 副作用
var is_resimulating: bool = false

## 脫手彈道（武藝用，見 VsProjectile.gd）。由 VsPlayer.fire_sword_wave() 這類
## Call Method 動畫軌道呼叫 spawn_projectile() 動態生成，不是場景固定節點。
const PROJECTILE_SCENE := preload("res://VsMods/combat/VsProjectile.tscn")
var projectiles: Array[VsProjectile] = []

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
	# 主遊戲 PauseMenu 的停用/還原範圍是整個 VsMods 流程（title_screen 進入
	# LobbyScreen 時就關、LobbyScreen 返回 title_screen 時才還原），不是這裡
	# ——這裡只是對戰中，如果在這裡開/關會漏掉 LobbyScreen/SelectScreen 這兩段
	# 期間（2026-07-20 實測抓到：大廳畫面按下主遊戲的暫停鍵，主遊戲 PauseMenu
	# 真的跳出來了），見 title_screen.gd::_on_vs_game_pressed()／
	# LobbyScreen.gd::_on_back()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_arena()
	_spawn_players()
	_spawn_hud()
	_spawn_round_manager()
	_build_pause_overlay()
	_on_forfeit_cb    = func(): _leave_to_lobby("對方放棄，你獲勝！")
	_on_disconnect_cb = func(): _leave_to_lobby("對方斷線，你獲勝！")
	VsNetworkManager.desync_detected.connect(_on_desync_detected)
	VsNetworkManager.sync_lost.connect(_on_sync_lost)
	VsNetworkManager.opponent_forfeited.connect(_on_forfeit_cb)
	VsNetworkManager.disconnected.connect(_on_disconnect_cb)
	if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
		VsNetworkManager.remote_arts_received.connect(_on_remote_round_arts)
	_write_startup_log()  # 確認 user:// 可寫入，並讓玩家知道路徑

## 同一台電腦開兩個實例測試時共用 user://，log 必須按本機玩家分檔，
## 否則主機與客戶端的記錄互相交錯，無法對照。
func _desync_log_path() -> String:
	return "user://desync_log_p%d.txt" % VsNetworkManager.local_player_id

func _write_startup_log() -> void:
	var pid     := VsNetworkManager.local_player_id
	var path    := "user://vs_session_p%d.txt" % pid
	var fa      := FileAccess.open(path, FileAccess.WRITE)
	var abs_dir := ProjectSettings.globalize_path("user://")
	if fa:
		fa.store_line("對戰記錄資料夾 = " + abs_dir)
		fa.store_line("DESYNC log = " + abs_dir + "desync_log_p%d.txt" % pid)
		fa.store_line("模式 = " + str(VsNetworkManager.mode))
		fa.store_line("INPUT_DELAY = " + str(VsNetworkManager.INPUT_DELAY))
		fa.close()
	# 每場開頭在 desync log 附加時間戳分隔線（附加模式：最上方=最舊，往下越新）
	_desync_log.append("")
	_desync_log.append("═══ 場次開始 %s  本機=P%d  mode=%d ═══" % [
		Time.get_datetime_string_from_system(), pid, VsNetworkManager.mode])
	_flush_desync_log()
	# Editor 模式下可在「輸出」面板看到此行
	print("[VsMods] user:// 路徑 = ", abs_dir)
	print("[VsMods] DESYNC log = ", abs_dir + "desync_log_p%d.txt" % pid)

func _exit_tree() -> void:
	# 每場對局結束時主動斷開，防止 dead callable 在 VsNetworkManager 上堆積
	if VsNetworkManager.desync_detected.is_connected(_on_desync_detected):
		VsNetworkManager.desync_detected.disconnect(_on_desync_detected)
	if VsNetworkManager.sync_lost.is_connected(_on_sync_lost):
		VsNetworkManager.sync_lost.disconnect(_on_sync_lost)
	if _on_forfeit_cb.is_valid() and VsNetworkManager.opponent_forfeited.is_connected(_on_forfeit_cb):
		VsNetworkManager.opponent_forfeited.disconnect(_on_forfeit_cb)
	if _on_disconnect_cb.is_valid() and VsNetworkManager.disconnected.is_connected(_on_disconnect_cb):
		VsNetworkManager.disconnected.disconnect(_on_disconnect_cb)
	if VsNetworkManager.remote_arts_received.is_connected(_on_remote_round_arts):
		VsNetworkManager.remote_arts_received.disconnect(_on_remote_round_arts)
	# PauseMenu 的還原不在這裡做——這個函式在「回大廳」時也會跑，太早還原
	# 會導致大廳畫面又能叫出主遊戲的暫停選單，見上面 _ready() 的說明
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_flush_desync_log()

func _flush_desync_log() -> void:
	if _desync_log.is_empty():
		return
	# user:// 在匯出版 Windows 對應 %APPDATA%\Godot\app_userdata\<專案名>\
	var path := _desync_log_path()
	# 追加模式：多次 flush（即時 + exit）不覆蓋同一場已有的記錄
	var fa: FileAccess
	if FileAccess.file_exists(path):
		fa = FileAccess.open(path, FileAccess.READ_WRITE)
		if fa:
			fa.seek_end()
	if not fa:
		fa = FileAccess.open(path, FileAccess.WRITE)
	if not fa:
		push_error("無法寫入 desync log：" + path)
		return
	for line: String in _desync_log:
		fa.store_line(line)
	fa.close()
	_desync_log.clear()   # 清空，避免 _exit_tree 重複寫入
	print("DESYNC log 已附加：", ProjectSettings.globalize_path(path))

## 依 VsGameManager.selected_arena_id 動態掛載場地（VsArenaRegistry 查表→
## instantiate→塞進 arena_root），並把場地帶來的重生點/攝影機邊界接回
## spawn_point_p1/p2、camera.limit_*——這幾個原本是 vs_world.tscn 寫死的固定
## 節點/屬性，現在改成場地資料驅動，別的地方（_spawn_players/_spawn_round_manager）
## 完全不用跟著改，只要在這之後執行即可。
func _spawn_arena() -> void:
	var arena_scene := VsArenaRegistry.get_scene(VsGameManager.selected_arena_id)
	var arena := arena_scene.instantiate() as VsArena
	arena_root.add_child(arena)
	spawn_point_p1 = arena.get_node("SpawnPoint_P1") as Node2D
	spawn_point_p2 = arena.get_node("SpawnPoint_P2") as Node2D
	camera.limit_left   = arena.camera_limit_left
	camera.limit_right  = arena.camera_limit_right
	camera.limit_bottom = arena.camera_limit_bottom

func _spawn_players() -> void:
	var p1_scene := VsCharacterRegistry.get_scene(VsGameManager.p1_character)
	var p2_scene := VsCharacterRegistry.get_scene(VsGameManager.p2_character)

	p1 = p1_scene.instantiate()
	p1.player_id = 1
	p1.position  = spawn_point_p1.position
	add_child(p1)
	p1.art_slots.assign(VsGameManager.p1_arts)
	p1.apply_arts_bonus()
	p1._load_arts()

	p2 = p2_scene.instantiate()
	p2.player_id = 2
	p2.position  = spawn_point_p2.position
	add_child(p2)
	p2.art_slots.assign(VsGameManager.p2_arts)
	p2.apply_arts_bonus()
	p2._load_arts()

	# 對手參照：回到 idle 自動面向對方（輔助鎖敵）用
	p1.opponent = p2
	p2.opponent = p1

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
	round_manager.arts_reselect_started.connect(_on_arts_reselect_started)

# ── 主循環 ────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _vs_paused:
		return
	var local_input := InputState.from_input(1)
	# Checksum 只送「已 settled」幀的（雙方都用確認輸入模擬過、不會再被 rollback
	# 改寫），從 _cs_history 讀取——比對「還會變的預測狀態」只會誤報 DESYNC
	var cs_frame := VsNetworkManager.get_settled_frame()
	var cs: Array = []
	if cs_frame >= 0 and _cs_history.has(cs_frame):
		cs = _cs_history[cs_frame]
	else:
		cs_frame = -1
	var result := VsNetworkManager.tick(local_input, cs_frame, cs)
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
		"proj": projectiles.map(func(p: VsProjectile) -> Dictionary:
			var d := p.save_state()
			d["owner"] = p.owner_player.player_id
			return d),
		"inp1": inp1,
		"inp2": inp2,
	}
	# checksum 歷史與快照同步記錄（幀開始時的狀態）；重模擬時同路徑覆寫修正
	_cs_history[frame] = _compute_checksums()
	# 只保留最近 MAX_ROLLBACK_FRAMES 幀；cs 歷史需等對方封包到才比對，留 3 倍窗
	_frame_states.erase(frame - MAX_ROLLBACK_FRAMES)
	_cs_history.erase(frame - 3 * MAX_ROLLBACK_FRAMES)

func _restore_snapshot(frame: int) -> void:
	var s: Dictionary = _frame_states[frame]
	p1.restore_state(s["p1"])
	p2.restore_state(s["p2"])
	round_manager.restore_state(s["rm"])
	_restore_projectiles(s.get("proj", []))

## 重建彈道清單以精確符合快照：直接砍掉現有節點重新生成，比逐一比對增刪
## 簡單可靠——彈道數量少（同時最多幾顆），沒有效能顧慮。
func _restore_projectiles(data: Array) -> void:
	for p: VsProjectile in projectiles:
		p.free()
	projectiles.clear()
	for d: Dictionary in data:
		var owner: VsPlayer = p1 if d["owner"] == 1 else p2
		var proj := _instantiate_projectile(owner)
		proj.restore_state(d)

# ── 單幀模擬 ──────────────────────────────────────────────────────────────────
func _simulate_frame(delta: float, inp1: InputState, inp2: InputState) -> void:
	# 同步給玩家：vfx_* 系列特效輔助函式靠這個旗標擋掉 rollback 重模擬期間的
	# 重複觸發（同一次命中/同一幀衝刺可能因多次 rollback 被重跑好幾遍）
	p1.is_resimulating = is_resimulating
	p2.is_resimulating = is_resimulating
	round_manager.tick(delta, inp1, inp2)
	if not round_manager.is_fighting():
		# AnimationPlayer 是 MANUAL 模式（平時由 VsPlayer.apply_input 推進）；
		# 非戰鬥階段玩家不被模擬，這裡純外觀推進動畫以免畫面凍住。
		# 不屬於模擬狀態：玩家凍結中軌道值不參與任何判定，且回合重置的
		# transition_to 會重播動畫，重模擬跳過這段也不會分歧
		if not is_resimulating:
			p1.anim_player.advance(delta)
			p2.anim_player.advance(delta)
		return
	p1.apply_input(delta, inp1)
	p2.apply_input(delta, inp2)
	# 打擊偵測統一在此執行（正常幀與 rollback 幀走同一路徑，保證兩端時機一致）
	_check_manual_hits(delta)
	_update_projectiles(delta)

# ── 回合事件 ──────────────────────────────────────────────────────────────────
func _on_round_ended(winner_id: int) -> void:
	if is_resimulating: return
	hud.show_round_result(winner_id)
	hud.update_wins(round_manager.p1_wins, round_manager.p2_wins)

func _on_round_started(round_num: int) -> void:
	# 彈道清理是模擬狀態的一部分（跟 VsRoundManager._reset_round() 清判定框同
	# 一類「回合重置=全新開始」語意），resim 也必須照跑，不能被 is_resimulating
	# 擋掉；HUD 更新才是純外觀，才需要擋。之前沒做這段，殘留彈道會飛進新回合
	# ——跟判定框連擊沒清乾淨是同一種「攻擊洩漏」bug，順手一起修掉。
	for proj: VsProjectile in projectiles:
		proj.free()
	projectiles.clear()
	if is_resimulating: return
	if _ar_overlay:
		_ar_overlay.queue_free()
		_ar_overlay = null
	hud.show_round_num(round_num)

func _on_arts_reselect_started() -> void:
	if is_resimulating: return
	if _ar_overlay:
		_ar_overlay.queue_free()
	_ar_overlay = ARTS_RESELECT_SCENE.instantiate() as ArtsReselectOverlay
	add_child(_ar_overlay)
	_ar_overlay.init(p1, p2, round_manager)

## 收到對方這回合的重選結果——只在雙方都在跑的固定倒數視窗內才有意義；
## 直接信任對方送來的陣列已經套用過「最多改 2 種」的規則（送出前
## ArtsReselectOverlay._commit() 已經算過），不用在這裡重算。
func _on_remote_round_arts(arts: Array, _character_id: String) -> void:
	if not round_manager or not round_manager.is_arts_reselect():
		return
	if VsNetworkManager.local_player_id == 1:
		round_manager.p2_new_arts = arts
	else:
		round_manager.p1_new_arts = arts

func _process(_delta: float) -> void:
	# 滑鼠鎖定：比照主遊戲 Player.gd._process() 同款邏輯（按住 Alt 解鎖+顯示，
	# 放開恢復鎖定置中），額外加上「任何浮層開著就不鎖」——回合間重選武藝的
	# 浮層原本沒處理過滑鼠模式，導致滑鼠一直被鎖走看不到、點不到按鈕；暫停
	# 選單原本各自在 _toggle_vs_pause() 手動切一次，現在統一收進這裡每幀判斷，
	# 不用兩處分別維護。
	var overlay_open := (_pause_overlay and _pause_overlay.visible) or _ar_overlay != null
	if overlay_open or Input.is_physical_key_pressed(KEY_ALT):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_match_ended(winner_id: int) -> void:
	if is_resimulating: return
	hud.show_game_over(winner_id)
	_accept_return_input = false
	get_tree().create_timer(0.8).timeout.connect(func(): _accept_return_input = true)

# ── 手動打擊偵測（補足 rollback 中間幀 Area2D 訊號不觸發的缺口）────────────────
func _check_manual_hits(delta: float) -> void:
	for hb: VsHitbox in p1.hitboxes:
		_manual_check(delta, hb, p2.hurtbox, p1, p2)
	for hb: VsHitbox in p2.hitboxes:
		_manual_check(delta, hb, p1.hurtbox, p2, p1)

func _manual_check(delta: float, hb: VsHitbox, hrb: VsHurtbox, hb_owner: VsPlayer, hrb_owner: VsPlayer) -> void:
	hb.tick_cooldown(delta)

	# 連擊已經開始但還沒打完：不受動畫軌道自己的關閉 key 影響，強制保持開啟
	# 直到連擊數用完——動畫上判定框的開關時間點是照單發攻擊設計的，關閉 key
	# 不知道 combo_hits，時間一到就無條件把 monitoring 關掉，後面的連擊永遠打
	# 不到（實測抓到：combo_hits 設 5/10 都只打出 4 下，就是卡在這個固定關閉
	# 時間點；A1 設 2 連擊完全沒有第二下，也是同一個根因，只是視窗更短）。
	if hb.combo_hits > 1 and hb.hits_dealt > 0 and not hb.has_hit:
		hb.monitoring = true
	if not hb.monitoring:
		return
	# Rollback 安全防重複：has_hit（= 連擊全部打完）存於快照，還原後仍能阻擋
	# 同一攻擊窗再次偵測。連擊間隔冷卻中（hit_cooldown_left>0）也先擋下——
	# 1v1 只有一個對手，不用 hit_targets 分目標，連擊靠這兩個欄位控制節奏。
	if hb.has_hit or hb.hit_cooldown_left > 0.0:
		return
	# sticky 且已經鎖定目標：跳過幾何重疊檢查，冷卻時間到就直接算命中（1v1
	# 只有一個對手，鎖定=只認這唯一的目標，不用比對是不是同一顆 hurtbox）。
	# 否則走一般的幾何相交判定（也是 sticky 連擊第一下命中前的必經路徑）。
	var confirmed := (hb.sticky and hb.is_locked) or _sim_rect(hb, hb_owner).intersects(_sim_rect(hrb, hrb_owner))
	if confirmed:
		hb.register_hit()
		hrb.receive_hit(hb)
		if hb.has_hit:
			hb.monitoring = false   # 連擊全部打完，立刻關閉，沒有殘留的必要
		# 打擊回饋：純視覺，命中判定/傷害邏輯完全不受影響。原則上不管霸體/
		# 一般吸收與否都照樣給回饋（「打中了」跟「打中造成多少效果」是兩件
		# 事，比照主遊戲 Hitbox 的做法），但兩個全角色共同例外（使用者規則）：
		# 無敵目標完全不給回饋（音效+火花，攻擊視覺上「根本沒打到」）；防禦
		# 成功目標的火花換成主遊戲同款格擋火花（釘在防禦方身上，不是攻擊方
		# 的角色/hitbox 火花設定）。`receive_hit()` 內 `_on_hurtbox_hurt()` 是
		# 同幀同步呼叫，這裡讀 `hrb_owner.last_hit_outcome` 保證是本次判定的
		# 結果，不是上一次殘留值。
		match hrb_owner.last_hit_outcome:
			VsPlayer.HitOutcome.INVINCIBLE:
				pass
			VsPlayer.HitOutcome.GUARDED:
				hrb_owner.vfx_block_spark()
				hb_owner.vfx_shake(hb.shake_intensity)
				hb_owner.vfx_hit_sfx(hb)
			_:
				hb_owner.vfx_spark(hb, hrb.global_position, hrb_owner)
				hb_owner.vfx_shake(hb.shake_intensity)
				hb_owner.vfx_hit_sfx(hb)

## 生成一顆脫手彈道（VsPlayer.fire_sword_wave() 的 Call Method 軌道呼叫入口）。
## 呼叫時機發生在 apply_input() 內（見 _simulate_frame 順序），本幀稍後的
## _update_projectiles() 就會立刻推進它，跟一般命中判定同一幀生效沒有延遲。
func spawn_projectile(owner: VsPlayer, direction: int) -> VsProjectile:
	var proj := _instantiate_projectile(owner)
	proj.position  = owner.position + Vector2(30.0 * direction, -30.0)   # 出手位置微調，比照主遊戲 c_3_wave
	proj.direction = direction
	proj.scale.x   = direction   # 視覺鏡像；_ready() 時 direction 還是預設值 1，這裡才是真正的方向
	proj.hitbox.direction_override = direction   # 鎖定擊退方向，見 VsHitbox.direction_override 註解
	return proj

func _instantiate_projectile(owner: VsPlayer) -> VsProjectile:
	var proj := PROJECTILE_SCENE.instantiate() as VsProjectile
	add_child(proj)
	proj.owner_player       = owner
	proj.hitbox.owner_player = owner   # 供火花/震動等 vfx 呼叫用
	projectiles.append(proj)
	return proj

## 移動所有存活彈道 + 命中判定 + 收尾銷毀，每幀跑一次（正常幀與 rollback 重模擬
## 幀走同一路徑）。彈道命中判定跟 _manual_check 同一套「settled 幾何 Rect2 相交」
## 手法，只是位置基準換成彈道自己的 position（不是某個 VsPlayer.facing_dir 相對
## 位移），所以另外寫一個 _sim_rect_projectile，不跟 _sim_rect 共用。
func _update_projectiles(delta: float) -> void:
	for proj: VsProjectile in projectiles:
		proj.simulate(delta)
		var target: VsPlayer = p2 if proj.owner_player == p1 else p1
		_manual_check_projectile(delta, proj, target)

	# 收尾：命中或超出射程的彈道本幀移除（先判定完才砍，不影響本幀已經算好的結果）
	var i := projectiles.size() - 1
	while i >= 0:
		if projectiles[i].should_despawn():
			var dead := projectiles[i]
			projectiles.remove_at(i)
			dead.free()
		i -= 1

func _manual_check_projectile(delta: float, proj: VsProjectile, hrb_owner: VsPlayer) -> void:
	var hb := proj.hitbox
	hb.tick_cooldown(delta)
	# 跟 _manual_check 同一套防呆：連擊已開始但還沒打完，不讓別的東西關掉 monitoring
	if hb.combo_hits > 1 and hb.hits_dealt > 0 and not hb.has_hit:
		hb.monitoring = true
	if not hb.monitoring or hb.has_hit or hb.hit_cooldown_left > 0.0:
		return
	var hrb := hrb_owner.hurtbox
	var confirmed := (hb.sticky and hb.is_locked) or _sim_rect_projectile(hb, proj).intersects(_sim_rect(hrb, hrb_owner))
	if confirmed:
		hb.register_hit()
		hrb.receive_hit(hb)
		# 打擊回饋例外規則跟 _manual_check 同一套，見該處註解
		match hrb_owner.last_hit_outcome:
			VsPlayer.HitOutcome.INVINCIBLE:
				pass
			VsPlayer.HitOutcome.GUARDED:
				hrb_owner.vfx_block_spark()
				proj.owner_player.vfx_shake(hb.shake_intensity)
				proj.owner_player.vfx_hit_sfx(hb)
			_:
				proj.owner_player.vfx_spark(hb, hrb.global_position, hrb_owner)
				proj.owner_player.vfx_shake(hb.shake_intensity)
				proj.owner_player.vfx_hit_sfx(hb)

## 比照 _sim_rect，但基準點是彈道自己的 position（不是某個 VsPlayer 的
## facing_dir 相對位移）——彈道在世界空間直線飛行，用 proj.direction 決定
## hitbox 局部偏移的左右鏡像。
func _sim_rect_projectile(hb: VsHitbox, proj: VsProjectile) -> Rect2:
	var cs := hb.get_child(0) as CollisionShape2D
	if not cs or not (cs.shape is RectangleShape2D):
		return Rect2()
	var size: Vector2 = (cs.shape as RectangleShape2D).size
	var offset := hb.position + cs.position
	var world_pos := Vector2(
		proj.position.x + offset.x * proj.direction,
		proj.position.y + offset.y
	)
	return Rect2(world_pos - size * 0.5, size)

## desync log 用：列出玩家所有判定框的 monitoring/has_hit（開著的才列，全關顯示 "-"）
func _hb_summary(p: VsPlayer) -> String:
	var parts: Array[String] = []
	for hb: VsHitbox in p.hitboxes:
		if hb.monitoring or hb.has_hit:
			parts.append("%s mon=%s hit=%s" % [hb.name, str(hb.monitoring), str(hb.has_hit)])
	return "-" if parts.is_empty() else "; ".join(parts)

## 從模擬狀態直接計算 Area2D 的世界空間 AABB，完全不依賴 scene tree global_transform。
## 根本原因：rollback 重模擬中間幀，Godot 不保證 global_transform 在 move_and_slide()
## 後立刻更新子節點的快取，導致兩端在邊界命中時算出不同位置。
## 公式：world_x = owner.position.x + (area.pos.x + cs.pos.x) * facing_dir
##        world_y = owner.position.y + (area.pos.y + cs.pos.y)
## 假設 Graphics 節點 position=(0,0)（由 VsPlayer.tscn 確認）。
func _sim_rect(area: Area2D, owner: VsPlayer) -> Rect2:
	var cs := area.get_child(0) as CollisionShape2D
	if not cs or not (cs.shape is RectangleShape2D):
		return Rect2()
	var size: Vector2 = (cs.shape as RectangleShape2D).size
	var offset := area.position + cs.position   # Graphics 空間內的總偏移
	var world_pos := Vector2(
		owner.position.x + offset.x * owner.facing_dir,
		owner.position.y + offset.y
	)
	return Rect2(world_pos - size * 0.5, size)

## 回傳 [cs_位置, cs_速度, cs_血量能量回合, cs_狀態] 四個獨立雜湊
func _compute_checksums() -> Array:
	if not p1 or not p2:
		return [0, 0, 0, 0]
	var rm_state := round_manager.save_state() if round_manager else {}
	# 彈道數量/座標一起併進位置雜湊——脫手彈道也是需要兩端一致的模擬狀態，
	# 數量或位置分歧（例如某一端漏生成/漏移動一顆）要能被 desync 偵測抓到
	var proj_vals: Array = [projectiles.size()]
	for proj: VsProjectile in projectiles:
		proj_vals.append(roundi(proj.position.x * 100))
		proj_vals.append(roundi(proj.position.y * 100))
	return [
		_fnv([roundi(p1.position.x*100), roundi(p1.position.y*100),
			  roundi(p2.position.x*100), roundi(p2.position.y*100)] + proj_vals),
		_fnv([roundi(p1.velocity.x*100), roundi(p1.velocity.y*100),
			  roundi(p2.velocity.x*100), roundi(p2.velocity.y*100)]),
		# 把回合管理器狀態與面向方向一起雜湊
		_fnv([roundi(p1.hp), roundi(p1.arts_energy*10), roundi(p1.dash_energy*10),
			  roundi(p2.hp), roundi(p2.arts_energy*10), roundi(p2.dash_energy*10),
			  p1.facing_dir, p2.facing_dir,
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
	_desync_log_count += 1
	if _desync_log_count > DESYNC_LOG_MAX:
		return   # 已記錄足夠樣本；持續分歧由 sync_lost 收尾
	var snap := Vector2(0.01, 0.01)
	var lines: Array[String] = [
		"=== DESYNC f%d  分叉欄位：[%s] ===" % [frame, ", ".join(fields)],
		"P1 pos=%s vel=%s hp=%.1f arts=%.1f dash=%.1f facing=%d inv=%.2f pda=%.2f [%s]" % [
			str(p1.position.snapped(snap)), str(p1.velocity.snapped(snap)),
			p1.hp, p1.arts_energy, p1.dash_energy,
			p1.facing_dir, p1.invincible_time_left, p1.post_dash_armor_left,
			str(p1.state_machine.current_state_name)],
		"P2 pos=%s vel=%s hp=%.1f arts=%.1f dash=%.1f facing=%d inv=%.2f pda=%.2f [%s]" % [
			str(p2.position.snapped(snap)), str(p2.velocity.snapped(snap)),
			p2.hp, p2.arts_energy, p2.dash_energy,
			p2.facing_dir, p2.invincible_time_left, p2.post_dash_armor_left,
			str(p2.state_machine.current_state_name)],
		"P1_HB [%s]  P2_HB [%s]" % [_hb_summary(p1), _hb_summary(p2)],
	]
	# ↑上面是「偵測當下」的即時狀態；↓下面是「分歧那一幀」的封存快照——
	# 兩台機器各自對照同一幀的快照，才能定位是輸入對幀錯還是模擬分歧
	var s: Dictionary = _frame_states.get(frame, {})
	if not s.is_empty():
		var sp1: Dictionary = s["p1"]
		var sp2: Dictionary = s["p2"]
		var b1: PackedByteArray = (s["inp1"] as InputState).to_bytes()
		var b2: PackedByteArray = (s["inp2"] as InputState).to_bytes()
		lines.append("f%d快照 P1 pos=%s vel=%s [%s]  P2 pos=%s vel=%s [%s]" % [
			frame,
			str((sp1["pos"] as Vector2).snapped(snap)), str((sp1["vel"] as Vector2).snapped(snap)),
			str(sp1["sname"]),
			str((sp2["pos"] as Vector2).snapped(snap)), str((sp2["vel"] as Vector2).snapped(snap)),
			str(sp2["sname"])])
		lines.append("f%d輸入 in1=%02X%02X in2=%02X%02X" % [frame, b1[0], b1[1], b2[0], b2[1]])
	else:
		lines.append("f%d快照已不在視窗內（目前幀 %d）" % [frame, VsNetworkManager.get_game_frame()])
	lines.append("預測深度=%d  近期rollback[起點,執行幀]=%s" % [
		VsNetworkManager.get_prediction_depth(),
		str(VsNetworkManager.get_recent_rollbacks())])
	_desync_log.append_array(lines)
	_desync_log.append("")   # 空行分隔
	push_warning("\n".join(lines))
	_flush_desync_log()   # 即時寫檔，防止崩潰或強制關閉遺失記錄
	if not is_resimulating:
		hud.show_message("DESYNC f%d: %s" % [frame, ", ".join(fields)])

func _on_hard_desync() -> void:
	if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
		VsNetworkManager.send_forfeit()
	_leave_to_lobby("連線中斷，正在返回大廳...")

## checksum 連續分歧超過閾值（≈2 秒）：狀態已無法收斂，雙方各自偵測、各自離場
func _on_sync_lost() -> void:
	_flush_desync_log()
	_leave_to_lobby("偵測到嚴重不同步，本場作廢，返回大廳...")

## 統一離場入口：顯示訊息 → 2 秒後返回大廳。
## `instant=true` 跳過訊息與等待、立刻切場景——玩家自己主動按「返回大廳」屬於
## 這種：訊息是給「被動離場」（對方棄權/斷線/desync）的情況看的，讓玩家在畫面
## 消失前看懂發生了什麼事；主動點擊的按鈕玩家自己知道要離開，不需要這段緩衝，
## 之前不分青紅皂白全部套用 2 秒等待，被使用者抓出來是不必要的等待。
func _leave_to_lobby(msg: String, instant: bool = false) -> void:
	if _leaving:
		return
	_leaving = true
	_vs_paused = false   # 確保不卡在暫停狀態
	if instant:
		VsGameManager.selection_confirmed = false
		get_tree().change_scene_to_file("res://VsMods/ui/LobbyScreen.tscn")
		return
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
	# 滑鼠模式改由 _process() 每幀統一判斷（overlay_open 檢查），這裡不用再管
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
		_leave_to_lobby("", true)
	)
	vbox.add_child(lobby_btn)

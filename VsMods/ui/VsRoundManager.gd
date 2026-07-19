class_name VsRoundManager
extends Node
## 回合管理器（三戰兩勝）
## tick() 由 vs_world 每物理幀呼叫；
## 回合結束時凍結玩家輸入（vs_world 透過 is_fighting() 判斷）。

# ── 設定 ──────────────────────────────────────────────────────────────────────
const ROUNDS_TO_WIN          := 2     # 先贏幾場者得勝
const ROUND_END_DELAY        := 2.0   # 回合結算停頓（秒）
## 重選武藝階段上限時長——雙方都按確認可以提早結束（見 p1_confirmed/
## p2_confirmed），沒人管的話（例如有人 AFK）到時間也會強制進下一回合，避免卡死。
const ARTS_RESELECT_DURATION := 30.0

# ── 訊號 ──────────────────────────────────────────────────────────────────────
signal round_ended(winner_id: int)    # 0=平手, 1=P1勝, 2=P2勝
signal round_started(round_num: int)
signal match_ended(winner_id: int)    # 1=P1, 2=P2
signal arts_reselect_started()

# ── 狀態 ──────────────────────────────────────────────────────────────────────
enum Phase { FIGHTING, ROUND_END, ARTS_RESELECT, GAME_OVER }

var p1_wins:   int   = 0
var p2_wins:   int   = 0
var round_num: int   = 1
var phase:     Phase = Phase.FIGHTING

## 重選武藝階段收集的新裝備（由 vs_world 的 UI 流程直接寫入）。空陣列＝維持
## 原本裝備不變。**刻意不進 save_state()/restore_state()**：這兩個欄位是靠
## 場外可靠管道（WS，同開賽前選角那套）在雙方之間同步好的「已敲定」值，
## rollback 重模擬同一段時間只會讀到同一個已敲定值，不需要、也不應該當成
## 逐幀預測狀態處理。
var p1_new_arts: Array = []
var p2_new_arts: Array = []

## 重選武藝階段的「確認」狀態——**這兩個要進 save_state()/restore_state()**，
## 跟 p1_new_arts/p2_new_arts 不同：它們是由 InputState.confirm（走一般輸入
## 延遲＋rollback 管線）逐幀累積出來的確定性模擬狀態，不是場外預先敲定好的
## 值，必須跟其他遊戲狀態一樣參與快照還原，見 _tick_arts_reselect() 註解。
var p1_confirmed: bool = false
var p2_confirmed: bool = false

var _timer: float = 0.0
var _p1:    VsPlayer
var _p2:    VsPlayer
var _sp1:   Vector2
var _sp2:   Vector2

# ── 初始化 ────────────────────────────────────────────────────────────────────
func init(p1: VsPlayer, p2: VsPlayer, spawn_p1: Vector2, spawn_p2: Vector2) -> void:
	_p1  = p1
	_p2  = p2
	_sp1 = spawn_p1
	_sp2 = spawn_p2

func is_fighting() -> bool:
	return phase == Phase.FIGHTING

func is_game_over() -> bool:
	return phase == Phase.GAME_OVER

func is_arts_reselect() -> bool:
	return phase == Phase.ARTS_RESELECT

func arts_reselect_time_left() -> float:
	return _timer

func save_state() -> Dictionary:
	return {
		"phase":    phase,
		"p1w":      p1_wins,
		"p2w":      p2_wins,
		"round":    round_num,
		"timer":    _timer,
		"p1c":      p1_confirmed,
		"p2c":      p2_confirmed,
	}

func restore_state(s: Dictionary) -> void:
	phase        = s["phase"] as Phase
	p1_wins      = s["p1w"]
	p2_wins      = s["p2w"]
	round_num    = s["round"]
	_timer       = s["timer"]
	p1_confirmed = s.get("p1c", false)
	p2_confirmed = s.get("p2c", false)

# ── 主循環（由 vs_world 每物理幀呼叫）────────────────────────────────────────
func tick(delta: float, inp1: InputState, inp2: InputState) -> void:
	match phase:
		Phase.FIGHTING:       _tick_fighting()
		Phase.ROUND_END:      _tick_round_end(delta)
		Phase.ARTS_RESELECT:  _tick_arts_reselect(delta, inp1, inp2)
		Phase.GAME_OVER:      pass

# ── 戰鬥中：偵測死亡 ─────────────────────────────────────────────────────────
func _tick_fighting() -> void:
	var p1_dead := _p1.hp <= 0.0
	var p2_dead := _p2.hp <= 0.0
	if not p1_dead and not p2_dead:
		return

	# 計算回合勝者
	var winner := 0
	if   p1_dead and not p2_dead: winner = 2
	elif p2_dead and not p1_dead: winner = 1
	# 平手：兩人同時倒地，雙方各得一分

	if winner == 1 or winner == 0: p1_wins += 1
	if winner == 2 or winner == 0: p2_wins += 1

	_p1.hp = maxf(_p1.hp, 0.0)
	_p2.hp = maxf(_p2.hp, 0.0)

	# 死亡演出（規則：死亡→撥放動畫）：倒下收場。在模擬路徑內執行→確定性安全；
	# ROUND_END 期間玩家凍結不再推進狀態，動畫由 vs_world 純外觀播完。
	# TODO: 換成專屬死亡動畫（目前用倒地的 launched 動畫代位）
	if p1_dead and not (_p1.state_machine.current_state is VsKnockdown or _p1.state_machine.current_state is VsLaunched):
		_p1.state_machine.transition_to(&"vsknockdown")
	if p2_dead and not (_p2.state_machine.current_state is VsKnockdown or _p2.state_machine.current_state is VsLaunched):
		_p2.state_machine.transition_to(&"vsknockdown")

	phase  = Phase.ROUND_END
	_timer = ROUND_END_DELAY
	round_ended.emit(winner)

# ── 回合結算倒計時 ────────────────────────────────────────────────────────────
func _tick_round_end(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return

	# 比賽結束？
	if p1_wins >= ROUNDS_TO_WIN or p2_wins >= ROUNDS_TO_WIN:
		phase = Phase.GAME_OVER
		var match_winner := 1 if p1_wins >= p2_wins else 2
		match_ended.emit(match_winner)
		return

	# 比賽還沒結束：先進「重選武藝」階段，不直接開下一回合
	phase = Phase.ARTS_RESELECT
	_timer = ARTS_RESELECT_DURATION
	p1_new_arts  = []
	p2_new_arts  = []
	p1_confirmed = false
	p2_confirmed = false
	arts_reselect_started.emit()

## 重選武藝倒數＋確認。轉場條件：時間到，**或**雙方都按過確認鍵。
## ⚠ 確認鍵走 InputState.confirm（跟其他戰鬥輸入同一份 rollback 管線），
## 不是直接讀 UI 按鈕點擊的當下時間去觸發轉場——原因：「雙方都確認了」這件事
## 如果用場外 WS 訊息到達時間判斷，兩端收到確認的真實時間點必有網路延遲落差，
## 若拿它直接觸發階段轉換，兩端離開這個 phase 的模擬幀號就會不一致，後續
## _reset_round() 的位置/血量重置等模擬狀態會在不同幀發生 → checksum 分歧。
## 走輸入管線就自動獲得跟其他輸入一樣的確定性保證：InputState.confirm 是
## 逐幀帶延遲＋預測＋rollback 修正送到兩端的，p1_confirmed/p2_confirmed 兩端
## 保證在同一個模擬幀被設成 true，轉場時機因此天然同步。
## p1_new_arts/p2_new_arts（場外 WS 交換）只要在整個視窗內完成即可，讀取時機
## 已經是兩端都確認過後，不受這裡的時序影響。
func _tick_arts_reselect(delta: float, inp1: InputState, inp2: InputState) -> void:
	if inp1.confirm: p1_confirmed = true
	if inp2.confirm: p2_confirmed = true
	_timer -= delta
	if _timer > 0.0 and not (p1_confirmed and p2_confirmed):
		return
	round_num += 1
	_reset_round()
	phase = Phase.FIGHTING
	round_started.emit(round_num)

# ── 重置回合 ──────────────────────────────────────────────────────────────────
func _reset_round() -> void:
	for vs: VsPlayer in [_p1, _p2]:
		vs.hp              = vs.max_hp
		vs.arts_energy     = vs.max_arts_energy
		vs.dash_energy     = vs.max_dash_energy
		vs.post_dash_armor_left = 0.0
		vs.ukemi_uses_left = VsPlayer.UKEMI_MAX_USES
		vs.velocity        = Vector2.ZERO
		vs.pending_hit     = {}
		vs.invincible_time_left = 0.5   # 開局 0.5s 無敵，避免立即被打

	_p1.position = _sp1
	_p2.position = _sp2

	# 強制回 Idle（可能停在 Hurt/Knockdown 狀態）
	_p1.state_machine.transition_to(&"vsidle")
	_p2.state_machine.transition_to(&"vsidle")

	# 換裝重選的武藝（若這回合有選新的；空陣列＝維持原裝備不變）。必須放在上面
	# transition_to(&"vsidle") 之後——這樣才能保證 current_state 不會是任何
	# VsMartialArt 節點，reload_arts() 移除舊節點才不會留下懸空的 current_state
	# 參照（見 VsPlayer.reload_arts() 註解）。
	if not p1_new_arts.is_empty():
		_p1.reload_arts(p1_new_arts)
	if not p2_new_arts.is_empty():
		_p2.reload_arts(p2_new_arts)

	# 硬重置雙方所有判定框（monitoring/hits_dealt/is_locked 全清）——不能只靠
	# 上面 transition_to(&"vsidle") 觸發的 exit()：sticky 連擊沒打完時，
	# exit() 刻意不強制關閉（讓連段自己跑完，見 VsHitbox.close_on_state_exit()
	# 完整說明），這是遊戲進行中合理的設計；但「回合」是更高一層的邊界，
	# 上一回合沒打完的連擊不該續到下一回合（例如靠一次多段連擊終結對手，
	# 沒打完的那幾下不該在新回合開場就補上），所以這裡不管 exit() 有沒有放行
	# sticky，一律當作全新開始強制清空。
	for vs: VsPlayer in [_p1, _p2]:
		for hb: VsHitbox in vs.hitboxes:
			hb.monitoring = false
			hb.reset_hits()

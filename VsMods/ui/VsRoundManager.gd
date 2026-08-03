class_name VsRoundManager
extends Node
## 回合管理器（三戰兩勝）
## tick() 由 vs_world 每物理幀呼叫；
## 回合結束時凍結玩家輸入（vs_world 透過 is_fighting() 判斷）。

# ── 設定 ──────────────────────────────────────────────────────────────────────
const ROUNDS_TO_WIN          := 2     # 先贏幾場者得勝
const ROUND_END_DELAY        := 2.0   # 回合結算停頓（秒）
const ROUND_TIME_LIMIT        := 60.0  # 單回合時限（秒），時間到血多的一方獲勝
## 重選武藝階段上限時長——雙方都按確認可以提早結束（見 p1_confirmed/
## p2_confirmed），沒人管的話（例如有人 AFK）到時間也會強制進下一回合，避免卡死。
const ARTS_RESELECT_DURATION := 30.0

# ── 訊號 ──────────────────────────────────────────────────────────────────────
signal round_ended(winner_id: int)    # 0=平手, 1=P1勝, 2=P2勝
signal round_started(round_num: int)
signal match_ended(winner_id: int)    # 1=P1, 2=P2
signal arts_reselect_started()
## 敗北運鏡子階段切換（見下方 RoundEndStage）。vs_world 連接這個訊號、在
## handler 開頭擋 is_resimulating（跟 round_ended/round_started 同一套既有
## 慣例）觸發實際的鏡頭特寫呼叫——訊號本身在 resim 期間一樣會重複 emit
## （tick() 是確定性模擬碼，resim 重跑到同一幀就會再次觸發同一個轉場），
## 副作用防重複的責任在 handler，不在這裡。
signal round_end_stage_changed(stage: int)

# ── 狀態 ──────────────────────────────────────────────────────────────────────
enum Phase { FIGHTING, ROUND_END, ARTS_RESELECT, GAME_OVER }

## ROUND_END 期間的運鏡子階段（2026-08-01，敗北演出優化）：
## PLAIN——沒有單一勝負可特寫的情況（時間到、或雙方同時倒地平手），維持原本
##   「等敗北動畫播完＋ROUND_END_DELAY」的樸素流程，不觸發任何運鏡/時緩。
## LOSER_CLOSEUP——真正有人被打死（非時間到）才進來：特寫敗方 CLOSEUP_DURATION
##   秒，同時整場模擬用 TIME_SLOW_RATE 慢動作播放（見 sim_delta_scale()）——
##   這段時間敗方的死亡/倒地動畫應該正在慢動作播放。
## WAIT_LANDING——退出特寫+慢動作，恢復正常速度，純粹等敗北動畫真正播完
##   （_defeat_wait_done()，跟原本 PLAIN 分支等待的邏輯一樣，只是移到這個
##   子階段）。
## WINNER_CLOSEUP——敗北動畫確定播完後，特寫勝方 CLOSEUP_DURATION 秒；這段
##   計時器一到就直接接原本「比賽結束/進重選」的收尾，等同取代了原本的
##   ROUND_END_DELAY（不再額外疊加一次）。
enum RoundEndStage { PLAIN, LOSER_CLOSEUP, WAIT_LANDING, WINNER_CLOSEUP }
const CLOSEUP_DURATION := 2.0    # 敗方/勝方特寫各自維持的秒數
const TIME_SLOW_RATE   := 0.45   # LOSER_CLOSEUP 期間模擬 delta 的縮放比例（慢動作，2026-08-01 從 0.25 調低）

var p1_wins:   int   = 0
var p2_wins:   int   = 0
var round_num: int   = 1
var phase:     Phase = Phase.FIGHTING
var round_time_left: float = ROUND_TIME_LIMIT   ## 本回合剩餘秒數，_reset_round() 重置

var round_end_stage:  RoundEndStage = RoundEndStage.PLAIN
var round_end_winner: int = 0   ## LOSER_CLOSEUP/WINNER_CLOSEUP 特寫目標依據：1=P1, 2=P2

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

## 這次進 ROUND_END 是不是「時間到」觸發的（而非有人死亡）——_tick_round_end()
## 靠這個決定要不要等待敗北動畫播完才開始倒數 ROUND_END_DELAY：時間到沒有人
## 真的被打死，沒有動畫要等，直接倒數即可（使用者明確要求「因時間敗北就不必
## 動畫」）。跟 round_time_left 不同，這個純粹是旗標，不需要精確數值。
var _time_based_end: bool = false

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
		"rtl":      round_time_left,
		"p1c":      p1_confirmed,
		"p2c":      p2_confirmed,
		"tbe":      _time_based_end,
		"res":      round_end_stage,
		"rew":      round_end_winner,
	}

func restore_state(s: Dictionary) -> void:
	phase        = s["phase"] as Phase
	p1_wins      = s["p1w"]
	p2_wins      = s["p2w"]
	round_num    = s["round"]
	_timer       = s["timer"]
	round_time_left = s.get("rtl", ROUND_TIME_LIMIT)
	p1_confirmed = s.get("p1c", false)
	p2_confirmed = s.get("p2c", false)
	_time_based_end = s.get("tbe", false)
	round_end_stage  = s.get("res", RoundEndStage.PLAIN) as RoundEndStage
	round_end_winner = s.get("rew", 0)

# ── 主循環（由 vs_world 每物理幀呼叫）────────────────────────────────────────
func tick(delta: float, inp1: InputState, inp2: InputState) -> void:
	match phase:
		Phase.FIGHTING:       _tick_fighting(delta)
		Phase.ROUND_END:      _tick_round_end(delta)
		Phase.ARTS_RESELECT:  _tick_arts_reselect(delta, inp1, inp2)
		Phase.GAME_OVER:      pass

# ── 戰鬥中：偵測死亡／時間到 ─────────────────────────────────────────────────
func _tick_fighting(delta: float) -> void:
	round_time_left = maxf(round_time_left - delta, 0.0)

	var p1_dead := _p1.hp <= 0.0
	var p2_dead := _p2.hp <= 0.0
	var time_up := round_time_left <= 0.0 and not p1_dead and not p2_dead
	if not p1_dead and not p2_dead and not time_up:
		return

	# 計算回合勝者
	var winner := 0
	if time_up:
		# 時間到：血量多的一方獲勝；血量一致算平手（雙方都算贏，走跟下面
		# 「兩人同時倒地」同一套 winner==0 慣例，不用另外處理）
		if   _p1.hp > _p2.hp: winner = 1
		elif _p2.hp > _p1.hp: winner = 2
	else:
		if   p1_dead and not p2_dead: winner = 2
		elif p2_dead and not p1_dead: winner = 1
		# 平手：兩人同時倒地，雙方各得一分

	if winner == 1 or winner == 0: p1_wins += 1
	if winner == 2 or winner == 0: p2_wins += 1

	_p1.hp = maxf(_p1.hp, 0.0)
	_p2.hp = maxf(_p2.hp, 0.0)

	# 死亡演出：時間到不強制任何一方倒地——沒有人真的被打死，血量還在，維持
	# 原本站姿/動作即可（也不需要等任何敗北動畫，_tick_round_end() 靠
	# _time_based_end 判斷）。真的死亡則依死亡當下的狀態分流，見 _route_defeat()。
	# 在模擬路徑內執行→確定性安全；ROUND_END 期間玩家的動作/物理會繼續自然
	# 播完，不是凍結。
	_time_based_end = time_up
	if not time_up:
		if p1_dead:
			_p1.is_defeated = true
			_route_defeat(_p1)
		if p2_dead:
			_p2.is_defeated = true
			_route_defeat(_p2)

	phase = Phase.ROUND_END

	# 敗北運鏡（2026-08-01）：只有「真的打死對手、不是時間到、而且有單一
	# 勝負」才進特寫流程——雙方同時倒地平手沒有單一敗方可以特寫，跟時間到
	# 一樣退回原本樸素的 PLAIN 流程（等敗北動畫播完+ROUND_END_DELAY）。
	if not time_up and winner != 0:
		var loser := _p2 if winner == 1 else _p1
		round_end_winner = winner
		if loser.died_from_hazard:
			# 場地機關（目前只有懸崖）害死的——kill_instantly() 沒有正常命中/
			# 硬直可看，特寫敗方沒意義，直接跳過 LOSER_CLOSEUP（連帶跳過慢動作，
			# sim_delta_scale() 只在這個子階段生效），進 WAIT_LANDING 純等
			# 敗北動畫（"did"）播完，只保留勝方特寫。
			round_end_stage = RoundEndStage.WAIT_LANDING
		else:
			round_end_stage = RoundEndStage.LOSER_CLOSEUP
			_timer = CLOSEUP_DURATION
	else:
		round_end_stage  = RoundEndStage.PLAIN
		round_end_winner = 0
		_timer = ROUND_END_DELAY
	round_end_stage_changed.emit(round_end_stage)

	round_ended.emit(winner)

## LOSER_CLOSEUP 期間整場模擬要用的 delta 縮放比例——由 vs_world._simulate_frame()
## 讀取，只影響 apply_input()/打擊判定/彈道/機關（角色動畫、位移都用模擬
## delta 推進，縮小 delta 就是慢動作），不影響 tick() 本身的階段計時器（那個
## 永遠用未縮放的 delta，「2秒」是實際秒數，不會被慢動作拉長）。純粹是
## _round_end_stage 的確定性函數，兩端算出的縮放值保證一致，rollback 安全。
func sim_delta_scale() -> float:
	if phase == Phase.ROUND_END and round_end_stage == RoundEndStage.LOSER_CLOSEUP:
		return TIME_SLOW_RATE
	return 1.0

## 依死亡當下的狀態決定播哪條敗北演出：VsLaunched（擊飛中）或已經在
## VsKnockdown（倒地流程進行中）——保留原本的路徑不強制打斷，讓它自然落地，
## VsKnockdown 二次落地時會自己偵測 is_defeated 改播 launched_3 定格（見
## VsKnockdown.gd）。其餘所有情況（VsHurt 硬直、或任何被霸體吸收硬直但傷害
## 致命的狀態，例如攻擊/防禦/武藝中被打死）一律直接轉進 vsdefeated 播 "did"，
## 完全跳過整套倒地流程。
func _route_defeat(vs: VsPlayer) -> void:
	var cur := vs.state_machine.current_state
	if cur is VsLaunched or cur is VsKnockdown:
		return
	vs.state_machine.transition_to(&"vsdefeated")

# ── 回合結算倒計時 ────────────────────────────────────────────────────────────
## 依 round_end_stage 分流：
## - PLAIN（時間到/平手）：原本的樸素流程——等敗北動畫播完（沒人死就直接過）
##   再倒數 ROUND_END_DELAY。
## - LOSER_CLOSEUP：特寫敗方+慢動作固定播 CLOSEUP_DURATION 秒（不等動畫，
##   時間到就切下一階段——慢動作期間動畫本來就播得比較慢，這段本身就是
##   「讓玩家看清楚敗北瞬間」的固定演出時長，不是等待窗口）。
## - WAIT_LANDING：退出特寫+恢復正常速度，這裡才是真正等敗北動畫播完
##   （_defeat_wait_done()，跟 PLAIN 分支等的是同一件事，只是換了時機）。
## - WINNER_CLOSEUP：特寫勝方固定 CLOSEUP_DURATION 秒，時間到直接接下面
##   共用的「比賽結束/進重選」收尾——取代原本的 ROUND_END_DELAY，不會兩個
##   都算。
func _tick_round_end(delta: float) -> void:
	match round_end_stage:
		RoundEndStage.PLAIN:
			if not _defeat_wait_done():
				return
			_timer -= delta
			if _timer > 0.0:
				return
		RoundEndStage.LOSER_CLOSEUP:
			_timer -= delta
			if _timer > 0.0:
				return
			round_end_stage = RoundEndStage.WAIT_LANDING
			round_end_stage_changed.emit(round_end_stage)
			return
		RoundEndStage.WAIT_LANDING:
			if not _defeat_wait_done():
				return
			round_end_stage = RoundEndStage.WINNER_CLOSEUP
			_timer = CLOSEUP_DURATION
			round_end_stage_changed.emit(round_end_stage)
			return
		RoundEndStage.WINNER_CLOSEUP:
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

## 沒死的一方不用等（not is_defeated 直接算過關）；死亡的一方要等
## defeat_settled（VsDefeated 播完 "did"，或 VsKnockdown 敗北分支定格
## launched_3 那一刻）才算過關。雙方都過關才能開始倒數 ROUND_END_DELAY。
func _defeat_wait_done() -> bool:
	if _time_based_end:
		return true
	var p1_ok := not _p1.is_defeated or _p1.defeat_settled
	var p2_ok := not _p2.is_defeated or _p2.defeat_settled
	return p1_ok and p2_ok

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
	round_time_left = ROUND_TIME_LIMIT
	round_end_stage  = RoundEndStage.PLAIN
	round_end_winner = 0
	for vs: VsPlayer in [_p1, _p2]:
		vs.hp              = vs.max_hp
		vs.arts_energy     = vs.max_arts_energy
		vs.dash_energy     = vs.max_dash_energy
		vs.post_dash_armor_left = 0.0
		vs.ukemi_cooldown_left = 0.0   # 每回合開始重新可用（受身本身無限次數，只受冷卻限制）
		vs.is_defeated      = false
		vs.defeat_settled   = false
		vs.died_from_hazard = false
		vs.velocity        = Vector2.ZERO
		vs.pending_hit     = {}
		vs.invincible_time_left = 0.5   # 開局 0.5s 無敵，避免立即被打
		vs.hazard_buff_mult = {}   # buff 包效果本身是限時 10 秒（見 VsPlayer.HAZARD_BUFF_DURATION），
		vs.hazard_buff_time_left = {}   # 這裡只是回合邊界的保險清空，避免跨回合殘留

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

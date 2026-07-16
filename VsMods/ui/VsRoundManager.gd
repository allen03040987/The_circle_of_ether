class_name VsRoundManager
extends Node
## 回合管理器（三戰兩勝）
## tick() 由 vs_world 每物理幀呼叫；
## 回合結束時凍結玩家輸入（vs_world 透過 is_fighting() 判斷）。

# ── 設定 ──────────────────────────────────────────────────────────────────────
const ROUNDS_TO_WIN   := 2     # 先贏幾場者得勝
const ROUND_END_DELAY := 2.0   # 回合結算停頓（秒）

# ── 訊號 ──────────────────────────────────────────────────────────────────────
signal round_ended(winner_id: int)    # 0=平手, 1=P1勝, 2=P2勝
signal round_started(round_num: int)
signal match_ended(winner_id: int)    # 1=P1, 2=P2

# ── 狀態 ──────────────────────────────────────────────────────────────────────
enum Phase { FIGHTING, ROUND_END, GAME_OVER }

var p1_wins:   int   = 0
var p2_wins:   int   = 0
var round_num: int   = 1
var phase:     Phase = Phase.FIGHTING

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

func save_state() -> Dictionary:
	return {
		"phase":    phase,
		"p1w":      p1_wins,
		"p2w":      p2_wins,
		"round":    round_num,
		"timer":    _timer,
	}

func restore_state(s: Dictionary) -> void:
	phase     = s["phase"] as Phase
	p1_wins   = s["p1w"]
	p2_wins   = s["p2w"]
	round_num = s["round"]
	_timer    = s["timer"]

# ── 主循環（由 vs_world 每物理幀呼叫）────────────────────────────────────────
func tick(delta: float) -> void:
	match phase:
		Phase.FIGHTING:  _tick_fighting()
		Phase.ROUND_END: _tick_round_end(delta)
		Phase.GAME_OVER: pass

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

	# 繼續下一回合
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
		vs.velocity        = Vector2.ZERO
		vs.pending_hit     = {}
		vs.invincible_time_left = 0.5   # 開局 0.5s 無敵，避免立即被打

	_p1.position = _sp1
	_p2.position = _sp2

	# 強制回 Idle（可能停在 Hurt/Knockdown 狀態）
	_p1.state_machine.transition_to(&"vsidle")
	_p2.state_machine.transition_to(&"vsidle")

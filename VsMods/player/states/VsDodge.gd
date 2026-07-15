class_name VsDodge
extends VsPlayerState
## 閃避狀態
## 前 PERFECT_WINDOW 秒為完美閃避判定窗（玩家無敵 + 受擊觸發獎勵）
## 完美閃避窗結束後仍持續移動，但不再無敵（鼓勵精準時機）

const DODGE_SPEED: float    = 300.0
const DODGE_DURATION: float = 0.35
const PERFECT_WINDOW: float = 0.14  # 與 invincible_time_left 初始值同步

var dodge_dir: int   = 1
var elapsed: float   = 0.0
var _perfect_used: bool = false

func enter(_prev: StringName) -> void:
	elapsed       = 0.0
	_perfect_used = false
	var vs        := player as VsPlayer
	# 以 last_input 決定方向；無移動輸入則沿目前面向
	var lm := vs.last_input.move_dir if vs.last_input else 0.0
	dodge_dir = int(sign(lm)) if lm != 0.0 else vs.facing_dir
	vs.anim_player.play("sliding")
	vs.invincible_time_left = PERFECT_WINDOW

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	player.velocity.x = dodge_dir * DODGE_SPEED
	if not player.is_on_floor():
		_apply_gravity(delta)
	if elapsed >= DODGE_DURATION:
		return &"vsidle" if player.is_on_floor() else &"vsfall"
	return &""

func save_state() -> Dictionary:
	return {"dir": dodge_dir, "elapsed": elapsed, "perfect": _perfect_used}

func restore_state(d: Dictionary) -> void:
	dodge_dir     = d.get("dir",     1)
	elapsed       = d.get("elapsed", 0.0)
	_perfect_used = d.get("perfect", false)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("sliding")
	vs.anim_player.seek(elapsed, true)

## 完美閃避獎勵：由 VsPlayer._on_hurtbox_hurt() 在判定窗內呼叫
func trigger_perfect_dodge() -> void:
	if _perfect_used: return
	_perfect_used = true
	var vs := player as VsPlayer
	vs.energy = minf(vs.energy + 10.0, vs.max_energy)
	vs.invincible_time_left = maxf(vs.invincible_time_left, DODGE_DURATION - elapsed)
	# TODO: 可在此加時間放慢特效（參考主遊戲 Slide.gd::trigger_perfect_dodge）

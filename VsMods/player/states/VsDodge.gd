class_name VsDodge
extends VsPlayerState
## 衝刺狀態
## 消耗 30 點衝刺能量，往前位移，期間不受重力影響。
## 前 PERFECT_WINDOW 秒內受擊 → 觸發完美閃避（invincible_time_left 延伸至整段衝刺）。
## 衝刺正常結束後授予 2 秒強霸體（被打斷則不授予）。

const DODGE_SPEED:    float = 300.0
const DODGE_DURATION: float = 0.35
const PERFECT_WINDOW: float = 0.3   # 完美閃避判定窗（與 invincible_time_left 初始值同步）

var dodge_dir:     int   = 1
var elapsed:       float = 0.0
var _perfect_used: bool  = false
var _completed:    bool  = false   # 是否正常走完整段衝刺（被打斷則為 false）

func enter(_prev: StringName) -> void:
	elapsed        = 0.0
	_perfect_used  = false
	_completed     = false
	var vs         := player as VsPlayer
	# 以 last_input 決定方向；無移動輸入則沿目前面向
	var lm := vs.last_input.move_dir if vs.last_input else 0.0
	dodge_dir = int(sign(lm)) if lm != 0.0 else vs.facing_dir
	vs.anim_player.play("sliding")
	vs.invincible_time_left = PERFECT_WINDOW

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed             += delta
	player.velocity.x    = dodge_dir * DODGE_SPEED
	player.velocity.y    = 0.0   # 衝刺期間不受重力影響
	if elapsed >= DODGE_DURATION:
		_completed = true
		player.velocity.x = 0.0   # 衝刺結束直接停下，不滑行
		return &"vsidle" if _grounded() else &"vsfall"
	return &""

func exit() -> void:
	# 只有正常走完才授予衝刺後強霸體（被擊中打斷則不授予）
	if _completed:
		(player as VsPlayer).post_dash_armor_left = 2.0

func save_state() -> Dictionary:
	return {
		"dir":     dodge_dir,
		"elapsed": elapsed,
		"perfect": _perfect_used,
		"done":    _completed,
	}

func restore_state(d: Dictionary) -> void:
	dodge_dir     = d.get("dir",     1)
	elapsed       = d.get("elapsed", 0.0)
	_perfect_used = d.get("perfect", false)
	_completed    = d.get("done",    false)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("sliding")
	vs.anim_player.seek(elapsed, true)

## 完美閃避：由 VsPlayer._on_hurtbox_hurt() 在判定窗內呼叫
## 將無敵時間延伸至覆蓋整段衝刺剩餘時間
func trigger_perfect_dodge() -> void:
	if _perfect_used: return
	_perfect_used = true
	var vs := player as VsPlayer
	vs.invincible_time_left = maxf(vs.invincible_time_left, DODGE_DURATION - elapsed)

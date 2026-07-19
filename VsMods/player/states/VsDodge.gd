class_name VsDodge
extends VsPlayerState
## 衝刺狀態
## 消耗 30 點衝刺能量，往前位移，期間不受重力影響。
## 前 PERFECT_WINDOW 秒內受擊 → 觸發完美閃避：(1) 無敵延伸至整段衝刺、
## (2) 結束後再給 2 秒強霸體。兩者都綁在「有沒有被打到」上——沒被打到、
## 或雖被打到但衝刺被打斷，都不給結束後強霸體。

const DODGE_DURATION: float = 0.35
const PERFECT_WINDOW: float = 0.3   # 完美閃避判定窗（與 invincible_time_left 初始值同步）
const GHOST_INTERVAL: float = 0.05  # 殘影間隔（秒），比照主遊戲 Slide.gd

const SLIDING_SFX_2 := preload("res://sound/SFX/sprint.wav")
const SLIDING_SFX_3 := preload("res://sound/SFX/attack/wind_2.wav")
const SUCCESS_SFX := preload("res://sound/SFX/Successfully_dodged.wav")

var dodge_dir:     int   = 1
var elapsed:       float = 0.0
var _perfect_used: bool  = false
var _completed:    bool  = false   # 是否正常走完整段衝刺（被打斷則為 false）
var _ghost_timer:  float = 0.0

func enter(_prev: StringName) -> void:
	elapsed        = 0.0
	_perfect_used  = false
	_completed     = false
	_ghost_timer   = 0.0
	var vs         := player as VsPlayer
	# 以 last_input 決定方向；無移動輸入則沿目前面向
	var lm := vs.last_input.move_dir if vs.last_input else 0.0
	dodge_dir = int(sign(lm)) if lm != 0.0 else vs.facing_dir
	# 動畫朝向要跟移動方向一致：沒這行的話，若衝刺前面向跟 dodge_dir 不同
	# （例如剛轉身瞬間衝刺），畫面會出現「朝左的滑動動畫、卻往右衝」
	vs.facing_dir = dodge_dir
	vs.anim_player.play("sliding")
	vs.invincible_time_left = PERFECT_WINDOW
	vs.vfx_sfx(SLIDING_SFX_2, -12.0)
	vs.vfx_sfx(SLIDING_SFX_3, -8.0)

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed             += delta
	player.velocity.x    = dodge_dir * (player as VsPlayer).dodge_speed
	player.velocity.y    = 0.0   # 衝刺期間不受重力影響

	_ghost_timer += delta
	if _ghost_timer >= GHOST_INTERVAL:
		_ghost_timer -= GHOST_INTERVAL
		(player as VsPlayer).vfx_ghost()

	if elapsed >= DODGE_DURATION:
		_completed = true
		player.velocity.x = 0.0   # 衝刺結束直接停下，不滑行
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""

func exit() -> void:
	# 結束後強霸體：必須「正常走完」且「前 0.3s 有觸發完美閃避」兩者皆成立
	if _completed and _perfect_used:
		(player as VsPlayer).post_dash_armor_left = 2.0

func save_state() -> Dictionary:
	return {
		"dir":     dodge_dir,
		"elapsed": elapsed,
		"perfect": _perfect_used,
		"done":    _completed,
		"gt":      _ghost_timer,
	}

func restore_state(d: Dictionary) -> void:
	dodge_dir     = d.get("dir",     1)
	elapsed       = d.get("elapsed", 0.0)
	_perfect_used = d.get("perfect", false)
	_completed    = d.get("done",    false)
	_ghost_timer  = d.get("gt",      0.0)

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
	vs.vfx_dodge_spark()
	vs.vfx_sfx(SUCCESS_SFX)

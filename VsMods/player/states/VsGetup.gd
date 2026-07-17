class_name VsGetup
extends VsPlayerState
## 起身狀態（倒地滿時自動進入）
## 規則：起身時給予 2 秒無敵（延續到起身動畫結束後的操作）；
## 起身期間可用衝刺打斷，但無敵提前結束（衝刺自己的完美閃避窗照舊）。

const GETUP_INVINCIBILITY: float = 2.0  # 起身給予的無敵時長（秒）

var elapsed:   float = 0.0
var _duration: float = 0.3   # 起身時長 = launched_2 動畫長度（enter/restore 時讀取）

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	vs.invincible_time_left = GETUP_INVINCIBILITY
	vs.anim_player.play("launched_2")
	_duration = vs.anim_player.get_animation("launched_2").length

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed   = d.get("elapsed", 0.0)
	_duration = (player as VsPlayer).anim_player.get_animation("launched_2").length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("launched_2")
	vs.anim_player.seek(elapsed, true)

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	# 承接倒地彈起的殘留滑行動量，摩擦減速（不瞬間黏住）
	player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * 1.5 * delta)
	# 衝刺打斷起身：無敵提前結束（VsDodge.enter 會另設它自己的完美閃避窗）
	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		vs.invincible_time_left = 0.0
		return &"vsdodge"
	if elapsed >= _duration:
		return &"vsidle"
	return &""

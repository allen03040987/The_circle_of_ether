class_name VsHurt
extends VsPlayerState
## 受擊硬直狀態
## 硬直結束後若仍在空中→ VsFall；落地→ VsIdle

var elapsed: float      = 0.0
var hitstun_time: float = 0.4

func enter(_prev: StringName) -> void:
	elapsed      = 0.0
	var vs       := player as VsPlayer
	hitstun_time = vs.queued_hitstun
	vs.anim_player.play("hurt")
	vs.invincible_time_left = 0.15  # 短暫無敵防連擊穿透

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * 1.5 * delta)
	_apply_gravity(delta)
	if elapsed >= hitstun_time:
		return &"vsidle" if player.is_on_floor() else &"vsfall"
	return &""

func exit() -> void:
	# 離場後補緩衝無敵，防止動畫剛結束就再次被擊中
	var vs := player as VsPlayer
	vs.invincible_time_left = maxf(vs.invincible_time_left, 0.2)

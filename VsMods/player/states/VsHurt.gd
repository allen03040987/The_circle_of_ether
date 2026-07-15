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
	var vs := player as VsPlayer
	vs.invincible_time_left = maxf(vs.invincible_time_left, 0.2)

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "hitstun": hitstun_time}

func restore_state(d: Dictionary) -> void:
	elapsed      = d.get("elapsed", 0.0)
	hitstun_time = d.get("hitstun",  0.4)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("hurt")
	vs.anim_player.seek(elapsed, true)

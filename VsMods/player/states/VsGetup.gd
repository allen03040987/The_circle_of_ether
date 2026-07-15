class_name VsGetup
extends VsPlayerState
## 起身狀態（倒地後自動進入）
## 起身期間全程無敵

const GETUP_DURATION: float = 0.4

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	vs.invincible_time_left = GETUP_DURATION + 0.1
	vs.anim_player.play("idle")

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
	if elapsed >= GETUP_DURATION:
		return &"vsidle"
	return &""

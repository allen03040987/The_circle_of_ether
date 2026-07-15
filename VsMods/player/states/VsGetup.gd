class_name VsGetup
extends VsPlayerState
## 起身狀態（倒地後自動進入）
## 起身期間全程無敵

const GETUP_DURATION: float = 0.4

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	# 起身期間無敵（多留 0.1s 緩衝讓動畫先播完再可被擊）
	vs.invincible_time_left = GETUP_DURATION + 0.1
	# TODO: 起身動畫，目前暫用 idle
	vs.anim_player.play("idle")

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
	if elapsed >= GETUP_DURATION:
		return &"vsidle"
	return &""

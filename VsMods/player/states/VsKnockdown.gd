class_name VsKnockdown
extends VsPlayerState
## 倒地狀態（causes_knockdown = true 的攻擊觸發）
## 趴地一段時間後自動進入 VsGetup

const KNOCKDOWN_DURATION: float = 1.2  # 趴地時長（秒）

var elapsed: float = 0.0

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs  := player as VsPlayer
	vs.anim_player.play("launched")
	vs.invincible_time_left = 0.5

func save_state() -> Dictionary:
	return {"elapsed": elapsed}

func restore_state(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("launched")

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
		player.velocity.y = 0.0
	else:
		_apply_gravity(delta)
	if elapsed >= KNOCKDOWN_DURATION:
		return &"vsgetup"
	return &""
